import 'package:hive_ce/hive_ce.dart';

/// How many notes this account may hold.
///
/// The Server decides and enforces it: a push that would go over is refused. This
/// class holds the number the Server last reported (the wallet's `noteLimit`) so
/// the UI can show `3 / 20` and stop at the limit without a request. It starts at
/// [freeLimit], and each purchase of capacity moves it up to the Server's ceiling.
class NoteQuota {
  NoteQuota._();

  static const String boxName = 'prefsBox';
  static const String _limitKey = 'noteLimit';

  /// What a new account gets.
  static const int freeLimit = 20;

  static Box? _box;

  /// The value in use, kept in memory as well as in the box.
  static int? _memory;

  static Future<void> init() async {
    _box = await Hive.openBox(boxName);
  }

  /// Current cap. Counts notes and to-dos together — a checklist is a note.
  static int get limit {
    final memory = _memory;
    if (memory != null && memory > 0) return memory;
    final v = _box?.get(_limitKey);
    return v is int && v > 0 ? v : freeLimit;
  }

  /// Records the limit the Server reported.
  static Future<void> setLimit(int value) async {
    _memory = value;
    await _box?.put(_limitKey, value);
  }

  /// Back to the free tier, for example when the account signs out.
  static Future<void> reset() async {
    _memory = null;
    await _box?.delete(_limitKey);
  }
}
