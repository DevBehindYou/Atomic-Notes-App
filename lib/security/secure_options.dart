import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The Android options for EVERY [FlutterSecureStorage] in the app.
///
/// On Android all instances read and write the same preferences file, whatever
/// options they were built with. The session token used to sit in an instance
/// with default options while the encryption key used one with
/// `encryptedSharedPreferences: true`. The two modes then disturbed each
/// other's entries, and the token could no longer be read after the app was
/// closed: every restart signed the user out.
///
/// Give each new instance `aOptions: kSecureAndroidOptions` and nothing else.
/// A test fails if a construction leaves it out.
const AndroidOptions kSecureAndroidOptions =
    AndroidOptions(encryptedSharedPreferences: true);
