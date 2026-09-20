import 'dart:convert';
import 'dart:math';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/security/secure_options.dart';
import 'package:atomic_notes/security/totp.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive_ce.dart';

/// Where two-factor state is kept. A seam so tests do not need a keystore.
///
/// Two places on purpose. The secret, the recovery-code hashes and the attempt
/// counters are sensitive and go to the OS keystore. Whether the gate is armed
/// is not sensitive and must be readable even when the keystore is not, so an
/// unreadable keystore can be told apart from "never turned on".
abstract class TwoFactorStorage {
  Future<String?> readState(String account);
  Future<void> writeState(String account, String json);
  Future<void> deleteState(String account);
  bool isArmed(String account);
  Future<void> setArmed(String account, bool armed);
}

class DeviceTwoFactorStorage implements TwoFactorStorage {
  const DeviceTwoFactorStorage();

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: kSecureAndroidOptions,
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static String _stateKey(String account) => 'atomic_2fa_$account';
  static String _flagKey(String account) => 'twoFactorOn_$account';

  @override
  Future<String?> readState(String account) =>
      _secure.read(key: _stateKey(account));

  @override
  Future<void> writeState(String account, String json) =>
      _secure.write(key: _stateKey(account), value: json);

  @override
  Future<void> deleteState(String account) =>
      _secure.delete(key: _stateKey(account));

  @override
  bool isArmed(String account) {
    if (!Hive.isBoxOpen('authBox')) return false;
    return Hive.box<bool>('authBox').get(_flagKey(account)) ?? false;
  }

  @override
  Future<void> setArmed(String account, bool armed) async {
    final box = await Hive.openBox<bool>('authBox');
    if (armed) {
      await box.put(_flagKey(account), true);
    } else {
      await box.delete(_flagKey(account));
    }
  }
}

enum TwoFactorResult {
  /// The code or recovery code was right.
  ok,

  /// It was wrong.
  wrong,

  /// Too many wrong tries; see [TwoFactorCheck.retryAfter].
  locked,

  /// The key on this device cannot be read, so nothing can be checked.
  unavailable,
}

class TwoFactorCheck {
  final TwoFactorResult result;
  final Duration? retryAfter;
  final bool usedRecoveryCode;

  /// Fresh recovery codes, set only by [TwoFactor.regenerateRecoveryCodes].
  final List<String>? codes;

  const TwoFactorCheck(
    this.result, {
    this.retryAfter,
    this.usedRecoveryCode = false,
    this.codes,
  });

  bool get ok => result == TwoFactorResult.ok;
}

/// What the setup screen shows while the user adds the account to an
/// authenticator app. Nothing is stored until a code from that app is proven.
class TwoFactorSetup {
  /// The key, base32, for typing into an authenticator app by hand.
  final String secret;

  /// The `otpauth://` address behind the QR code.
  final String uri;

  const TwoFactorSetup({required this.secret, required this.uri});
}

class _Data {
  _Data({
    required this.secret,
    required this.recovery,
    this.lastStep = -1,
    this.failures = 0,
    this.lockedUntil = 0,
  });

  final String secret;
  final List<String> recovery;
  int lastStep;
  int failures;
  int lockedUntil;

  String toJson() => jsonEncode({
        'secret': secret,
        'recovery': recovery,
        'lastStep': lastStep,
        'failures': failures,
        'lockedUntil': lockedUntil,
      });

