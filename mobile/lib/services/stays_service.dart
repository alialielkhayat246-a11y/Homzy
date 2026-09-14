import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class StaysService {
  StaysService._();
  static final StaysService instance = StaysService._();
  SupabaseClient get _db => Supabase.instance.client;

  List<Map<String, dynamic>> _rows(dynamic value) =>
      (value as List? ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

  Future<List<Map<String, dynamic>>> browse() async => _rows(await _db
      .from('stay_cards')
      .select()
      .order('created_at', ascending: false));

  Future<List<Map<String, dynamic>>> bookings() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return const [];
    return _rows(await _db
        .from('stay_bookings')
        .select()
        .eq('guest_id', uid)
        .order('check_in', ascending: false));
  }

  Future<Map<String, dynamic>> ensureHost() async {
    final uid = _db.auth.currentUser!.id;
    final existing = _rows(await _db
        .from('stay_hosts')
        .select('user_id,verification_status')
        .eq('user_id', uid)
        .limit(1));
    if (existing.isNotEmpty) return existing.first;
    return Map<String, dynamic>.from(await _db
        .from('stay_hosts')
        .insert({'user_id': uid, 'verification_status': 'pending'})
        .select('user_id,verification_status')
        .single());
  }

  Future<List<Map<String, dynamic>>> hostProperties() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return const [];
    return _rows(await _db
        .from('stay_properties')
        .select(
            '*,stay_pricing(base_price,currency),stay_property_images(url,is_cover,sort)')
        .eq('host_id', uid)
        .order('created_at', ascending: false));
  }

  Future<String> createProperty(Map<String, dynamic> data,
      {required num basePrice}) async {
    final uid = _db.auth.currentUser!.id;
    await ensureHost();
    final property = await _db
        .from('stay_properties')
        .insert({...data, 'host_id': uid})
        .select('id')
        .single();
    final id = '${property['id']}';
    await _db.from('stay_pricing').insert({
      'property_id': id,
      'base_price': basePrice,
      'currency': 'EGP',
      'cleaning_fee': 0,
      'min_nights': 1,
      'cancellation_policy': 'flexible',
    });
    return id;
  }

  Future<List<Map<String, dynamic>>> verifications() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return const [];
    return _rows(await _db
        .from('stay_verifications')
        .select('doc_type,status,created_at')
        .eq('user_id', uid)
        .order('created_at', ascending: false));
  }

  Future<void> uploadVerification(
      Uint8List bytes, String filename, String docType) async {
    final uid = _db.auth.currentUser!.id;
    await ensureHost();
    final safe = filename.replaceAll(RegExp(r'[^a-zA-Z0-9.]'), '_');
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}-$safe';
    await _db.storage.from('stay-docs').uploadBinary(path, bytes,
        fileOptions: const FileOptions(upsert: false));
    await _db.from('stay_verifications').insert({
      'user_id': uid,
      'role': 'host',
      'doc_type': docType,
      'doc_path': path,
    });
  }
}
