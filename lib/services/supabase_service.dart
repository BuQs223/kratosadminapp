import 'package:supabase_flutter/supabase_flutter.dart';

import 'powersync_service.dart';

class SupabaseService {
  static final SupabaseClient _client = Supabase.instance.client;

  // Getter for the client
  static SupabaseClient get client => _client;

  // Auth methods
  static User? get currentUser => _client.auth.currentUser;

  static bool get isAuthenticated => currentUser != null;

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    await PowerSyncService.connectIfAuthenticated();
    return response;
  }

  static Future<void> signOut() async {
    await PowerSyncService.disconnect();
    await _client.auth.signOut();
  }

  static Stream<AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;
}
