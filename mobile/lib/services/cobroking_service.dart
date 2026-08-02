import 'package:supabase_flutter/supabase_flutter.dart';

class CoPost {
  CoPost({
    required this.id,
    required this.kind,
    required this.title,
    this.purpose,
    this.type,
    this.area,
    this.bedrooms,
    this.budget,
    this.description,
    this.phone,
  });

  final String id;
  final String kind; // have | want
  final String title;
  final String? purpose;
  final String? type;
  final String? area;
  final int? bedrooms;
  final num? budget;
  final String? description;
  final String? phone;

  bool get isWant => kind == 'want';

  factory CoPost.fromJson(Map<String, dynamic> j) => CoPost(
        id: '${j['id']}',
        kind: '${j['kind'] ?? 'have'}',
        title: '${j['title'] ?? ''}',
        purpose: j['purpose']?.toString(),
        type: j['type']?.toString(),
        area: j['area']?.toString(),
        bedrooms: j['bedrooms'] is int
            ? j['bedrooms'] as int
            : int.tryParse('${j['bedrooms']}'),
        budget: j['budget'] as num?,
        description: j['description']?.toString(),
        phone: j['phone']?.toString(),
      );
}

/// Broker-to-broker board (co-broking): post a unit you have or a client need.
class CobrokingService {
  CobrokingService._();
  static final CobrokingService instance = CobrokingService._();
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<CoPost>> list() async {
    final rows = await _db
        .from('cobroking')
        .select()
        .eq('active', true)
        .order('created_at', ascending: false)
        .limit(80);
    return (rows as List)
        .map((r) => CoPost.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> create(Map<String, dynamic> data) async {
    final uid = _db.auth.currentUser!.id;
    await _db.from('cobroking').insert({...data, 'owner_id': uid});
  }

  Future<void> remove(String id) =>
      _db.from('cobroking').delete().eq('id', id);
}
