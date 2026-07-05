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
  }) async {
    final res = await _client.auth.signUp(
      email: email,
      password: password,
      data: (fullName != null && fullName.isNotEmpty)
          ? {'full_name': fullName}
          : null,
    );
    // New accounts are auto-confirmed by a DB trigger (Supabase's built-in
    // mailer isn't configured), so if sign-up didn't return a session, sign in
    // right away — the user goes straight into the app, no email step.
    if (_client.auth.currentSession == null) {
      try {
        await _client.auth
            .signInWithPassword(email: email, password: password);
      } catch (_) {/* surfaced on the next sign-in attempt */}
    }
    return res;
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
    // On web, redirect back to the exact page the app is served from (e.g. the
    // GitHub Pages URL) instead of the dashboard's default Site URL — otherwise
    // a stale Site URL (localhost) breaks the OAuth return. On mobile we use the
    // app's deep-link scheme.
    final base = Uri.base;
    final webRedirect = '${base.origin}${base.path}';
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo:
          kIsWeb ? webRedirect : 'io.supabase.homzy://login-callback/',
    );
  }

  Future<void> signOut() => _client.auth.signOut();
}
