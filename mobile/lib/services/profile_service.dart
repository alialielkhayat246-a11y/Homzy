import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads/writes the current user's profile row (role, phone, company, avatar).
class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();

  SupabaseClient get _db => Supabase.instance.client;
  String? get _uid => _db.auth.currentUser?.id;

  /// Cached role from the last [get]/[role] call ('user' | 'broker'). Lets the
  /// UI branch synchronously; brokers get the listings tools, users don't.
  String? cachedRole;
  bool get isBroker => cachedRole == 'broker';

  /// Notifies listeners (e.g. the nav shell) when the role/mode changes.
  final ValueNotifier<String?> roleNotifier = ValueNotifier<String?>(null);

  void _setRole(String? r) {
    cachedRole = r;
    roleNotifier.value = r;
  }

  Future<Map<String, dynamic>?> get() async {
    final uid = _uid;
    if (uid == null) return null;
    final row =
        await _db.from('profiles').select().eq('id', uid).maybeSingle();
    if (row != null && row['role'] != null) _setRole('${row['role']}');
    return row;
  }

  /// Resolve the role, defaulting to 'user' when unknown.
  Future<String> role() async {
    if (cachedRole != null) return cachedRole!;
    final p = await get();
    final r = '${p?['role'] ?? 'user'}';
    _setRole(r);
    return r;
  }

  /// Switch between 'broker' and 'user' mode and persist it.
  Future<void> setMode(String role) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    await _db.from('profiles').upsert({'id': uid, 'role': role});
    _setRole(role);
  }

  /// Update editable profile fields (only non-null values are written).
  Future<void> update({
    String? fullName,
    String? phone,
    String? company,
    String? avatarUrl,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final data = <String, dynamic>{'id': uid};
    if (fullName != null) data['full_name'] = fullName;
    if (phone != null) data['phone'] = phone;
    if (company != null) data['company'] = company;
    if (avatarUrl != null) data['avatar_url'] = avatarUrl;
    await _db.from('profiles').upsert(data);
  }

  /// Upload an avatar image; returns its public URL.
  Future<String> uploadAvatar(Uint8List bytes, String ext) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final path = '$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
              upsert: true, contentType: 'image/$ext'),
        );
    final url = _db.storage.from('avatars').getPublicUrl(path);
    await update(avatarUrl: url);
    return url;
  }

  /// Permanently delete the account (via the delete-account edge function).
  Future<void> deleteAccount() async {
    final token = _db.auth.currentSession?.accessToken;
    if (token == null) throw StateError('Not signed in');
    final res = await _db.functions.invoke('delete-account',
        headers: {'Authorization': 'Bearer $token'});
    if (res.status != 200) {
      throw Exception('Delete failed (${res.status})');
    }
    await _db.auth.signOut();
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
    _setRole(role);
  }
}
