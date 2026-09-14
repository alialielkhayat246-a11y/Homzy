import 'package:supabase_flutter/supabase_flutter.dart';

class AgencyWorkspace {
  const AgencyWorkspace({
    required this.agency,
    required this.permissions,
    required this.roster,
    required this.roles,
    required this.teams,
  });

  final Map<String, dynamic> agency;
  final Set<String> permissions;
  final List<Map<String, dynamic>> roster;
  final List<Map<String, dynamic>> roles;
  final List<Map<String, dynamic>> teams;

  bool can(String permission) => permissions.contains(permission);
}

class AgencyService {
  AgencyService._();
  static final AgencyService instance = AgencyService._();
  SupabaseClient get _db => Supabase.instance.client;

  List<Map<String, dynamic>> _rows(dynamic value) =>
      (value as List? ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

  Future<AgencyWorkspace?> workspace() async {
    final agencies = _rows(await _db
        .from('agencies')
        .select('id,name,logo_url,phone,email,address,description')
        .order('created_at')
        .limit(1));
    if (agencies.isEmpty) return null;
    final agency = agencies.first;
    final id = agency['id'];
    final values = await Future.wait<dynamic>([
      _db.rpc('my_perms', params: {'p_agency': id}),
      _db.rpc('agency_team_roster', params: {'p_agency': id}),
      _db.from('roles').select().eq('agency_id', id).order('rank'),
      _db.from('teams').select().eq('agency_id', id).order('created_at'),
    ]);
    return AgencyWorkspace(
      agency: agency,
      permissions: (values[0] as List? ?? const [])
          .map((value) => value.toString())
          .toSet(),
      roster: _rows(values[1]),
      roles: _rows(values[2]),
      teams: _rows(values[3]),
    );
  }

  Future<void> createAgency(String name) async {
    await _db.rpc('create_agency', params: {'p_name': name});
  }

  Future<List<Map<String, dynamic>>> owners(String agencyId) async => _rows(
      await _db.rpc('agency_list_owners', params: {'p_agency': agencyId}));

  Future<void> createOwner(String agencyId, Map<String, dynamic> values) async {
    await _db
        .rpc('agency_create_owner', params: {'p_agency': agencyId, ...values});
  }

  Future<void> setOwnerStage(String ownerId, String stage) async {
    await _db.rpc('agency_set_owner_stage', params: {
      'p_owner': ownerId,
      'p_stage': stage,
      'p_status': null,
      'p_notes': null,
    });
  }

  Future<void> assignOwner(String ownerId, String? userId) async {
    await _db.rpc('agency_assign_owner', params: {
      'p_owner': ownerId,
      'p_assignee': userId,
      'p_reason': null,
    });
  }

  Future<void> setMemberStatus(
      String agencyId, String userId, String status) async {
    await _db.rpc('agency_set_member_status', params: {
      'p_agency': agencyId,
      'p_user': userId,
      'p_status': status,
    });
  }

  Future<void> setMemberRole(
      String agencyId, String userId, String role) async {
    await _db.rpc('agency_set_member_role', params: {
      'p_agency': agencyId,
      'p_user': userId,
      'p_role_key': role,
    });
  }

  Future<void> createTeam(
      String agencyId, String name, String? leaderId) async {
    await _db.rpc('agency_create_team', params: {
      'p_agency': agencyId,
      'p_name': name,
      'p_leader': leaderId,
    });
  }

  Future<Map<String, dynamic>?> lookupUser(
      String agencyId, String query) async {
    final value = await _db.rpc('agency_lookup_user', params: {
      'p_agency': agencyId,
      'p_query': query,
    });
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  Future<void> addMember(
      String agencyId, String userId, String roleKey, String? teamId) async {
    await _db.rpc('agency_add_member', params: {
      'p_agency': agencyId,
      'p_user': userId,
      'p_role_key': roleKey,
      'p_team': teamId,
    });
  }
}
