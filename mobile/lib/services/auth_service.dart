import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around Supabase Auth for Homzy.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  Session? get session => _client.auth.currentSession;
  bool get isLoggedIn => session != null;
  String? get email => currentUser?.email;
  String? get displayName =>
      currentUser?.userMetadata?['full_name'] as String? ?? email;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? fullName,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      data: (fullName != null && fullName.isNotEmpty)
          ? {'full_name': fullName}
          : null,
    );
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Browser-based Google OAuth. Supabase handles the redirect back into the
  /// app via the io.supabase.homzy://login-callback/ deep link (see the
  /// Android manifest intent-filter). Requires the Google provider to be
  /// enabled in the Supabase dashboard.
  Future<bool> signInWithGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      // On web Supabase redirects back to the current origin; on mobile we use
      // the app's deep-link scheme.
      redirectTo: kIsWeb ? null : 'io.supabase.homzy://login-callback/',
    );
  }

  Future<void> signOut() => _client.auth.signOut();
}
