import 'package:supabase_flutter/supabase_flutter.dart';

import 'listing_service.dart';

const clientStages = ['new', 'contacted', 'viewing', 'closed', 'lost'];

class Client {
  Client({
    required this.id,
    required this.name,
    this.phone,
    this.purpose,
    this.type,
    this.area,
    this.bedrooms,
    this.budget,
    this.stage = 'new',
    this.notes,
  });

  final String id;
  final String name;
  final String? phone;
  final String? purpose;
  final String? type;
  final String? area;
  final int? bedrooms;
  final num? budget;
  final String stage;
  final String? notes;

  factory Client.fromJson(Map<String, dynamic> j) => Client(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        phone: j['phone']?.toString(),
        purpose: j['purpose']?.toString(),
        type: j['type']?.toString(),
        area: j['area']?.toString(),
        bedrooms: j['bedrooms'] is int
            ? j['bedrooms'] as int
            : int.tryParse('${j['bedrooms']}'),
        budget: j['budget'] as num?,
        stage: '${j['stage'] ?? 'new'}',
        notes: j['notes']?.toString(),
      );
}

/// The broker's private client pipeline (CRM) + live matches per client.
class ClientService {
  ClientService._();
  static final ClientService instance = ClientService._();
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<Client>> list() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _db
        .from('clients')
        .select()
        .eq('owner_id', uid)
        .order('updated_at', ascending: false);
    return (rows as List)
        .map((r) => Client.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<String> create(Map<String, dynamic> data) async {
    final uid = _db.auth.currentUser!.id;
    final row = await _db
        .from('clients')
        .insert({...data, 'owner_id': uid})
        .select('id')
        .single();
    return '${row['id']}';
  }

  Future<void> update(String id, Map<String, dynamic> data) => _db
      .from('clients')
      .update({...data, 'updated_at': DateTime.now().toIso8601String()})
      .eq('id', id);

  Future<void> setStage(String id, String stage) => update(id, {'stage': stage});

  Future<void> remove(String id) => _db.from('clients').delete().eq('id', id);

  /// Active marketplace listings matching a client's brief (the "alerts").
  Future<List<Listing>> matches(Client c) async {
    return ListingService.instance.browse(
      purpose: c.purpose,
      type: c.type,
      area: c.area,
      priceMax: c.budget != null ? c.budget! * 1.2 : null,
    );
  }
}
