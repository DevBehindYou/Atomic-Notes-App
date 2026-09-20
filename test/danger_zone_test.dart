// Widget tests for the Danger Zone and its slide-to-confirm control. They need
// neither Hive nor the network: with no signed-in user the cloud wipe returns
// "Not signed in." before it touches anything.

import 'package:atomic_notes/page/endpage/danger_zone_page.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/component/slide_to_confirm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SlideToConfirm', () {
    Future<void> pumpSlider(
        WidgetTester tester, Future<void> Function() onConfirmed) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: SlideToConfirm(label: 'wipe', onConfirmed: onConfirmed),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a short slide snaps back and confirms nothing',
        (tester) async {
      var confirmed = 0;
      await pumpSlider(tester, () async => confirmed++);
      await tester.drag(
          find.byKey(SlideToConfirm.thumbKey), const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(confirmed, 0);
    });

    testWidgets('sliding all the way confirms exactly once', (tester) async {
      var confirmed = 0;
      await pumpSlider(tester, () async => confirmed++);
      await tester.drag(
          find.byKey(SlideToConfirm.thumbKey), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(confirmed, 1);
    });
  });

  group('Danger Zone page', () {
    Future<void> pumpPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: DangerZonePage()));
    }

    testWidgets('offers the two wipe actions and nothing else',
        (tester) async {
      await pumpPage(tester);
      // Each title appears on its card and on its button.
      expect(find.text('WIPE CLOUD NOTES'), findsNWidgets(2));
      expect(find.text('WIPE LOCAL NOTES'), findsNWidgets(2));
      expect(find.text('DEVELOPER OPTIONS'), findsNothing);
      expect(find.text('SYNC WITH CLOUD'), findsNothing);
    });

    testWidgets('the popup can be cancelled without running anything',
        (tester) async {
      await pumpPage(tester);
      await tester.tap(find.widgetWithText(InkActionButton, 'WIPE CLOUD NOTES'));
      await tester.pumpAndSettle();
      expect(find.text('FINAL CONFIRMATION'), findsOneWidget);
      expect(find.byType(SlideToConfirm), findsOneWidget);

      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(find.byType(SlideToConfirm), findsNothing);
    });

    testWidgets('the cloud wipe runs only after the slide', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.widgetWithText(InkActionButton, 'WIPE CLOUD NOTES'));
      await tester.pumpAndSettle();
      // Nothing has run yet: no result message.
      expect(find.text('Not signed in.'), findsNothing);

      await tester.drag(
          find.byKey(SlideToConfirm.thumbKey), const Offset(600, 0));
      await tester.pumpAndSettle();
      // The popup closed and the outcome was reported.
      expect(find.byType(SlideToConfirm), findsNothing);
      expect(find.text('Not signed in.'), findsOneWidget);
    });
  });
}
