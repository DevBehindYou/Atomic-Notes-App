import 'dart:async';

import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/energy_models.dart';
import 'package:atomic_notes/database/note_quota.dart';
import 'package:flutter/foundation.dart';

/// Single source of truth for Atomic Energy + Atomic Coins on the client.
///
/// Same shape as [NotesRepository]/[Vault]: a singleton [ChangeNotifier] that
/// reads server-authoritative balances and never computes its own. Every
/// mutation goes through the server's Energy API (a Node/MongoDB port of the
/// original SECURITY DEFINER RPCs — see the server's src/lib/energy.ts); the
/// client can read the balance but the server is what changes it.
///
/// Modular by design: other features call [convertCoins] and
/// [upgradeNoteLimit] without importing the Energy screen. Sync is charged by
/// the Server itself when it runs, so nothing here spends energy.
class EnergyService extends ChangeNotifier {
  EnergyService._();
  static final EnergyService instance = EnergyService._();

  // Economy constants, mirrored from the server so the UI can explain them.
  // The server is authoritative; these are for display/estimation only.
  static const int coinToEnergy = 40; // 1 coin -> 40 energy
  static const int dailyGrant = 20; // +20 every 24h (server clock)
  // Note: the full capacity (120) is per-user and read from the wallet via the
  // `energyCap` instance getter below — no static constant, to avoid shadowing.
  static const int syncStandardCost = 5; // automatic sync, once an hour (4 per grant)
  static const int syncInstantCost = 10; // instant sync (2 per grant)

  final ApiClient _api = ApiClient.instance;
  String? get _uid => _api.currentUserId;

  Wallet _wallet = Wallet.empty;
  EnergyLimits _limits = const EnergyLimits();
  List<EnergyTx> _history = const [];
  bool _loading = false;
  String? _error;
  String? _boundUser;

  Wallet get wallet => _wallet;

  /// The prices and ceilings the Server enforces.
  EnergyLimits get limits => _limits;
  List<EnergyTx> get history => _history;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasLoaded => _boundUser != null && _boundUser == _uid;

  int get coins => _wallet.coins;
  int get energy => _wallet.energy;
  int get energyCap => _wallet.energyCap;

  /// How many notes the account may hold, as the Server reports it.
  int get noteLimit => _wallet.noteLimit;

  /// The next tier above the current limit, or null at the ceiling.
  NoteLimitTier? get nextTier {
    for (final t in _limits.tiers) {
      if (t.limit > noteLimit) return t;
    }
    return null;
  }

  /// A higher tier can be bought.
  bool get canRaiseNoteLimit => nextTier != null;

  /// There are enough coins for the next tier.
  bool get canAffordNoteLimit {
    final t = nextTier;
    return t != null && coins >= t.costCoins;
  }

  /// The limit after the next purchase.
  int get nextNoteLimit => nextTier?.limit ?? noteLimit;

  // ---- lifecycle --------------------------------------------------------

  /// Run after sign-in (splash) and any time the screen wants fresh data.
  /// Ensures a wallet row exists, applies the daily grant, then loads.
  ///
  /// MIGRATION NOTE: the server's GET /energy already calls energyEnsure +
  /// energyGrantDaily itself (see routes/energy.ts), so refresh() alone
  /// would be enough — this still calls them explicitly first, matching the
  /// old two-step shape, since it's harmless (both are idempotent) and
  /// keeps this diff smaller than restructuring the lifecycle too.
  Future<void> init() async {
    final uid = _uid;
    // A different account must never see the previous user's balances.
    if (uid != _boundUser) {
      _wallet = Wallet.empty;
      _history = const [];
      _error = null;
      _boundUser = uid;
    }
    if (uid == null) return;
    await refresh();
  }

  /// Drop in-memory balances (called on logout by SessionGuard).
  void clear() {
    _wallet = Wallet.empty;
    _limits = const EnergyLimits();
    _history = const [];
    _error = null;
    _boundUser = null;
    unawaited(NoteQuota.reset());
    notifyListeners();
  }

  // ---- reads ------------------------------------------------------------

  Future<void> refresh() async {
    final uid = _uid;
    if (uid == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final state = await _api.energyState();
      if (state['wallet'] != null) {
        _adopt(state);
      }
      _history = (state['history'] as List)
          .map((e) => EnergyTx.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      _error = _friendly(e);
      debugPrint('EnergyService.refresh failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ---- mutations (server-authoritative) --------------------------------

  /// Convert [coins] Atomic Coins into Energy. Returns null on success, or a
  /// user-facing error string (insufficient coins, cap overflow, ...).
  Future<String?> convertCoins(int coins) async {
    if (_uid == null) return 'You are signed out.';
    try {
      await _api.energyConvert(coins);
      await refresh();
      return null;
    } catch (e) {
      return _friendly(e);
    }
  }

  /// Buys the next 10 notes of capacity for coins. Returns null on success, or a
  /// user-facing message. Safe to repeat: the Server charges a step only once.
  Future<String?> upgradeNoteLimit() async {
    if (_uid == null) return 'You are signed out.';
    if (!canRaiseNoteLimit) return 'You already have the most notes possible.';
    try {
      final state = await _api.upgradeNoteLimit(noteLimit);
      _adopt(state);
      notifyListeners();
      await refresh();
      return null;
    } catch (e) {
      if (e.toString().contains('invalid_amount')) {
        // The limit this device showed is not the Server's any more.
        await refresh();
        return 'Your note limit changed. Check it and try again.';
      }
      return _friendly(e);
    }
  }

  /// Takes the wallet and limits from a Server response and keeps the note
  /// quota in step with them.
  void _adopt(Map<String, dynamic> state) {
    final wallet = state['wallet'];
    if (wallet is Map) {
      _wallet = Wallet.fromMap(Map<String, dynamic>.from(wallet));
      unawaited(NoteQuota.setLimit(_wallet.noteLimit));
    }
    final limits = state['limits'];
    if (limits is Map) {
      _limits = EnergyLimits.fromMap(Map<String, dynamic>.from(limits));
    }
  }

  @visibleForTesting
  void debugSet({Wallet? wallet, EnergyLimits? limits}) {
    if (wallet != null) {
      _wallet = wallet;
      unawaited(NoteQuota.setLimit(wallet.noteLimit));
    }
    if (limits != null) _limits = limits;
    notifyListeners();
  }

  // ---- errors -----------------------------------------------------------

  /// Map raised errors (ApiException.code, or a raw exception string) to
  /// plain messages. ApiException.toString() returns just the server's error
  /// code, so this .contains() matching keeps working unchanged — the server
  /// deliberately returns the same code strings the old RPCs raised.
  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('insufficient_coins')) return 'Not enough Atomic Coins.';
    if (s.contains('insufficient_energy')) return 'Not enough Atomic Energy.';
    if (s.contains('note_limit_ceiling')) {
      return 'You already have the most notes possible.';
    }
    if (s.contains('energy_cap_exceeded')) {
      return 'That would overflow your Energy cap. Use some first.';
    }
    if (s.contains('invalid_amount')) return 'Enter a valid amount.';
    if (s.contains('SocketException') || s.contains('Failed host')) {
      return 'You appear to be offline.';
    }
    return 'Something went wrong. Please try again.';
  }
}
