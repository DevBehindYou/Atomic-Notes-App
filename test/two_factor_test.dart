// Two-factor rules: what turns it on, what is stored, and how wrong tries are
// handled. The keystore and clock are replaced, so nothing here touches the
// device.

import 'package:atomic_notes/security/two_factor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/two_factor_fakes.dart';

void main() {
  late FakeTwoFactorStorage storage;
  late TestClock clock;
  late TwoFactor tf;

  setUp(() {
    storage = FakeTwoFactorStorage();
    clock = TestClock();
    tf = makeTwoFactor(storage, clock);
  });

  group('setup', () {
    test('a wrong code turns nothing on', () async {
      final setup = tf.beginSetup();
      final wrong = await wrongCodeAt(setup.secret, clock.now);

      expect(await tf.confirmSetup(wrong), isNull);
      expect(tf.isArmed, isFalse);
      expect(storage.state, isEmpty);
    });

    test('the right code turns it on and returns eight recovery codes',
        () async {
      final on = await turnOn(tf, clock);

      expect(tf.isArmed, isTrue);
      expect(on.codes.length, TwoFactor.recoveryCodeCount);
      expect(on.codes.toSet().length, TwoFactor.recoveryCodeCount);
      final shape = RegExp(r'^[A-HJKMNP-Z2-9]{5}-[A-HJKMNP-Z2-9]{5}$');
      for (final code in on.codes) {
        expect(shape.hasMatch(code), isTrue, reason: code);
      }
      expect(await tf.recoveryCodesLeft(), TwoFactor.recoveryCodeCount);
    });

    test('recovery codes are stored only as hashes', () async {
      final on = await turnOn(tf, clock);
      final stored = storage.state[testAccount]!;

      for (final code in on.codes) {
        expect(stored.contains(code), isFalse);
        expect(stored.contains(code.replaceAll('-', '')), isFalse);
      }
    });

    test('a setup that is cancelled stores nothing', () async {
      final setup = tf.beginSetup();
      tf.cancelSetup();

      expect(await tf.confirmSetup(await codeAt(setup.secret, clock.now)),
          isNull);
      expect(tf.isArmed, isFalse);
      expect(storage.state, isEmpty);
    });

    test('listeners hear when it turns on', () async {
      int heard = 0;
      tf.addListener(() => heard++);
      await turnOn(tf, clock);
      expect(heard, greaterThan(0));
    });
  });

  group('checking a code', () {
    test('the next code is accepted', () async {
      final on = await turnOn(tf, clock);
      clock.advance(const Duration(seconds: 30));

      final result = await tf.check(await codeAt(on.secret, clock.now));
      expect(result.result, TwoFactorResult.ok);
      expect(result.usedRecoveryCode, isFalse);
    });

    test('a code cannot be used twice', () async {
      final on = await turnOn(tf, clock);
      clock.advance(const Duration(seconds: 30));
      final code = await codeAt(on.secret, clock.now);

      expect((await tf.check(code)).ok, isTrue);
      expect((await tf.check(code)).result, TwoFactorResult.wrong);
    });

    test('the code that confirmed setup cannot open the app', () async {
      final on = await turnOn(tf, clock);

      final result = await tf.check(await codeAt(on.secret, clock.now));
      expect(result.result, TwoFactorResult.wrong);
    });

    test('a wrong code is refused', () async {
      final on = await turnOn(tf, clock);
      final wrong = await wrongCodeAt(on.secret, clock.now);

      expect((await tf.check(wrong)).result, TwoFactorResult.wrong);
    });

    test('a recovery code works once', () async {
      final on = await turnOn(tf, clock);

      final first = await tf.check(on.codes.first);
      expect(first.ok, isTrue);
      expect(first.usedRecoveryCode, isTrue);
      expect(await tf.recoveryCodesLeft(), TwoFactor.recoveryCodeCount - 1);
      expect((await tf.check(on.codes.first)).result, TwoFactorResult.wrong);
    });

    test('a recovery code is accepted in lower case and without the dash',
        () async {
      final on = await turnOn(tf, clock);
      final typed = on.codes[3].toLowerCase().replaceAll('-', '');

      expect((await tf.check(typed)).ok, isTrue);
    });

    test('nothing is accepted for an empty entry', () async {
      await turnOn(tf, clock);
      expect((await tf.check('')).result, TwoFactorResult.wrong);
    });
  });

  group('wrong tries', () {
    test('five wrong tries lock for 30 seconds, then 60', () async {
      final on = await turnOn(tf, clock);
      final wrong = await wrongCodeAt(on.secret, clock.now);

      for (int i = 0; i < 4; i++) {
        expect((await tf.check(wrong)).result, TwoFactorResult.wrong);
      }
      final fifth = await tf.check(wrong);
      expect(fifth.result, TwoFactorResult.locked);
      expect(fifth.retryAfter, const Duration(seconds: 30));

      // The right answer does not get through while locked.
      clock.advance(const Duration(seconds: 10));
      final during = await tf.check(await codeAt(on.secret, clock.now));
      expect(during.result, TwoFactorResult.locked);

      // Once it ends, five more wrong tries lock for twice as long.
      clock.advance(const Duration(seconds: 21));
      final again = await wrongCodeAt(on.secret, clock.now);
      for (int i = 0; i < 4; i++) {
        expect((await tf.check(again)).result, TwoFactorResult.wrong);
      }
      final tenth = await tf.check(again);
      expect(tenth.result, TwoFactorResult.locked);
      expect(tenth.retryAfter, const Duration(seconds: 60));
    });

    test('a right code clears the count', () async {
      final on = await turnOn(tf, clock);
      final wrong = await wrongCodeAt(on.secret, clock.now);
      for (int i = 0; i < 4; i++) {
        await tf.check(wrong);
      }

      clock.advance(const Duration(seconds: 30));
      expect((await tf.check(await codeAt(on.secret, clock.now))).ok, isTrue);

      // Four more wrong tries are not enough to lock: the count started over.
      final next = await wrongCodeAt(on.secret, clock.now);
      for (int i = 0; i < 4; i++) {
        expect((await tf.check(next)).result, TwoFactorResult.wrong);
      }
    });

    test('the lock survives a restart', () async {
      final on = await turnOn(tf, clock);
      final wrong = await wrongCodeAt(on.secret, clock.now);
      for (int i = 0; i < 5; i++) {
        await tf.check(wrong);
      }

      // A new object over the same storage, as after the app is reopened.
      final reopened = makeTwoFactor(storage, clock);
      final result = await reopened.check(await codeAt(on.secret, clock.now));
      expect(result.result, TwoFactorResult.locked);
    });
  });

  group('turning it off and new codes', () {
    test('turning off needs a valid code', () async {
      final on = await turnOn(tf, clock);
      final wrong = await wrongCodeAt(on.secret, clock.now);

      expect((await tf.disable(wrong)).result, TwoFactorResult.wrong);
      expect(tf.isArmed, isTrue);

      clock.advance(const Duration(seconds: 30));
      expect((await tf.disable(await codeAt(on.secret, clock.now))).ok, isTrue);
      expect(tf.isArmed, isFalse);
      expect(storage.state, isEmpty);
    });

    test('a recovery code can turn it off', () async {
      final on = await turnOn(tf, clock);

      expect((await tf.disable(on.codes.last)).ok, isTrue);
      expect(tf.isArmed, isFalse);
    });

    test('new recovery codes replace the old ones', () async {
      final on = await turnOn(tf, clock);
      clock.advance(const Duration(seconds: 30));

      final result =
          await tf.regenerateRecoveryCodes(await codeAt(on.secret, clock.now));
      expect(result.ok, isTrue);
      expect(result.codes!.length, TwoFactor.recoveryCodeCount);
      expect(result.codes!.toSet().intersection(on.codes.toSet()), isEmpty);

      expect((await tf.check(on.codes.first)).result, TwoFactorResult.wrong);
      expect((await tf.check(result.codes!.first)).ok, isTrue);
    });

    test('new recovery codes need a valid code', () async {
      final on = await turnOn(tf, clock);
      final wrong = await wrongCodeAt(on.secret, clock.now);

      final result = await tf.regenerateRecoveryCodes(wrong);
      expect(result.result, TwoFactorResult.wrong);
      expect(result.codes, isNull);
    });
  });

  group('when the key cannot be read', () {
    test('nothing can be checked, and it can be reset', () async {
      final on = await turnOn(tf, clock);
      storage.failReads = true;

      expect(await tf.hasVerificationData(), isFalse);
      expect(await tf.recoveryCodesLeft(), isNull);
      expect((await tf.check(on.codes.first)).result,
          TwoFactorResult.unavailable);
      // The flag is still on, which is what tells this apart from "never on".
      expect(tf.isArmed, isTrue);

      await tf.resetOnThisDevice();
      expect(tf.isArmed, isFalse);
    });

    test('a corrupted stored key counts as unreadable', () async {
      await turnOn(tf, clock);
      storage.state[testAccount] = '{"secret":"not base32!","recovery":[]}';

      expect(await tf.hasVerificationData(), isFalse);
    });
  });

  test('with no account there is nothing to arm or check', () async {
    final signedOut = TwoFactor(
      storage: storage,
      account: () => null,
      clock: clock.call,
    );

    expect(signedOut.isArmed, isFalse);
    expect(await signedOut.hasVerificationData(), isFalse);
    expect((await signedOut.check('123456')).result,
        TwoFactorResult.unavailable);
  });
}
