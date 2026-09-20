// The two-factor screens end to end, over a fake keystore and a clock the test
// moves by hand: turning it on, the code prompt at launch, and turning it off.

import 'package:atomic_notes/page/endpage/two_factor_gate_page.dart';
import 'package:atomic_notes/page/endpage/two_factor_page.dart';
import 'package:atomic_notes/security/two_factor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'support/two_factor_fakes.dart';

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Lets the awaits inside the page finish.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  late FakeTwoFactorStorage storage;
  late TestClock clock;
  late TwoFactor tf;

  setUp(() {
    storage = FakeTwoFactorStorage();
    clock = TestClock();
    tf = makeTwoFactor(storage, clock);
  });

  group('setup page', () {
    testWidgets('turns it on, shows the codes once, then turns it off',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(MaterialApp(home: TwoFactorPage(twoFactor: tf)));
      await _settle(tester);

      // Off: the explanation and the way in.
      expect(find.text('OFF'), findsOneWidget);
      await tester.tap(find.text('SET UP TWO-FACTOR'));
      await _settle(tester);

      // Step 1: a QR code and the key to type instead.
      expect(find.text('STEP 1 · ADD TO YOUR APP'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      final String key = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!
          .replaceAll(' ', '');
      expect(key.length, greaterThanOrEqualTo(32));

      // A wrong code is refused with a message.
      final String wrong = (await tester.runAsync(
        () => wrongCodeAt(key, clock.now),
      ))!;
      await tester.enterText(find.byType(TextField), wrong);
      await _settle(tester);
      expect(find.textContaining("didn't match"), findsOneWidget);
      expect(tf.isArmed, isFalse);

      // The right one turns it on and shows the recovery codes.
      final String right =
          (await tester.runAsync(() => codeAt(key, clock.now)))!;
      await tester.enterText(find.byType(TextField), right);
      await _settle(tester);

      expect(tf.isArmed, isTrue);
      expect(find.text('SAVE THESE NOW.'), findsOneWidget);
      expect(find.byType(SelectableText), findsNWidgets(8));

      // Done stays shut until the codes are marked as saved.
      await tester.tap(find.text('DONE'));
      await _settle(tester);
      expect(find.text('SAVE THESE NOW.'), findsOneWidget);
      await tester.tap(find.text('I saved these codes somewhere safe'));
      await tester.pump();
      await tester.tap(find.text('DONE'));
      await _settle(tester);

      // On: status and the count of codes left.
      expect(find.text('TWO-FACTOR IS ON'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);

      // Turning it off asks for a fresh code.
      clock.advance(const Duration(seconds: 30));
      await tester.tap(find.text('TURN OFF TWO-FACTOR'));
      await tester.pumpAndSettle();
      final String again =
          (await tester.runAsync(() => codeAt(key, clock.now)))!;
      await tester.enterText(find.byType(TextField), again);
      await _settle(tester);
      await tester.pumpAndSettle();

      expect(tf.isArmed, isFalse);
      expect(find.text('SET UP TWO-FACTOR'), findsOneWidget);
    });

    testWidgets('cancelling a setup stores nothing', (tester) async {
      _phone(tester);
      await tester.pumpWidget(MaterialApp(home: TwoFactorPage(twoFactor: tf)));
      await _settle(tester);

      await tester.tap(find.text('SET UP TWO-FACTOR'));
      await _settle(tester);
      await tester.ensureVisible(find.text('CANCEL'));
      await tester.tap(find.text('CANCEL'));
      await _settle(tester);

      expect(find.text('SET UP TWO-FACTOR'), findsOneWidget);
      expect(tf.isArmed, isFalse);
      expect(storage.state, isEmpty);
    });
  });

  group('code prompt at launch', () {
    Future<({String secret, List<String> codes})> armed(
        WidgetTester tester) async {
      final on = (await tester.runAsync(() => turnOn(tf, clock)))!;
      clock.advance(const Duration(seconds: 30));
      return on;
    }

    Future<void> openGate(WidgetTester tester) async {
      _phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          routes: {'/mainpage': (_) => const Scaffold(body: Text('MAIN'))},
          home: TwoFactorGatePage(twoFactor: tf),
        ),
      );
      await _settle(tester);
    }

    testWidgets('the right code opens the app', (tester) async {
      final on = await armed(tester);
      await openGate(tester);

      final String code =
          (await tester.runAsync(() => codeAt(on.secret, clock.now)))!;
      await tester.enterText(find.byType(TextField), code);
      await _settle(tester);
      await tester.pumpAndSettle();

      expect(find.text('MAIN'), findsOneWidget);
    });

    testWidgets('a wrong code stays on the prompt with a message',
        (tester) async {
      final on = await armed(tester);
      await openGate(tester);

      final String wrong = (await tester.runAsync(
        () => wrongCodeAt(on.secret, clock.now),
      ))!;
      await tester.enterText(find.byType(TextField), wrong);
      await _settle(tester);

      expect(find.textContaining("didn't match"), findsOneWidget);
      expect(find.text('MAIN'), findsNothing);
    });

    testWidgets('a recovery code opens the app', (tester) async {
      final on = await armed(tester);
      await openGate(tester);

      await tester.tap(find.text('USE A RECOVERY CODE'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), on.codes.first);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      await tester.pumpAndSettle();

      expect(find.text('MAIN'), findsOneWidget);
    });

    testWidgets('five wrong codes lock the prompt', (tester) async {
      final on = await armed(tester);
      await openGate(tester);

      final String wrong = (await tester.runAsync(
        () => wrongCodeAt(on.secret, clock.now),
      ))!;
      for (int i = 0; i < 5; i++) {
        await tester.enterText(find.byType(TextField), wrong);
        await _settle(tester);
      }

      expect(find.textContaining('Too many wrong tries'), findsOneWidget);
    });

    testWidgets('an unreadable key offers a retry and a reset', (tester) async {
      await armed(tester);
      storage.failReads = true;
      await openGate(tester);

      expect(find.text('KEY UNAVAILABLE'), findsOneWidget);
      expect(find.text('TRY AGAIN'), findsOneWidget);
      expect(find.text('TURN OFF ON THIS DEVICE'), findsOneWidget);
    });
  });
}
