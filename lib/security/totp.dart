import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Time-based one-time passwords (RFC 6238) over HMAC-SHA1, the variant every
/// authenticator app understands: 6 digits, a new code every 30 seconds.
///
/// Pure functions only. Where the secret lives and how failures are counted is
/// [TwoFactor]'s business, not this file's.
class Totp {
  Totp._();

  static const int digits = 6;
  static const int period = 30;

  /// 160 bits, the size RFC 4226 recommends.
  static const int secretBytes = 20;

  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static Uint8List randomSecret([Random? random]) {
    final rng = random ?? Random.secure();
    return Uint8List.fromList(
        List<int>.generate(secretBytes, (_) => rng.nextInt(256)));
  }

  /// RFC 4648 base32 without padding, the form authenticator apps expect.
  static String base32Encode(List<int> bytes) {
    final out = StringBuffer();
    int buffer = 0;
    int bits = 0;
    for (final byte in bytes) {
      buffer = (buffer << 8) | (byte & 0xff);
      bits += 8;
      while (bits >= 5) {
        out.write(_alphabet[(buffer >> (bits - 5)) & 31]);
        bits -= 5;
      }
      buffer &= (1 << bits) - 1;
    }
    if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
    return out.toString();
  }

  /// Accepts what a person might paste: any case, spaces, dashes and padding.
  /// Throws [FormatException] on a character that is not base32.
  static Uint8List base32Decode(String text) {
    final cleaned = text.toUpperCase().replaceAll(RegExp(r'[\s=-]'), '');
    final out = <int>[];
    int buffer = 0;
    int bits = 0;
    for (final unit in cleaned.codeUnits) {
      final int value = _alphabet.indexOf(String.fromCharCode(unit));
      if (value < 0) {
        throw const FormatException('Not a base32 character');
      }
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        out.add((buffer >> (bits - 8)) & 0xff);
        bits -= 8;
        buffer &= (1 << bits) - 1;
      }
    }
    return Uint8List.fromList(out);
  }

  /// The 30-second window a moment falls in.
  static int stepFor(DateTime time) =>
      time.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ period;

  /// The code for one time step (RFC 4226 HOTP with the step as the counter).
  static Future<String> codeForStep(List<int> secret, int step) async {
    // Eight bytes, big endian. Two 32-bit writes rather than setUint64, which
    // is not available when compiled for the web.
    final message = Uint8List(8);
    final view = ByteData.view(message.buffer);
    view.setUint32(0, step ~/ 0x100000000);
    view.setUint32(4, step & 0xffffffff);

    final mac = await Hmac(Sha1())
        .calculateMac(message, secretKey: SecretKey(secret));
    final h = mac.bytes;
    final int offset = h[h.length - 1] & 0x0f;
    final int binary = ((h[offset] & 0x7f) << 24) |
        ((h[offset + 1] & 0xff) << 16) |
        ((h[offset + 2] & 0xff) << 8) |
        (h[offset + 3] & 0xff);
    return (binary % 1000000).toString().padLeft(digits, '0');
  }

  /// The time step whose code equals [input], or null.
  ///
  /// Steps up to [window] either side of now are accepted, which absorbs clock
  /// drift and the moment it takes to type. A step at or before [after] is
  /// refused, so a code that has already been used cannot be used again.
  static Future<int?> match(
    List<int> secret,
    String input, {
    required DateTime now,
    int window = 1,
    int? after,
  }) async {
    final String cleaned = input.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{6}$').hasMatch(cleaned)) return null;

    final int current = stepFor(now);
    int? found;
    // Every step is computed even after a hit, so the time taken does not tell
    // an observer which step matched.
    for (int step = current - window; step <= current + window; step++) {
      if (step < 0) continue;
      final String expected = await codeForStep(secret, step);
      final bool same = _sameText(expected, cleaned);
      if (same && found == null && (after == null || step > after)) {
        found = step;
      }
    }
    return found;
  }

  /// The address an authenticator app reads from a QR code.
  static String uri({
    required String secret,
    required String account,
    String issuer = 'Atomic Notes',
  }) {
    final String label =
        '${Uri.encodeComponent(issuer)}:${Uri.encodeComponent(account)}';
    return 'otpauth://totp/$label'
        '?secret=$secret'
        '&issuer=${Uri.encodeComponent(issuer)}'
        '&algorithm=SHA1&digits=$digits&period=$period';
  }

  static bool _sameText(String a, String b) {
    if (a.length != b.length) return false;
    int difference = 0;
    for (int i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }
}
