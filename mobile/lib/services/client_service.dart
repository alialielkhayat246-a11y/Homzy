import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api.dart';

const clientStages = [
  'new',
  'contact',
  'qualified',
  'matching',
  'viewing',
  'offer_sent',
  'negotiate',
  'reservation',
  'closed',
  'lost',
];

String normalizeClientStage(String? value) {
  const aliases = {
    'contacted': 'contact',
    'offer': 'offer_sent',
    'negotiation': 'negotiate',
    'reserved': 'reservation',
  };
  final stage = aliases[value] ?? value ?? 'new';
  return clientStages.contains(stage) ? stage : 'new';
}

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
    this.custom = const {},
    this.leadScore,
    this.temperature,
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
  final Map<String, dynamic> custom;
  final int? leadScore;
  final String? temperature;

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
        stage: normalizeClientStage(j['stage']?.toString()),
        notes: j['notes']?.toString(),
        custom: j['custom'] is Map
            ? Map<String, dynamic>.from(j['custom'] as Map)
            : const {},
        leadScore: j['lead_score'] is num
            ? (j['lead_score'] as num).round()
            : int.tryParse('${j['lead_score'] ?? ''}'),
        temperature: j['temperature']?.toString(),
      );
}

/// The broker's private client pipeline (CRM) + live matches per client.
class ClientService {
  ClientService._();
  static final ClientService instance = ClientService._();
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<Client>> list() async {
    if (_db.auth.currentUser == null) return [];
    final rows = await _db
        .from('clients')
        .select()
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
      .update({...data, 'updated_at': DateTime.now().toIso8601String()}).eq(
          'id', id);

  Future<void> setStage(String id, String stage) async {
    await _db.rpc('crm_sales_move_stage', params: {
      'p_lead': id,
      'p_stage': stage,
      'p_reason': null,
    });
  }

  Future<void> remove(String id) => _db.from('clients').delete().eq('id', id);

  /// Uses the same server-side saved-requirements ranking and AI guidance as
  /// the web CRM. The bearer token keeps the result scoped to this broker.
  Future<Map<String, dynamic>> copilot(String clientId,
      {required String language}) async {
    final token = _db.auth.currentSession?.accessToken;
    if (token == null) throw StateError('Sign in required');
    final uri = Uri.parse(
        '${HomzyApi.instance.baseUrl}/api/crm/sales/clients/$clientId/copilot?language=$language');
    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 45));
    final decoded = response.bodyBytes.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      final detail = decoded is Map ? decoded['detail'] : null;
      throw StateError(
          detail?.toString() ?? 'CRM service returned ${response.statusCode}');
    }
    return Map<String, dynamic>.from(decoded as Map);
  }
}
