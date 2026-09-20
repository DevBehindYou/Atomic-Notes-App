import 'dart:math';

import 'package:atomic_notes/security/totp.dart';
import 'package:atomic_notes/security/two_factor.dart';

/// In-memory stand-in for the keystore and the armed flag.
class FakeTwoFactorStorage implements TwoFactorStorage {
  final Map<String, String> state = {};
  final Set<String> armed = {};

  /// Simulates a keystore that cannot be read (a restore, a system reset).
  bool failReads = false;

  @override
  Future<String?> readState(String account) async {
    if (failReads) throw StateError('keystore unavailable');
    return state[account];
  }

  @override
  Future<void> writeState(String account, String json) async {
    state[account] = json;
  }

  @override
  Future<void> deleteState(String account) async {
    state.remove(account);
  }

  @override
  bool isArmed(String account) => armed.contains(account);

  @override
  Future<void> setArmed(String account, bool value) async {
    if (value) {
      armed.add(account);
    } else {
      armed.remove(account);
    }
  }
}

/// A clock the test moves by hand.
class TestClock {
  DateTime now = DateTime.utc(2026, 1, 1, 12);

  DateTime call() => now;

  void advance(Duration by) {
    now = now.add(by);
  }
}

const String testAccount = 'acct';

TwoFactor makeTwoFactor(FakeTwoFactorStorage storage, TestClock clock) {
  return TwoFactor(
    storage: storage,
    account: () => testAccount,
    label: () => 'me@example.com',
    clock: clock.call,
    random: Random(7),
  );
}

/// The code an authenticator app would show for [secret] at [at].
Future<String> codeAt(String secret, DateTime at) {
  return Totp.codeForStep(Totp.base32Decode(secret), Totp.stepFor(at));
}

/// A six-digit code that is not valid at [at], nor one step either side.
Future<String> wrongCodeAt(String secret, DateTime at) async {
  final key = Totp.base32Decode(secret);
  final int step = Totp.stepFor(at);
  final valid = {
    for (int s = step - 1; s <= step + 1; s++) await Totp.codeForStep(key, s),
  };
  return ['000000', '111111', '222222'].firstWhere((c) => !valid.contains(c));
}

/// Runs the whole setup and returns the key and the recovery codes.
Future<({String secret, List<String> codes})> turnOn(
  TwoFactor tf,
  TestClock clock,
) async {
  final setup = tf.beginSetup();
  final codes = await tf.confirmSetup(await codeAt(setup.secret, clock.now));
  if (codes == null) throw StateError('setup did not confirm');
  return (secret: setup.secret, codes: codes);
}
