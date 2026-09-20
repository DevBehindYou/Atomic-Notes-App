import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce/hive_ce.dart';

/// "No screenshots": blocks screenshots and screen recording inside the app and
/// hides its preview in the recent-apps switcher.
///
/// Android implements this with the window's secure flag (see MainActivity.kt).
/// A platform without an implementation reports failure instead of pretending.
class ScreenSecurity {
  ScreenSecurity._();

  static const MethodChannel _channel = MethodChannel('com.notes.atomic/screen');

  /// Key in the process-wide 'authBox' Hive box.
  static const String prefKey = 'noScreenshot';

  /// Applies the saved choice. Call once at startup, after 'authBox' is open.
  static Future<void> applySaved() async {
    final saved = Hive.box<bool>('authBox').get(prefKey, defaultValue: false);
    await set(saved ?? false);
  }

  /// Turns the block on or off. Returns false when this device cannot do it.
  static Future<bool> set(bool secure) async {
    try {
      await _channel.invokeMethod<void>('setSecure', <String, bool>{'secure': secure});
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('ScreenSecurity: ${e.code}');
      return false;
    }
  }
}
