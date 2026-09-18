import 'dart:async';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/energy_service.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_quota.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';

/// Single source of truth for notes, and the sync engine.
///
/// Replaces the old model where seven screens each built their own
/// `NotesDataBase` with its own in-memory copy, and where the entire notebook
/// was pushed as one base64 blob. That blob was last-write-wins across *every*
/// note at once: a second device syncing didn't merge with the first, it
/// replaced everything the first had written. That is why notes never appeared
/// on a second phone.
///
/// Now: one row per note, last-write-wins per note on a server-set
/// `updated_at`, tombstones for deletes. MIGRATION NOTE: this used to also
/// carry a Realtime subscription (a change on one device landing on others
/// without a manual sync) — the new backend has no realtime/push layer yet
/// (see the server's README), so that line is no longer true. Updates now
/// arrive only via the hourly timer, the connectivity-restored trigger, or a
/// manual sync — a real UX regression from before, not a simplification, and
/// worth restoring deliberately (websocket push, or at least shorter polling)
/// rather than treating this comment as still accurate.
class NotesRepository extends ChangeNotifier {
  NotesRepository._();
  static final NotesRepository instance = NotesRepository._();

  static const String boxName = 'notesBox';

  /// Reserved Hive key tagging which account this local cache belongs to. Stored
  /// as a plain String, so the `is Map` guards in the loaders skip right over
  /// it. It is what lets a device keep one user's offline notes while refusing
  /// to show them to a different user who signs in later.
  static const String _ownerKey = '__cache_owner__';

  late Box _box;
  final ApiClient _api = ApiClient.instance;
  String? get _userId => _api.currentUserId;

  StreamSubscription<List<ConnectivityResult>>? _connectivity;

  /// Periodic background ("hourly") standard sync. Editing a note no longer
  /// uploads immediately — a change stays local until the user taps sync
  /// (instant) or this timer fires (standard, server-windowed to once/hour).
  Timer? _hourly;

  bool _syncing = false;
  bool get isSyncing => _syncing;

  String? lastError;
  DateTime? lastSyncedAt;
  int? _syncCursor;
  static const _pendingPushKey = '__pending_sync_operation';

  /// Reserved Hive key holding the last pull cursor of [_ownerKey]'s account, so
  /// a restart continues where the last pull ended instead of refetching every
  /// note from Google Drive.
  static const String _cursorKey = '__sync_cursor__';

  /// A push carries at most 20 notes; a sync sends up to this many batches.
  static const int _maxPushBatches = 5;

  /// Tail of the serialized Hive write queue (see [_persist]). Never fails.
  Future<void> _writeChain = Future<void>.value();

  /// In-memory index, id -> note.
  final Map<String, Note> _notes = {};

  // ---- lifecycle --------------------------------------------------------

