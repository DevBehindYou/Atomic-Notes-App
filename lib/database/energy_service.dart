import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/database/energy_models.dart';
import 'package:flutter/foundation.dart';

/// Single source of truth for Atomic Energy + Atomic Coins on the client.
///
/// Same shape as [NotesRepository]/[Vault]: a singleton [ChangeNotifier] that
/// reads server-authoritative balances and never computes its own. Every
/// mutation goes through the server's Energy API (a Node/MongoDB port of the
/// original SECURITY DEFINER RPCs — see the server's src/lib/energy.ts); the
/// client can read the balance but the server is what changes it.
///
/// Modular by design: other features call [spend]/[convertCoins] without
/// importing the Energy screen.
class EnergyService extends ChangeNotifier {
  EnergyService._();
  static final EnergyService instance = EnergyService._();

  // Economy constants, mirrored from the server so the UI can explain them.
  // The server is authoritative; these are for display/estimation only.
  static const int coinToEnergy = 40; // 1 coin -> 40 energy
  static const int dailyGrant = 20; // +20 every 24h (server clock)
  // Note: the full capacity (120) is per-user and read from the wallet via the
  // `energyCap` instance getter below — no static constant, to avoid shadowing.
  static const int syncStandardCost = 5; // hourly/standard sync (4 per grant)
  static const int syncInstantCost = 10; // instant sync (2 per grant)

  final ApiClient _api = ApiClient.instance;
  String? get _uid => _api.currentUserId;

  Wallet _wallet = Wallet.empty;
  List<EnergyTx> _history = const [];
  bool _loading = false;
  String? _error;
  String? _boundUser;

  Wallet get wallet => _wallet;
  List<EnergyTx> get history => _history;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasLoaded => _boundUser != null && _boundUser == _uid;

  int get coins => _wallet.coins;
  int get energy => _wallet.energy;
  int get energyCap => _wallet.energyCap;

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
    _history = const [];
    _error = null;
    _boundUser = null;
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
        _wallet = Wallet.fromMap(Map<String, dynamic>.from(state['wallet'] as Map));
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

  /// Spend energy directly. Returns null on success, else a message.
  Future<String?> spend(int amount, String reason) async {
    if (_uid == null) return 'You are signed out.';
    try {
      await _api.energySpend(amount, reason);
      await refresh();
      return null;
    } catch (e) {
      return _friendly(e);
    }
  }

  /// Instant sync: always costs [syncInstantCost] (10). Returns null on success,
  /// else a message. On success the caller knows the exact amount charged
  /// ([syncInstantCost]), so it can refund it if the upload later fails.
  Future<String?> spendInstant() => spend(syncInstantCost, 'Instant sync');

  /// Standard (background) sync: costs [syncStandardCost] (5) at most once per
  /// hour — free inside the paid hour (server-enforced window). Returns the
  /// amount actually charged (0 within the free hour, else 5), or null when the
  /// balance can't cover it. The amount lets the caller refund on upload failure.
  Future<int?> spendStandard() async {
    if (_uid == null) return null;
    try {
      final charged = await _api.energySpendStandard();
      await refresh();
      return charged;
    } catch (e) {
      debugPrint('EnergyService.spendStandard failed: $e');
      return null;
    }
  }

  /// Return energy that was charged for a sync that then failed to upload, so a
  /// dropped network never costs the user energy. Capped, and a no-op for 0.
  Future<void> refund(int amount, String reason) async {
    if (_uid == null || amount <= 0) return;
    try {
      await _api.energyRefund(amount, reason);
      await refresh();
    } catch (e) {
      debugPrint('EnergyService.refund failed: $e');
    }
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
