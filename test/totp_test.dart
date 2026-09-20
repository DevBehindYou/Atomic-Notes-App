// One-time passwords must agree with every authenticator app, so these check
// the published test vectors rather than the implementation against itself.
// RFC 4226 appendix D (counter codes) and RFC 6238 appendix B (SHA-1 times).

import 'dart:convert';

import 'package:atomic_notes/security/totp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final key = utf8.encode('12345678901234567890');

  group('codes', () {
    test('RFC 4226 counters 0 to 9', () async {
      const expected = [
        '755224', '287082', '359152', '969429', '338314', //
        '254676', '287922', '162583', '399871', '520489',
      ];
      for (int counter = 0; counter < expected.length; counter++) {
        expect(await Totp.codeForStep(key, counter), expected[counter],
            reason: 'counter $counter');
      }
    });

    test('RFC 6238 times', () async {
      const vectors = {
        59: '287082',
        1111111109: '081804',
        1111111111: '050471',
        1234567890: '005924',
        2000000000: '279037',
        20000000000: '353130',
      };
      for (final entry in vectors.entries) {
        final moment =
            DateTime.fromMillisecondsSinceEpoch(entry.key * 1000, isUtc: true);
        expect(await Totp.codeForStep(key, Totp.stepFor(moment)), entry.value,
            reason: 'unix time ${entry.key}');
      }
    });
  });

  group('matching', () {
    // Unix time 59 falls in step 1; the window covers steps 0, 1 and 2.
    final now = DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true);

    test('accepts the current step and one either side', () async {
      expect(await Totp.match(key, '287082', now: now), 1);
      expect(await Totp.match(key, '755224', now: now), 0);
      expect(await Totp.match(key, '359152', now: now), 2);
    });

    test('refuses a step outside the window', () async {
      // Counter 3.
      expect(await Totp.match(key, '969429', now: now), isNull);
    });

    test('refuses a step that was already used', () async {
      expect(await Totp.match(key, '287082', now: now, after: 1), isNull);
      expect(await Totp.match(key, '359152', now: now, after: 1), 2);
    });

    test('ignores spaces and refuses anything that is not six digits',
        () async {
      expect(await Totp.match(key, '287 082', now: now), 1);
      expect(await Totp.match(key, '28708', now: now), isNull);
      expect(await Totp.match(key, '2870820', now: now), isNull);
      expect(await Totp.match(key, 'abcdef', now: now), isNull);
      expect(await Totp.match(key, '', now: now), isNull);
    });
  });

  group('base32', () {
    test('RFC 4648 vectors, without padding', () {
      const vectors = {
        '': '',
        'f': 'MY',
        'fo': 'MZXQ',
        'foo': 'MZXW6',
        'foob': 'MZXW6YQ',
        'fooba': 'MZXW6YTB',
        'foobar': 'MZXW6YTBOI',
      };
      for (final entry in vectors.entries) {
        expect(Totp.base32Encode(utf8.encode(entry.key)), entry.value);
        expect(utf8.decode(Totp.base32Decode(entry.value)), entry.key);
      }
    });

    test('decodes what a person might paste', () {
      expect(utf8.decode(Totp.base32Decode('mzxw 6ytb-oi==')), 'foobar');
    });

    test('rejects a character that is not base32', () {
      expect(() => Totp.base32Decode('MZXW1'), throwsFormatException);
    });

    test('round-trips random secrets', () {
      final secret = Totp.randomSecret();
      expect(secret.length, Totp.secretBytes);
      expect(Totp.base32Decode(Totp.base32Encode(secret)), secret);
      expect(Totp.randomSecret(), isNot(secret));
    });
  });

  test('the QR address carries the key, issuer and settings', () {
    final uri = Totp.uri(secret: 'ABCDEFGH', account: 'me@example.com');
    expect(
      uri,
      'otpauth://totp/Atomic%20Notes:me%40example.com'
      '?secret=ABCDEFGH&issuer=Atomic%20Notes'
      '&algorithm=SHA1&digits=6&period=30',
    );
  });
}
