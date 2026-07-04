import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads the developers / projects / unit-types / media catalog from Supabase.
class CatalogService {
  CatalogService._();
  static final CatalogService instance = CatalogService._();
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<Project>> projects({
    String? search,
    String? area,
    String? unitType,
    String? delivery,
  }) async {
    final joinUnit = unitType != null && unitType.isNotEmpty;
    final sel = joinUnit
        ? '*, developer:developers(name, about, track_record, phone, website), unit_types!inner(type)'
        : '*, developer:developers(name, about, track_record, phone, website)';
    var q = _db.from('projects').select(sel);
    if (search != null && search.trim().isNotEmpty) {
      final s = search.trim().replaceAll(',', ' ');
      q = q.or('name.ilike.%$s%,area.ilike.%$s%');
    }
    if (area != null && area.isNotEmpty) q = q.ilike('area', '%$area%');
    if (delivery != null && delivery.isNotEmpty) {
      q = q.ilike('delivery', '%$delivery%');
    }
    if (joinUnit) q = q.eq('unit_types.type', unitType);
    final rows = await q.order('updated_at', ascending: false).limit(300);
    // de-dupe (inner join can repeat a project)
    final seen = <String>{};
    final out = <Project>[];
    for (final r in rows as List) {
      final p = Project.fromJson(r as Map<String, dynamic>);
      if (seen.add(p.id)) out.add(p);
    }
    return out;
  }

  /// Distinct area names for the filter dropdown.
  Future<List<String>> areas() async {
    final rows =
        await _db.from('projects').select('area').not('area', 'is', null);
    final set = <String>{};
    for (final r in rows as List) {
      final a = (r as Map)['area']?.toString();
      if (a != null && a.trim().isNotEmpty) set.add(a.trim());
    }
    final list = set.toList()..sort();
    return list;
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