  Future<void> init() async {
    _box = await Hive.openBox(boxName);
    await _loadFromDisk();

    // Push anything that was written while offline as soon as we're back.
    _connectivity = Connectivity().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) {
        unawaited(syncNow());
      }
    });
  }

  Future<void> _loadFromDisk() async {
    _notes.clear();
    _syncCursor = null;
    // A cache written by a different account — a previous user whose session
    // expired without an explicit logout — must never surface for this one.
    // (Explicit logout already wipes the box; this covers the expiry path.)
    final owner = _box.get(_ownerKey);
    final uid = _userId;
    if (owner is String && uid != null && owner != uid) {
      await _drainWrites();
      await _box.clear();
      return;
    }
    if (uid != null) _restoreCursor(uid);
    for (final raw in _box.values) {
      if (raw is Map && raw['id'] is String) {
        final opened = await _open(raw);
        if (opened == null) continue; // encrypted + locked: load after unlock
        final n = Note.fromMap(opened);
        _notes[n.id] = n;
      }
    }
  }

  // ---- encryption boundary ---------------------------------------------
  // When the vault is unlocked, note content (title/body/items) is sealed into
  // `payload` and the plaintext fields are emptied before anything is written
  // to Hive or Supabase, and re-opened on the way back. When encryption is off
  // these are pass-throughs, so plaintext behaviour is unchanged.

  Future<Map<String, dynamic>> _sealLocal(Note n) => _seal(n.toMap());
  Future<Map<String, dynamic>> _sealRemote(Note n, String uid) =>
      _seal(n.toRemote(uid));

  Future<Map<String, dynamic>> _seal(Map<String, dynamic> m) async {
    // T2T: the vault is off or locked on this device, so the note is stored in
    // the clear and stays readable to any signed-in device.
    if (!Vault.instance.isUnlocked) {
      m['enc_v'] = 0;
      m['payload'] = null;
      return m;
    }
    m['payload'] = await Vault.instance.encryptContent({
      'title': m['title'] ?? '',
      'body': m['body'] ?? '',
      'items': m['items'] ?? const <dynamic>[],
    });
    m['enc_v'] = Vault.encVersion;
    m['title'] = '';
    m['body'] = '';
    m['items'] = const <dynamic>[];
    return m;
  }

  /// Inverse of [_seal]. Returns a plaintext map ready for Note.fromMap/
  /// fromRemote, or null if the row is encrypted but the vault is locked or the
  /// content can't be decrypted (caller skips it and retries after unlock).
  Future<Map<String, dynamic>?> _open(Map<dynamic, dynamic> m) async {
    final out = m.map((k, v) => MapEntry(k.toString(), v));
    final encV = out['enc_v'] is int ? out['enc_v'] as int : 0;
    final payload = out['payload'];
    if (encV < 1 || payload is! String) return out;
    if (!Vault.instance.isUnlocked) return null;
    try {
      final content = await Vault.instance.decryptContent(payload);
      out['title'] = content['title'] ?? '';
      out['body'] = content['body'] ?? '';
      out['items'] = content['items'] ?? const <dynamic>[];
      return out;
    } catch (e) {
      debugPrint('NotesRepository: could not decrypt note ${out['id']}: $e');
      return null;
    }
  }

  /// Called after sign-in, and on startup when a session already exists.
  ///
  /// Returns as soon as the (cheap, local) subscription is registered — the
  /// actual network sync runs in the background. Nothing in the UI should
  /// ever wait for this.
  Future<void> start() async {
    final uid = _userId;
    if (uid == null) return;
    // Isolation on the hot path (logout/expiry then a different user signs in
    // without an app restart): if the disk cache belongs to another account,
    // drop it before this user's notes load in. Same user keeps their cache.
    final owner = _box.get(_ownerKey);
    if (owner is String && owner != uid) {
      _notes.clear();
      _syncCursor = null;
      lastSyncedAt = null;
      await _drainWrites();
      await _box.clear();
      notifyListeners();
    }
    _restoreCursor(uid);
    await _box.put(_ownerKey, uid);
    // MIGRATION NOTE: `_listenRealtime()` used to be called here — removed,
    // the new backend has no realtime endpoint (see class doc comment above).
    // Initial sync: fetches existing cloud notes (a free pull when there's
    // nothing pending). Editing does NOT sync after this — only this hourly
    // timer or a manual sync uploads changes.
    unawaited(syncNow());
    _hourly?.cancel();
    _hourly = Timer.periodic(
        const Duration(hours: 1), (_) => unawaited(syncNow()));
  }

  Future<void> stop() async {
    _hourly?.cancel();
    _hourly = null;
  }

  /// Drop the in-memory notes without touching the on-disk cache. Used by the
  /// session guard on sign-out so the UI can't show the previous user's notes,
  /// while a same-user re-login can still reuse the local cache.
  void clearMemory() {
    _notes.clear();
    _syncCursor = null;
    lastSyncedAt = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_connectivity?.cancel());
    _hourly?.cancel();
    super.dispose();
  }

  // ---- reads ------------------------------------------------------------

  /// Live notes, tombstones excluded, pinned first.
  List<Note> visible({NoteFilter filter = NoteFilter.newest}) {
    final list = _notes.values.where((n) => !n.deleted).toList();

    switch (filter) {
      case NoteFilter.todos:
        list.retainWhere((n) => n.kind == NoteKind.todo);
      case NoteFilter.notes:
        list.retainWhere((n) => n.kind == NoteKind.text);
      case NoteFilter.newest:
      case NoteFilter.oldest:
        break;
    }

    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return filter == NoteFilter.oldest
          ? a.createdAt.compareTo(b.createdAt)
          : b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  int get count => _notes.values.where((n) => !n.deleted).length;
  int get pendingCount => _notes.values.where((n) => n.dirty).length;

  Note? byId(String id) => _notes[id];

  // ---- quota ------------------------------------------------------------

  /// Notes and to-dos share one allowance — a checklist is a note.
  int get limit => NoteQuota.limit;

  int get remaining => (limit - count).clamp(0, limit);

  bool get isAtLimit => count >= limit;

  /// Tombstones don't count, so deleting frees a slot immediately.
  String get usageLabel => '$count / $limit';

  // ---- writes -----------------------------------------------------------

  Future<void> save(Note note) async {
    note.touch();
    _notes[note.id] = note;
    await _persist(note.id);
    notifyListeners();
    // No auto-upload: the note is saved locally and marked dirty; it reaches the
    // cloud only on a manual (instant) sync or the hourly background sync.
  }

  /// Soft delete, so the removal can reach other devices.
  Future<void> deleteNotes(Iterable<String> ids) async {
    for (final id in ids) {
      final n = _notes[id];
      if (n == null) continue;
      n.deleted = true;
      n.touch();
      await _persist(n.id);
    }
    notifyListeners();
    // Saved locally as a tombstone; the deletion reaches the cloud on the next
    // manual or hourly sync, not immediately.
  }

  /// Wipes the local cache only — used on logout. Does not touch the server.
  Future<void> clearLocal() async {
    _notes.clear();
    _syncCursor = null;
    // Let an in-flight write finish first: it would otherwise land after the
    // clear and leave this account's note on disk for the next one.
    await _drainWrites();
    await _box.clear();
    lastSyncedAt = null;
    notifyListeners();
  }

  // ---- persistence ------------------------------------------------------

  /// Writes note [id] to Hive, one write at a time. Each write reads the note
  /// when it runs and sealing is asynchronous, so unqueued writers could finish
  /// out of order and let an older snapshot (for example an acknowledgment that
  /// clears `dirty`) overwrite a newer local edit. Every change to a note is
  /// followed by a call here, so the last write on disk reflects the last
  /// change. A write for another account, or for a note no longer in memory,
  /// is dropped rather than put into the wrong cache.
  Future<void> _persist(String id) {
    final uid = _userId;
    final write = _writeChain.then((_) async {
      final note = _notes[id];
      if (note == null || _userId != uid) return;
      await _box.put(id, await _sealLocal(note));
    });
    _writeChain = write.catchError((_) {});
    return write;
  }

  Future<void> _drainWrites() => _writeChain;

  /// Loads the pull cursor saved for [uid], if this cache belongs to that account.
  void _restoreCursor(String uid) {
    final cursor = _box.get(_cursorKey);
    _syncCursor = _box.get(_ownerKey) == uid && cursor is int ? cursor : null;
  }

  Future<void> _resetCursor() async {
    _syncCursor = null;
    await _box.delete(_cursorKey);
  }

  // ---- sync -------------------------------------------------------------

  /// How long a sync may take before we give up. A device can report a live
  /// connection and still have no route out (captive portals, hotel wifi), so
  /// a connectivity check alone isn't enough — without a deadline the request
  /// just sits there.


  /// Push local changes, then pull remote ones. Safe to call often.
  ///
  /// Cloud sync is energy-gated. Uploading changes costs energy: [instant] sync
  /// (the manual button) costs 10 every time; a standard/background sync costs 5
  /// at most once per hour (free within the paid hour). A sync with nothing to
  /// upload (receive-only) is free. If the balance can't cover the upload, the
  /// notes stay safely on the device (still dirty) and nothing is pushed — so at
  /// zero energy local notes keep working but don't reach the cloud until energy
  /// is topped up.
  Future<bool> syncNow({bool instant = false}) async {
    if (_syncing) return true;
    final uid = _userId;
    if (uid == null) return false;
    if (!SyncStatusHelper.isSyncOn) return false;

    // Don't sit on a dead socket when we already know there's no network.
    final conn = await Connectivity().checkConnectivity();
    if (conn.contains(ConnectivityResult.none)) {
      lastError = 'Offline — changes are saved on this device';
      return false;
    }

    if (_syncing || _userId != uid) return false;
    // Acquire locally before the first await that starts a sync operation.
    _syncing = true;
    lastError = null;
    notifyListeners();
    try {
      // A push carries at most 20 notes: keep sending until nothing is waiting,
      // so a completed sync means every queued change reached the server.
      var drained = false;
      for (var batch = 0; batch < _maxPushBatches && !drained; batch++) {
        drained = !await _push(uid, instant: instant);
      }
      await _pull(uid);
      unawaited(EnergyService.instance.refresh());
      if (!drained) {
        lastError = '$pendingCount changes are still waiting to sync. Sync again to send the rest.';
        return false;
      }
      return true;
    } on TimeoutException {
      lastError = 'Sync is taking longer than expected. Your changes are saved; retry to recover the same operation.';
      return false;
    } catch (e) {
      lastError = e.toString().contains('note_limit_reached')
          ? 'Note limit reached — delete a note and sync again'
          : e.toString();
      return false;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Sends one batch. Returns true when more changes are still waiting.
  Future<bool> _push(String uid, {required bool instant}) async {
    if (_userId != uid) return false;
    final saved = _box.get(_pendingPushKey);
    Map<String, dynamic>? pending = saved is Map && saved['userId'] == uid
        ? Map<String, dynamic>.from(saved) : null;
    if (pending == null) {
      final dirty = _notes.values.where((n) => n.dirty).take(20).map((n) => n.copy()).toList();
      if (dirty.isEmpty) return false;
      final rows = await Future.wait(dirty.map((n) => _sealRemote(n, uid)));
      if (_userId != uid) return false;
      pending = {
        'requestId': newId(), 'userId': uid, 'instant': instant, 'rows': rows,
        'versions': {for (final n in dirty) n.id: n.updatedAt.toIso8601String()},
        'conflictIds': {for (final n in dirty) n.id: newId()},
      };
      await _box.put(_pendingPushKey, pending);
    }
    final rows = (pending['rows'] as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
    final List<Map<String, dynamic>> results;
    try {
      results = await _api.pushNotes(rows, requestId: pending['requestId'] as String, instant: pending['instant'] == true);
    } on ApiException catch (e) {
      // Validation happens before the operation is charged/recorded. Retry corrected data.
      if (e.statusCode == 400 || ['note_limit_reached', 'insufficient_energy', 'note_id_conflict'].contains(e.code)) {
        if (_userId == uid) await _box.delete(_pendingPushKey);
      }
      rethrow;
    }
    if (_userId != uid) return false;
    final versions = pending['versions'] as Map;
    var conflicted = false;
    var failed = false;
    for (final result in results) {
      final id = result['id'] as String;
      final local = _notes[id];
      if (local == null) continue;
      if (result['ok'] != true) {
        failed = true;
        if (result['error'] == 'note_conflict') conflicted = true;
        if (result['error'] == 'note_conflict' && local.dirty) {
          final copy = Note(id: (pending['conflictIds'] as Map)[id] as String, kind: local.kind, title: '${local.title.length > 270 ? local.title.substring(0, 270) : local.title} (conflict copy)',
            body: local.body, items: local.items.map((i) => i.copy()).toList(), dirty: true);
          _notes[copy.id] = copy;
          await _persist(copy.id);
          // The other version is fetched again below and replaces this one.
          local.dirty = false;
          local.serverVersion = 0;
          await _persist(id);
        }
        continue;
      }
      local.serverVersion = (result['version'] as num).toInt();
      if (local.updatedAt.toIso8601String() == versions[id]) {
        local.dirty = false;
        local.updatedAt = DateTime.parse(result['updated_at'] as String).toUtc();
      }
      if (_userId != uid) return false;
      await _persist(id);
    }
    if (_userId != uid) return false;
    await _box.delete(_pendingPushKey);
    if (failed) {
      // The pull cursor is already past the version that conflicted, so start over.
      if (conflicted) await _resetCursor();
      notifyListeners();
      await _pull(uid);
      throw ApiException(
          conflicted
              ? 'Some notes changed on another device. Your edits are saved as separate copies.'
              : 'Some notes could not be uploaded. They stay on this device and will retry.',
          409);
    }
    return _notes.values.any((n) => n.dirty);
  }

  Future<void> _pull(String uid) async {
    var more = true;
    while (more && _userId == uid) {
      final response = await _api.pullNotes(after: _syncCursor, encOnly: !Vault.instance.isUnlocked);
      if (_userId != uid) return;
      await _mergeAll(List<Map<String, dynamic>>.from(response['rows'] as List), uid);
      if (_userId != uid) return;
      _syncCursor = (response['nextCursor'] as num).toInt();
      await _box.put(_cursorKey, _syncCursor);
      more = response['hasMore'] == true;
      lastSyncedAt = DateTime.parse(response['cursor'] as String).toUtc();
    }
  }

  /// Last-write-wins per note, on the server's `updated_at`.
  ///
  /// [forUid] is the account the rows were fetched for. If the session has since
  /// changed (logout or expiry completed while this fetch/stream event was in
  /// flight), the rows are dropped rather than merged — otherwise a late fetch
  /// would repopulate the UI with the previous user's notes after sign-out.
  Future<void> _mergeAll(List<Map<String, dynamic>> rows, String forUid) async {
    if (_userId != forUid) return;
    var changed = false;
    for (final row in rows) {
      if (_userId != forUid) return; // session ended mid-merge
      final opened = await _open(row);
      if (opened == null) continue; // encrypted + locked: retry after unlock
      final remote = Note.fromRemote(opened);
      final local = _notes[remote.id];

      if (local == null) {
        _notes[remote.id] = remote;
        await _persist(remote.id);
        changed = true;
        continue;
      }

      // Never let a pull clobber an edit that hasn't been pushed yet.
      if (local.dirty) continue;

      if (remote.serverVersion > local.serverVersion) {
        _notes[remote.id] = remote;
        await _persist(remote.id);
        changed = true;
      }
    }
    if (changed && _userId == forUid) notifyListeners();
  }

  /// Re-seal every note this device holds and push them.
  ///
  /// Runs after the vault is created and after every unlock, so notes written
  /// while the vault was off or locked (T2T) are converted to vault notes. It
  /// is idempotent: re-sealing an already-sealed note just rewrites it, so an
  /// interrupted run is safe to repeat.
  Future<void> migrateToVault() async {
    if (!Vault.instance.isUnlocked) return;
    if (_notes.isEmpty) return;
    debugPrint('NotesRepository: migrating ${_notes.length} notes into the vault');
    for (final n in _notes.values.toList()) {
      n.dirty = true;
      await _persist(n.id);
    }
    notifyListeners();
    await syncNow();
    debugPrint('NotesRepository: vault migration complete');
  }

  /// After unlocking on a device that was holding notes it could not read,
  /// re-read the local cache, pull everything, and fold any plaintext notes
  /// into the vault.
  Future<void> reloadAfterUnlock() async {
    await _loadFromDisk();
    // A locked pull skipped encrypted rows but still advanced the cursor.
    await _resetCursor();
    lastSyncedAt = null;
    notifyListeners();
    await syncNow();
    await migrateToVault();
  }

  /// Any sealed payload this device already holds, so an offline device can
  /// check a recovery phrase without reaching the server.
  String? get sampleCiphertext {
    for (final raw in _box.values) {
      if (raw is Map && raw['id'] is String) {
        final v = raw['enc_v'];
        final p = raw['payload'];
        if (v is int && v >= 1 && p is String && p.isNotEmpty) return p;
      }
    }
    return null;
  }

  // ---- maintenance ------------------------------------------------------

  /// Number of live notes on the server, for the Database screen.
  ///
  /// Counts rows, not readable notes: an encrypted row still counts while this
  /// device is locked, which is what makes the on-device and in-cloud numbers
  /// comparable.
  Future<int> remoteCount() async {
    final uid = _userId;
    if (uid == null) return 0;
    try {
      return await _api.remoteNoteCount();
    } catch (e) {
      debugPrint('NotesRepository.remoteCount failed: $e');
      return 0;
    }
  }

  /// Hard-deletes every note row for this user, tombstones included.
  ///
  /// Deliberately leaves the vault row alone: it holds the phrase verifier, and
  /// dropping it would strand notes still encrypted on other devices.
  Future<String> wipeRemote() async {
    final uid = _userId;
    if (uid == null) return 'Not signed in';
    try {
      await _api.wipeRemoteNotes();
      return 'Cloud data deleted successfully';
    } catch (e) {
      lastError = e.toString();
      debugPrint('NotesRepository.wipeRemote failed: $e');
      return 'Failed to delete data';
    }
  }
}
