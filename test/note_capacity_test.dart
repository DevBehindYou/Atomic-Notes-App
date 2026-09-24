// Note capacity: the Server decides the limit and its price; the App shows it
// and offers the next step. The purchase itself is a Server call and is tested
// there; these check what the App does with the numbers it is given.

import 'package:atomic_notes/database/energy_models.dart';
import 'package:atomic_notes/database/energy_service.dart';
import 'package:atomic_notes/database/note_quota.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/page/endpage/energy_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Tall on purpose: the whole screen is on view, so nothing has to be scrolled to.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _wallet({int coins = 30, int noteLimit = 20}) {
  EnergyService.instance.debugSet(
    wallet: Wallet(
      coins: coins,
      energy: 50,
      energyCap: 120,
      lastDailyGrantAt: null,
      noteLimit: noteLimit,
    ),
    limits: const EnergyLimits(),
  );
}

void main() {
  tearDown(() async {
    EnergyService.instance.debugSet(wallet: Wallet.empty);
    await NoteQuota.reset();
  });

  group('what the Server sends', () {
    test('the wallet carries the note limit, 20 when it is absent', () {
      expect(Wallet.fromMap({'coins': 1, 'note_limit': 40}).noteLimit, 40);
      expect(Wallet.fromMap({'coins': 1}).noteLimit, 20);
    });

    test('the limits carry the named tiers and the ceiling', () {
      final l = EnergyLimits.fromMap({
        'note_limit_free': 20,
        'note_limit_ceiling': 100,
        'note_limit_tiers': [
          {'limit': 20, 'name': 'Tachyon', 'cost_coins': 0},
          {'limit': 30, 'name': 'God', 'cost_coins': 10},
          {'limit': 100, 'name': 'Strangelet', 'cost_coins': 50},
        ],
        'sync_standard_cost': 5,
        'sync_instant_cost': 10,
        'sync_standard_interval_seconds': 3600,
      });
      expect([l.noteLimitFree, l.noteLimitCeiling], [20, 100]);
      expect(l.tiers.map((t) => t.name), ['Tachyon', 'God', 'Strangelet']);
      expect(l.tiers.map((t) => t.limit), [20, 30, 100]);
      expect(l.tiers.map((t) => t.costCoins), [0, 10, 50]);
      expect([l.syncStandardCost, l.syncInstantCost], [5, 10]);
      expect(l.syncStandardIntervalSeconds, 3600);
    });

    test('a missing field falls back to the defaults', () {
      final l = EnergyLimits.fromMap({});
      expect(l.noteLimitCeiling, 100);
      expect(l.tiers, EnergyLimits.defaultTiers);
      expect(l.syncInstantCost, 10);
    });
  });

  group('the next tier', () {
    test('goes Tachyon, God, Antimatter, Monopole, Strangelet and stops at the ceiling', () {
      final steps = <int>[];
      for (final limit in [20, 30, 40, 50, 100]) {
        _wallet(noteLimit: limit);
        steps.add(EnergyService.instance.nextNoteLimit);
      }
      expect(steps, [30, 40, 50, 100, 100]);
      expect(EnergyService.instance.canRaiseNoteLimit, isFalse);
    });

    test('needs the next tier\'s coins, not a flat price', () {
      _wallet(noteLimit: 20, coins: 9);
      expect(EnergyService.instance.canAffordNoteLimit, isFalse);
      _wallet(noteLimit: 20, coins: 10);
      expect(EnergyService.instance.canAffordNoteLimit, isTrue);

      // The last tier (Strangelet) costs 50, not 10 like the others.
      _wallet(noteLimit: 50, coins: 10);
      expect(EnergyService.instance.canAffordNoteLimit, isFalse);
      _wallet(noteLimit: 50, coins: 50);
      expect(EnergyService.instance.canAffordNoteLimit, isTrue);
    });

    test('the note quota follows the wallet', () {
      _wallet(noteLimit: 40);
      expect(NoteQuota.limit, 40);
    });

    test('the notes screen hears about a new limit at once', () {
      int heard = 0;
      void listener() => heard++;
      NotesRepository.instance.addListener(listener);
      addTearDown(() => NotesRepository.instance.removeListener(listener));

      _wallet(noteLimit: 30);
      expect(NotesRepository.instance.usageLabel, '0 / 30');
      expect(heard, 1);
      // The same limit again is not news.
      _wallet(noteLimit: 30);
      expect(heard, 1);
    });
  });

  group('Atomic Energy screen', () {
    Future<void> open(WidgetTester tester) async {
      _phone(tester);
      await tester.pumpWidget(const MaterialApp(home: EnergyPage()));
      await tester.pump();
    }

    testWidgets('shows the five tiers and offers the next one', (tester) async {
      _wallet(noteLimit: 30);
      await open(tester);

      for (final v in [20, 30, 40, 50, 100]) {
        expect(find.byKey(ValueKey('capacity-$v')), findsOneWidget, reason: '$v');
      }
      expect(find.text('0 of 30 notes used'), findsOneWidget);
      expect(find.text('UNLOCK ANTIMATTER  ·  40 NOTES  ·  10 COINS'),
          findsOneWidget);
    });

    testWidgets('asks before spending coins', (tester) async {
      _wallet();
      await open(tester);

      await tester.tap(find.text('UNLOCK GOD  ·  30 NOTES  ·  10 COINS'));
      await tester.pumpAndSettle();
      expect(
        find.text('Spend 10 coins to raise your note limit from 20 to 30 (God)?'),
        findsOneWidget,
      );

      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(EnergyService.instance.noteLimit, 20);
      expect(EnergyService.instance.coins, 30);
    });

    testWidgets('says what is missing when there are too few coins',
        (tester) async {
      _wallet(coins: 2);
      await open(tester);

      await tester.tap(find.text('UNLOCK GOD  ·  30 NOTES  ·  10 COINS'));
      await tester.pump();
      expect(
          find.text('The next tier (God, 30 notes) costs 10 coins. You have 2.'),
          findsOneWidget);
    });

    testWidgets('offers nothing at the ceiling', (tester) async {
      _wallet(noteLimit: 100);
      await open(tester);

      expect(find.text('This is the most notes an account can hold.'),
          findsOneWidget);
      expect(find.text('UNLOCK STRANGELET  ·  100 NOTES  ·  50 COINS'),
          findsNothing);
    });
  });
}
