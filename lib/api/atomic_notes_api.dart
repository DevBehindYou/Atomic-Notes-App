import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:atomic_notes/authentication/auth_services/cred.dart';

/// Thrown by every ApiClient call on a non-2xx response. `code` is the
/// server's `error` field when present (e.g. `insufficient_energy`,
/// `note_limit_reached`) — callers that used to pattern-match on a Supabase
/// PostgrestException's message string now match on this instead.
class ApiException implements Exception {
  final String code;
  final int statusCode;
  ApiException(this.code, this.statusCode);
  @override
  String toString() => code;
}

/// Replaces every direct `Supabase.instance.client` call in the app. Auth,
/// notes sync, vault, energy, and profile all go through here — nothing
/// else in lib/ should import `http` directly or know the API's base URL.
///
/// NOTE on google_sign_in: this targets the `serverClientId` + `signIn()` ->
/// `account.serverAuthCode` pattern for offline server access, current as of
/// this migration. That package has had breaking API changes across major
/// versions before (most recently a v7 rewrite around federated auth) —
/// check `flutter pub outdated` and the package's own migration guide if
/// this doesn't compile against whatever version `flutter pub get` resolves.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'atomic_api_session_token';
  static const _userIdKey = 'atomic_api_user_id';
  static const _userEmailKey = 'atomic_api_user_email';

  final CredService _cred = CredService();
  String? _cachedToken;
  String? _cachedUserId;
  String? _cachedUserEmail;

  /// MIGRATION NOTE: this replaces Supabase's `auth.onAuthStateChange` stream,
  /// which SessionGuard used to listen to for `AuthChangeEvent.signedOut` —
  /// fired for BOTH an explicit `signOut()` and a token refresh failing
  /// passively. This fires for the same two cases: [signOut] below, and any
  /// 401 response (see `_decode`). One stream, same dual coverage.
  final StreamController<void> _sessionEndedController = StreamController<void>.broadcast();
  Stream<void> get onSessionEnded => _sessionEndedController.stream;

  late final GoogleSignIn _google = GoogleSignIn(
    forceCodeForRefreshToken: true,
    scopes: const ['email', 'https://www.googleapis.com/auth/drive.file'],
    serverClientId: _cred.GOOGLE_SERVER_CLIENT_ID,
  );

  /// Call once at startup, before anything checks [isSignedIn] — mirrors
  /// Supabase's own local session restore that used to happen inside
  /// `Supabase.initialize()`.
  Future<void> init() async {
    _cachedToken = await _storage.read(key: _tokenKey);
    _cachedUserId = await _storage.read(key: _userIdKey);
    _cachedUserEmail = await _storage.read(key: _userEmailKey);
  }

  String? get currentUserId => _cachedUserId;
  String? get currentUserEmail => _cachedUserEmail;
  bool get isSignedIn => _cachedToken != null;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(_cred.API_BASE_URL);
    return base.replace(
      path: '${base.path}$path',
      queryParameters: query?.isNotEmpty == true ? query : null,
    );
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_cachedToken != null) 'Authorization': 'Bearer $_cachedToken',
      };

  dynamic _decode(http.Response res) {
    final body = res.body.isEmpty ? const {} : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    final code = (body is Map && body['error'] is String) ? body['error'] as String : 'http_${res.statusCode}';

    // A 401 on an authenticated call means the session is gone server-side
    // (revoked, expired, or never valid) — clear it locally and tell
    // SessionGuard, the same protective effect Supabase's auth stream gave a
    // passive expiry before. `code == 'missing_token'` is excluded: that's a
    // caller bug (an authenticated call went out with no token attached),
    // not an expired session, and clearing state for it would be wrong.
    if (res.statusCode == 401 && code != 'missing_token' && _cachedToken != null) {
      _cachedToken = null;
      _cachedUserId = null;
      _cachedUserEmail = null;
      unawaited(_storage.delete(key: _tokenKey));
      unawaited(_storage.delete(key: _userIdKey));
      unawaited(_storage.delete(key: _userEmailKey));
      _sessionEndedController.add(null);
    }

    throw ApiException(code, res.statusCode);
  }

  Future<void> _saveSession(String token, String userId, String email) async {
    _cachedToken = token;
    _cachedUserId = userId;
    _cachedUserEmail = email;
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userIdKey, value: userId);
    await _storage.write(key: _userEmailKey, value: email);
  }

  // ---- auth ---------------------------------------------------------------

  /// Opens the native Google account picker, then exchanges the resulting
  /// serverAuthCode with the backend. Throws ApiException('cancelled', 0) if
  /// the user dismisses the picker, or ApiException('no_server_auth_code', 0)
  /// if google_sign_in didn't return one (usually a serverClientId
  /// misconfiguration — see cred.example.dart's comment).
  Future<void> signInWithGoogle() async {
    final account = await _google.signIn();
    if (account == null) throw ApiException('cancelled', 0);
    final serverAuthCode = account.serverAuthCode;
    if (serverAuthCode == null) throw ApiException('no_server_auth_code', 0);

    final res = await http.post(
      _uri('/auth/google/mobile'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'serverAuthCode': serverAuthCode}),
    );
    final data = _decode(res) as Map;
    final user = data['user'] as Map;
    await _saveSession(data['token'] as String, user['id'] as String, user['email'] as String);
  }

  Future<void> signOut() async {
    try {
      await http.post(_uri('/auth/logout'), headers: _headers);
    } catch (_) {
      // Sign out locally regardless — a failed revoke call shouldn't trap
      // the user in a signed-in UI they can no longer get out of.
    }
    try {
      await _google.signOut();
    } catch (_) {}
    _cachedToken = null;
    _cachedUserId = null;
    _cachedUserEmail = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _userEmailKey);
    // Same signal a passive 401 fires — SessionGuard reacts identically to
    // either, matching Supabase's old dual-purpose `signedOut` event.
    _sessionEndedController.add(null);
  }

  // ---- notes sync -----------------------------------------------------------

  /// Each row is the same snake_case shape `Note.toRemote()` already
  /// produces (id/kind/title/body/items/pinned/deleted/created_at/
  /// updated_at/enc_v/payload) — deliberately unchanged so note.dart needs
  /// no edits. Returns per-row results; callers that used to ignore the
  /// Supabase upsert's return value can keep doing so.
  Future<List<Map<String, dynamic>>> pushNotes(List<Map<String, dynamic>> rows, {
    required String requestId, bool instant = false,
  }) async {
    final res = await http.post(_uri('/notes/push'), headers: _headers,
      body: jsonEncode({'rows': rows, 'requestId': requestId, 'mode': instant ? 'instant' : 'standard'}))
      .timeout(const Duration(seconds: 90));
    final dynamic data;
    if (res.statusCode == 502) {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['error'] != 'note_sync_failed') {
        throw ApiException('http_502', 502);
      }
      data = decoded;
    } else {
      data = _decode(res);
    }
    return List<Map<String, dynamic>>.from(data['results'] as List);
  }

  Future<Map<String, dynamic>> pullNotes({int? after, bool encOnly = false}) async {
    final query = <String, String>{
      if (encOnly) 'encOnly': 'true',
      if (after != null) 'after': after.toString(),
    };
    final res = await http.get(_uri('/notes/pull', query), headers: _headers)
      .timeout(const Duration(seconds: 90));
    return Map<String, dynamic>.from(_decode(res) as Map);
  }

  Future<int> remoteNoteCount() async {
    final data = _decode(await http.get(_uri('/notes/count'), headers: _headers)) as Map;
    return data['count'] as int;
  }

  Future<void> wipeRemoteNotes() async {
    _decode(await http.delete(_uri('/notes'), headers: _headers));
  }

  // ---- vault ----------------------------------------------------------------

  /// Null if this account has no vault yet (server 404) — same as the old
  /// `.maybeSingle()` returning null.
  Future<Map<String, dynamic>?> getVault() async {
    final res = await http.get(_uri('/vault'), headers: _headers);
    if (res.statusCode == 404) return null;
    return _decode(res) as Map<String, dynamic>;
  }

  Future<void> createVault({
    required String verifier,
    required int kdfMemory,
    required int kdfIterations,
    required int kdfParallelism,
  }) async {
    _decode(await http.post(
      _uri('/vault'),
      headers: _headers,
      body: jsonEncode({
        'verifier': verifier,
        'kdfMemory': kdfMemory,
        'kdfIterations': kdfIterations,
        'kdfParallelism': kdfParallelism,
      }),
    ));
  }

  // ---- energy -----------------------------------------------------------

  Future<Map<String, dynamic>> energyState() async {
    return _decode(await http.get(_uri('/energy'), headers: _headers)) as Map<String, dynamic>;
  }

  Future<void> energyConvert(int coins) async {
    _decode(await http.post(_uri('/energy/convert'), headers: _headers, body: jsonEncode({'coins': coins})));
  }

  Future<void> energySpend(int amount, String reason) async {
    _decode(await http.post(_uri('/energy/spend'), headers: _headers, body: jsonEncode({'amount': amount, 'reason': reason})));
  }

  /// Returns the amount actually charged (0 within the free hourly window).
  Future<int> energySpendStandard() async {
    final data = _decode(await http.post(_uri('/energy/spend-standard'), headers: _headers)) as Map;
    return data['charged'] as int;
  }

  Future<void> energyRefund(int amount, String reason) async {
    _decode(await http.post(_uri('/energy/refund'), headers: _headers, body: jsonEncode({'amount': amount, 'reason': reason})));
  }

  // ---- profile ------------------------------------------------------------

  Future<String> getUsername() async {
    final data = _decode(await http.get(_uri('/atomicuser'), headers: _headers)) as Map;
    return data['username'] as String;
  }

  Future<void> setUsername(String username) async {
    _decode(await http.patch(_uri('/atomicuser'), headers: _headers, body: jsonEncode({'username': username})));
  }
}
