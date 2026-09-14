import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/notification_models.dart';
import 'package:flutter/foundation.dart';

/// Reads the in-app notification feed and tracks per-user read/dismiss state.
///
/// MIGRATION NOTE: notifications were explicitly out of scope for this
/// migration pass (see the server's README — the notifications_feed/
/// notification_mark_read/notification_mark_all_read/notification_dismiss
/// RPCs exist in the live app but have no server-side home yet). Rather than
/// leave this referencing a Supabase client that no longer exists (a compile
/// error) or silently pretending to call a working feed, every network path
/// below is stubbed to a safe no-op: the feed loads empty, and
/// mark-read/dismiss just no-op locally. `unreadCount` therefore reads 0
/// everywhere it's shown, which is honest given there is nothing behind it
/// yet — not a bug to chase if you see it.
class NotificationService extends ChangeNotifier {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  String? get _uid => ApiClient.instance.currentUserId;

  List<AppNotification> _items = const [];
  final bool _loading = false;
  String? _error;
  String? _boundUser;

  List<AppNotification> get items => _items;
  bool get loading => _loading;
  String? get error => _error;
  int get unreadCount => _items.where((n) => !n.isRead).length;

  Future<void> init() async {
    final uid = _uid;
    if (uid != _boundUser) {
      _items = const [];
      _error = null;
      _boundUser = uid;
    }
    // Not migrated yet — see class doc comment. Nothing to fetch.
  }

  void clear() {
    _items = const [];
    _error = null;
    _boundUser = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    // Not migrated yet — see class doc comment.
  }

  Future<void> markRead(String id) async {
    // Not migrated yet — see class doc comment.
  }

  Future<void> markAllRead() async {
    // Not migrated yet — see class doc comment.
  }

  Future<void> dismiss(String id) async {
    // Not migrated yet — see class doc comment.
  }
}
