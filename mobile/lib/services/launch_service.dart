import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class Launch {
  Launch({
    required this.id,
    required this.kind,
    required this.title,
    this.developer,
    this.project,
    this.area,
    this.description,
    this.imageUrl,
    this.link,
    this.createdBy,
  });

  final String id;
  final String kind; // launch | offer
  final String title;
  final String? developer;
  final String? project;
  final String? area;
  final String? description;
  final String? imageUrl;
  final String? link;
  final String? createdBy;

  bool get isOffer => kind == 'offer';

  factory Launch.fromJson(Map<String, dynamic> j) => Launch(
        id: '${j['id']}',
        kind: '${j['kind'] ?? 'launch'}',
        title: '${j['title'] ?? ''}',
        developer: j['developer']?.toString(),
        project: j['project']?.toString(),
        area: j['area']?.toString(),
        description: j['description']?.toString(),
        imageUrl: j['image_url']?.toString(),
        link: j['link']?.toString(),
        createdBy: j['created_by']?.toString(),
      );
}

/// Curated launches & offers feed (brokers post; everyone reads).
class LaunchService {
  LaunchService._();
  static final LaunchService instance = LaunchService._();
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<Launch>> list({int limit = 60}) async {
    final rows = await _db
        .from('launches')
        .select()
        .eq('active', true)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => Launch.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<String> create({
    required String kind,
    required String title,
    String? developer,
    String? project,
    String? area,
    String? description,
    String? imageUrl,
    String? link,
  }) async {
    final uid = _db.auth.currentUser!.id;
    final row = await _db.from('launches').insert({
      'created_by': uid,
      'kind': kind,
      'title': title,
      'developer': developer,
      'project': project,
      'area': area,
      'description': description,
      'image_url': imageUrl,
      'link': link,
    }).select('id').single();
    return '${row['id']}';
  }

  Future<void> remove(String id) =>
      _db.from('launches').delete().eq('id', id);

  /// Upload a launch image (reuses the public 'listings' bucket).
  Future<String> uploadImage(Uint8List bytes, String ext) async {
    final uid = _db.auth.currentUser!.id;
    final path =
        'launches/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storage.from('listings').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
              contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
              upsert: true),
        );
    return _db.storage.from('listings').getPublicUrl(path);
  }
}
