import 'package:supabase_flutter/supabase_flutter.dart';

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
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> signOut() async {
    await _client.auth.signOut();
  }

  static Stream<AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;
}
