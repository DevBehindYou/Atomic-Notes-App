import 'dart:async';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/energy_service.dart';
import 'package:atomic_notes/database/notification_service.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:flutter/material.dart';

/// The one place that owns the invariant: no valid session means no access to
/// authenticated application state.
///
/// Every logout path used to be a per-screen affair — the settings button, the
/// shell, and the splash each tried to react to sign-out on their own — and the
/// shell only ever replaced the top route, so the authenticated pages stayed
/// alive underneath and Back walked right back into them. This centralises it:
/// a single listener tears the previous user's runtime state down and resets
/// the navigation stack to the login screen, from wherever the app happens to
/// be.
///
/// MIGRATION NOTE: this used to listen to Supabase's
/// `auth.onAuthStateChange`, which fires `AuthChangeEvent.signedOut` for BOTH
/// an explicit `signOut()` and a token refresh failing passively. The new
/// backend has no equivalent auth-state stream, so ApiClient fires its own
/// `onSessionEnded` for the same two cases instead (see
/// ApiClient.signOut and the 401 handling in ApiClient._decode) — one
/// stream, same dual coverage as before.
class SessionGuard {
  SessionGuard._();

  /// Root navigator, so a sign-out that happens with nothing on screen (a
  /// background refresh failing) can still reset the stack.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Where a sign-out lands. Not the login route directly: [LoggedOutScreen] is
  /// an always-opaque branded screen that forwards to login itself. Landing
  /// there first is what stops a blank navigator when the stack reset races the
  /// logout confirmation dialog closing in the same beat.
  static const String _landingRoute = '/loggedout';

  static StreamSubscription<void>? _sub;
  static bool _handling = false;

  /// Begin guarding. Idempotent — safe to call more than once.
  static void attach() {
    _sub ??= ApiClient.instance.onSessionEnded.listen((_) {
      unawaited(_onSignedOut());
    });
  }

  static void detach() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  static Future<void> _onSignedOut() async {
    // More than one signal can arrive (an explicit logout that also trips a
    // 401 from an in-flight request). Collapse them so the teardown and reset
    // run once.
    if (_handling) return;
    _handling = true;
    try {
      try {
        await teardown();
      } catch (e) {
        debugPrint('SessionGuard: teardown failed, resetting anyway ($e)');
      }
      // Defer past any in-flight navigation (the logout dialog closes in the
      // same beat) so the stack reset can't collide with a route that is still
      // popping — that collision was leaving a blank black screen. Reset
      // regardless of teardown outcome: never leave an authenticated screen up.
      await Future<void>.delayed(Duration.zero);
      navigatorKey.currentState
          ?.pushNamedAndRemoveUntil(_landingRoute, (route) => false);
    } finally {
      _handling = false;
    }
  }

  /// Drop every piece of the previous user's authenticated runtime state.
  ///
  /// This deliberately does NOT wipe the on-disk note cache. An explicit logout
  /// already flushes and clears it in the settings screen, and a session that
  /// merely expired must not silently destroy notes that were never synced.
  /// Cross-account isolation on disk is enforced by [NotesRepository], which
  /// only ever loads a cache tagged with the current account.
  static Future<void> teardown() async {
    await NotesRepository.instance.stop(); // cancel the hourly sync timer
    NotesRepository.instance.clearMemory(); // hide notes from the UI at once
    Vault.instance.lockMemory(); // drop the decryption key from RAM
    EnergyService.instance.clear(); // drop the previous user's balances
    NotificationService.instance.clear(); // drop the previous user's feed
  }
}
