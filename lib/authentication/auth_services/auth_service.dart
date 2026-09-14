// ignore_for_file: unnecessary_null_comparison

import 'package:atomic_notes/api/atomic_notes_api.dart';

class AuthServices {
  final ApiClient _api = ApiClient.instance;
  late String userId = _api.currentUserId!;

  // update user info
  Future<String?> updateUserInfo({
    required String username,
  }) async {
    try {
      // MIGRATION NOTE: this used to be an insert-then-catch-23505-then-update
      // dance to work around Supabase not offering an atomic upsert at this
      // call site. The server does a real upsert in one round trip now
      // (routes/atomicuser.ts), so there's nothing left to catch here.
      await _api.setUsername(username);
      return "Username updated wait for refresh";
    } catch (error) {
      return "Error updating username";
    }
  }

  // fetch user info from the Atomic Notes API
  Future<String> getUserInfo() async {
    try {
      final username = await _api.getUsername();
      if (username == "") {
        return "@atomicuser";
      }
      return "@$username";
    } catch (error) {
      return "@atomicuser";
    }
  }
}
