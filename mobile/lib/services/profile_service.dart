import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads/writes the current user's profile row (role, phone, company).
class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  SupabaseClient get _db => Supabase.instance.client;
  String? get _uid => _db.auth.currentUser?.id;

  Future<Map<String, dynamic>?> get() async {
    final uid = _uid;
    if (uid == null) return null;
    return await _db.from('profiles').select().eq('id', uid).maybeSingle();
  }

  /// True when the user still needs to pick a role (first run).
  Future<bool> needsOnboarding() async {
    try {
      final p = await get();
      return p == null || p['role'] == null;
    } catch (_) {
      // If we can't reach the DB, don't block the user.
      return false;
    }
  }

  Future<void> saveRole({
    required String role, // 'user' | 'broker'
    required String phone,
    String? company,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    await _db.from('profiles').upsert({
      'id': uid,
      'role': role,
      'phone': phone,
      'company': company,
      'email': _db.auth.currentUser?.email,
    });
  }
}
