// Every secure-storage instance must use the same Android options, or the
// session token is lost each time the app closes (see secure_options.dart).
// The mismatch cannot be seen from Dart at run time, so this reads the source.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every FlutterSecureStorage is built with the shared Android options',
      () {
    final constructions = RegExp(r'FlutterSecureStorage\(([^;]*?)\);');
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.replaceAll(r'\', '/').endsWith('secure_options.dart'));

    int found = 0;
    for (final file in files) {
      for (final match in constructions.allMatches(file.readAsStringSync())) {
        found++;
        expect(
          match.group(1),
          contains('aOptions: kSecureAndroidOptions'),
          reason: '${file.path} builds a FlutterSecureStorage with its own '
              'Android options',
        );
      }
    }
    // The API client, the vault and two-factor.
    expect(found, greaterThanOrEqualTo(3));
  });
}