  static _Data? parse(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final String secret = m['secret'] as String;
      // A stored key that no longer decodes is as good as missing.
      Totp.base32Decode(secret);
      return _Data(
        secret: secret,
        recovery: (m['recovery'] as List).cast<String>().toList(),
        lastStep: (m['lastStep'] as num?)?.toInt() ?? -1,
        failures: (m['failures'] as num?)?.toInt() ?? 0,
        lockedUntil: (m['lockedUntil'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Two-step verification for opening the app: after the device lock, the app
/// asks for the 6-digit code from an authenticator app.
///
/// This is a gate on THIS device. The key lives in this device's keystore, so
/// it stops someone who has the phone, not someone who can read the keystore,
/// and it does not follow the account to other devices. Google's own
/// two-step verification protects the sign-in itself.
class TwoFactor extends ChangeNotifier {
  TwoFactor({
    TwoFactorStorage? storage,
    String? Function()? account,
    String? Function()? label,
    DateTime Function()? clock,
    Random? random,
  })  : _storage = storage ?? const DeviceTwoFactorStorage(),
        _account = account ?? (() => ApiClient.instance.currentUserId),
        _label = label ?? (() => ApiClient.instance.currentUserEmail),
        _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  static final TwoFactor instance = TwoFactor();

  static const int recoveryCodeCount = 8;
  static const int _recoveryLength = 10;

  /// Letters and digits that cannot be misread for one another (no I, L, O, 0, 1).
  static const String _recoveryAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  /// A lock after every fifth wrong try, doubling from 30 seconds to 15 minutes.
  static const int _triesPerLock = 5;
  static const int _firstLockSeconds = 30;
  static const int _maxLockSeconds = 900;

  final TwoFactorStorage _storage;
  final String? Function() _account;
  final String? Function() _label;
  final DateTime Function() _clock;
  final Random _random;

  List<int>? _pendingSecret;

  /// The gate is armed for the signed-in account on this device.
  bool get isArmed {
    final String? account = _account();
    return account != null && _storage.isArmed(account);
  }

  /// Whether the key on this device can be read.
  Future<bool> hasVerificationData() async {
    final String? account = _account();
    if (account == null) return false;
    return await _read(account) != null;
  }

  /// How many single-use recovery codes are left, or null if unreadable.
  Future<int?> recoveryCodesLeft() async {
    final String? account = _account();
    if (account == null) return null;
    return (await _read(account))?.recovery.length;
  }

  // ---- setup --------------------------------------------------------------

  /// Makes a new key and holds it in memory only.
  TwoFactorSetup beginSetup() {
    final List<int> secret = Totp.randomSecret(_random);
    _pendingSecret = secret;
    final String encoded = Totp.base32Encode(secret);
    return TwoFactorSetup(
      secret: encoded,
      uri: Totp.uri(
          secret: encoded, account: _label() ?? _account() ?? 'account'),
    );
  }

  void cancelSetup() => _pendingSecret = null;

  /// Turns two-factor on if [code] comes from the key shown by [beginSetup].
  /// Returns the recovery codes, shown to the user once, or null on a wrong code.
  Future<List<String>?> confirmSetup(String code) async {
    final String? account = _account();
    final List<int>? secret = _pendingSecret;
    if (account == null || secret == null) return null;

    final int? step =
        await Totp.match(secret, code, now: _clock(), window: 1);
    if (step == null) return null;

    final List<String> codes = _newRecoveryCodes();
    final data = _Data(
      secret: Totp.base32Encode(secret),
      recovery: [for (final c in codes) await _hashRecovery(account, c)],
      lastStep: step,
    );
    await _storage.writeState(account, data.toJson());
    await _storage.setArmed(account, true);
    _pendingSecret = null;
    notifyListeners();
    return codes;
  }

  // ---- checking -----------------------------------------------------------

  /// Checks a 6-digit code or a recovery code.
  Future<TwoFactorCheck> check(String input) async {
    final String? account = _account();
    if (account == null) {
      return const TwoFactorCheck(TwoFactorResult.unavailable);
    }
    final _Data? data = await _read(account);
    if (data == null) {
      return const TwoFactorCheck(TwoFactorResult.unavailable);
    }

    final DateTime now = _clock();
    final int nowMs = now.millisecondsSinceEpoch;
    if (data.lockedUntil > nowMs) {
      return TwoFactorCheck(TwoFactorResult.locked,
          retryAfter: Duration(milliseconds: data.lockedUntil - nowMs));
    }

    final String cleaned = input.replaceAll(RegExp(r'[\s-]'), '');
    bool ok = false;
    bool viaRecovery = false;
    if (RegExp(r'^\d{6}$').hasMatch(cleaned)) {
      final int? step = await Totp.match(
        Totp.base32Decode(data.secret),
        cleaned,
        now: now,
        after: data.lastStep,
      );
      if (step != null) {
        ok = true;
        data.lastStep = step;
      }
    } else if (cleaned.isNotEmpty) {
      final String hash = await _hashRecovery(account, cleaned);
      final int index = data.recovery.indexOf(hash);
      if (index >= 0) {
        ok = true;
        viaRecovery = true;
        data.recovery.removeAt(index);
      }
    }

    if (ok) {
      data.failures = 0;
      data.lockedUntil = 0;
      await _storage.writeState(account, data.toJson());
      notifyListeners();
      return TwoFactorCheck(TwoFactorResult.ok, usedRecoveryCode: viaRecovery);
    }

    data.failures += 1;
    if (data.failures % _triesPerLock == 0) {
      final int block = data.failures ~/ _triesPerLock;
      final int seconds = min(
          _firstLockSeconds * (1 << min(block - 1, 5)), _maxLockSeconds);
      data.lockedUntil = nowMs + seconds * 1000;
    }
    await _storage.writeState(account, data.toJson());
    if (data.lockedUntil > nowMs) {
      return TwoFactorCheck(TwoFactorResult.locked,
          retryAfter: Duration(milliseconds: data.lockedUntil - nowMs));
    }
    return const TwoFactorCheck(TwoFactorResult.wrong);
  }

  /// Turns two-factor off after a valid code or recovery code.
  Future<TwoFactorCheck> disable(String input) async {
    final TwoFactorCheck result = await check(input);
    if (!result.ok) return result;
    final String? account = _account();
    if (account != null) await _clear(account);
    return result;
  }

  /// Replaces the recovery codes after a valid code or recovery code.
  Future<TwoFactorCheck> regenerateRecoveryCodes(String input) async {
    final TwoFactorCheck result = await check(input);
    if (!result.ok) return result;
    final String? account = _account();
    final _Data? data = account == null ? null : await _read(account);
    if (account == null || data == null) {
      return const TwoFactorCheck(TwoFactorResult.unavailable);
    }
    final List<String> codes = _newRecoveryCodes();
    data.recovery
      ..clear()
      ..addAll([for (final c in codes) await _hashRecovery(account, c)]);
    await _storage.writeState(account, data.toJson());
    notifyListeners();
    return TwoFactorCheck(TwoFactorResult.ok,
        usedRecoveryCode: result.usedRecoveryCode, codes: codes);
  }

  /// Removes two-factor from this device without a code. Only for the case
  /// where the key cannot be read at all, so no code could ever be checked.
  Future<void> resetOnThisDevice() async {
    final String? account = _account();
    if (account != null) await _clear(account);
  }

  // ---- internals ----------------------------------------------------------

  Future<void> _clear(String account) async {
    await _storage.deleteState(account);
    await _storage.setArmed(account, false);
    notifyListeners();
  }

  Future<_Data?> _read(String account) async {
    try {
      final String? raw = await _storage.readState(account);
      return raw == null ? null : _Data.parse(raw);
    } catch (_) {
      return null;
    }
  }

  List<String> _newRecoveryCodes() {
    return List<String>.generate(recoveryCodeCount, (_) {
      final chars = List<String>.generate(_recoveryLength,
          (_) => _recoveryAlphabet[_random.nextInt(_recoveryAlphabet.length)]);
      return '${chars.sublist(0, 5).join()}-${chars.sublist(5).join()}';
    });
  }

  /// Only hashes are stored, so a recovery code cannot be read back from the
  /// device; it is shown once, at creation.
  Future<String> _hashRecovery(String account, String code) async {
    final String normal = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final hash =
        await Sha256().hash(utf8.encode('atomic-2fa-recovery|$account|$normal'));
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
