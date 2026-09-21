import 'package:flutter/foundation.dart';
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

  /// The current limit, announced whenever it changes so a screen that shows
  /// `3 / 20` moves to `3 / 30` at once instead of at the next restart.
  static final ValueNotifier<int> changes = ValueNotifier<int>(freeLimit);

  static Future<void> init() async {
    _box = await Hive.openBox(boxName);
    changes.value = limit;
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
    changes.value = value;
    await _box?.put(_limitKey, value);
  }

  /// Back to the free tier, for example when the account signs out.
  static Future<void> reset() async {
    _memory = null;
    changes.value = freeLimit;
    await _box?.delete(_limitKey);
  }
}
