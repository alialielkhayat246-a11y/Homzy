import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads the developers / projects / unit-types / media catalog from Supabase.
class CatalogService {
  CatalogService._();
  static final CatalogService instance = CatalogService._();
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<Project>> projects() async {
    final rows = await _db
        .from('projects')
        .select('*, developer:developers(name, about, track_record, phone, website)')
        .order('updated_at', ascending: false);
    return (rows as List)
        .map((r) => Project.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<ProjectDetail> detail(String projectId) async {
    final p = await _db
        .from('projects')
        .select('*, developer:developers(name, about, track_record, phone, website)')
        .eq('id', projectId)
        .single();
    final units = await _db
        .from('unit_types')
        .select()
        .eq('project_id', projectId)
        .order('price_from', ascending: true);
    final media = await _db
        .from('project_media')
        .select()
        .eq('project_id', projectId);
    return ProjectDetail(
      project: Project.fromJson(p),
      units: (units as List)
          .map((u) => UnitType.fromJson(u as Map<String, dynamic>))
          .toList(),
      media: (media as List)
          .map((m) => ProjectMedia.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }
}

String? _s(dynamic v) => v == null ? null : '$v';
num? _n(dynamic v) =>
    v == null ? null : (v is num ? v : num.tryParse('$v'));
int? _i(dynamic v) => v == null ? null : (v is int ? v : int.tryParse('$v'));

class Project {
  Project({
    required this.id,
    required this.name,
    this.area,
    this.description,
    this.delivery,
    this.status,
    this.amenities,
    this.coverImageUrl,
    this.developerName,
    this.developerAbout,
    this.developerTrack,
    this.developerPhone,
  });

  final String id;
  final String name;
  final String? area;
  final String? description;
  final String? delivery;
  final String? status;
  final String? amenities;
  final String? coverImageUrl;
  final String? developerName;
  final String? developerAbout;
  final String? developerTrack;
  final String? developerPhone;

  factory Project.fromJson(Map<String, dynamic> j) {
    final dev = j['developer'] as Map<String, dynamic>?;
    return Project(
      id: '${j['id']}',
      name: '${j['name'] ?? ''}',
      area: _s(j['area']),
      description: _s(j['description']),
      delivery: _s(j['delivery']),
      status: _s(j['status']),
      amenities: _s(j['amenities']),
      coverImageUrl: _s(j['cover_image_url']),
      developerName: _s(dev?['name']),
      developerAbout: _s(dev?['about']),
      developerTrack: _s(dev?['track_record']),
      developerPhone: _s(dev?['phone']),
    );
  }
}

class UnitType {
  UnitType({
    this.type,
    this.bedrooms,
    this.sizeFrom,
    this.sizeTo,
    this.priceFrom,
    this.priceTo,
    this.downPayment,
    this.installmentYears,
    this.paymentPlan,
    this.finishing,
    this.delivery,
  });

  final String? type;
  final int? bedrooms;
  final num? sizeFrom;
  final num? sizeTo;
  final num? priceFrom;
  final num? priceTo;
  final String? downPayment;
  final int? installmentYears;
  final String? paymentPlan;
  final String? finishing;
  final String? delivery;

  factory UnitType.fromJson(Map<String, dynamic> j) => UnitType(
        type: _s(j['type']),
        bedrooms: _i(j['bedrooms']),
        sizeFrom: _n(j['size_from']),
        sizeTo: _n(j['size_to']),
        priceFrom: _n(j['price_from']),
        priceTo: _n(j['price_to']),
        downPayment: _s(j['down_payment']),
        installmentYears: _i(j['installment_years']),
        paymentPlan: _s(j['payment_plan']),
        finishing: _s(j['finishing']),
        delivery: _s(j['delivery']),
      );
}

class ProjectMedia {
  ProjectMedia({required this.kind, required this.url, this.caption});
  final String kind; // image | brochure | video
  final String url;
  final String? caption;

  factory ProjectMedia.fromJson(Map<String, dynamic> j) => ProjectMedia(
        kind: '${j['kind']}',
        url: '${j['url']}',
        caption: _s(j['caption']),
      );
}

class ProjectDetail {
  ProjectDetail({required this.project, required this.units, required this.media});
  final Project project;
  final List<UnitType> units;
  final List<ProjectMedia> media;

  List<ProjectMedia> get images =>
      media.where((m) => m.kind == 'image').toList();
  List<ProjectMedia> get brochures =>
      media.where((m) => m.kind == 'brochure').toList();
  List<ProjectMedia> get videos =>
      media.where((m) => m.kind == 'video').toList();
}
