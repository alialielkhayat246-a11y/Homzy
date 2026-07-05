import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

String? _s(dynamic v) => v == null ? null : '$v';
num? _n(dynamic v) => v == null ? null : (v is num ? v : num.tryParse('$v'));
int? _i(dynamic v) => v == null ? null : (v is int ? v : int.tryParse('$v'));

/// A user-posted property listing (the marketplace side of Homzy).
class Listing {
  Listing({
    required this.id,
    required this.ownerId,
    required this.title,
    this.description,
    this.purpose = 'sale',
    this.type = 'apartment',
    this.price,
    this.currency = 'EGP',
    this.area,
    this.address,
    this.bedrooms,
    this.bathrooms,
    this.floor,
    this.sizeSqm,
    this.status = 'pending',
    this.lat,
    this.lng,
    this.images = const [],
    this.ownerName,
    this.ownerPhone,
  });

  final String id;
  final String ownerId;
  final String title;
  final String? description;
  final String purpose;
  final String type;
  final num? price;
  final String currency;
  final String? area;
  final String? address;
  final int? bedrooms;
  final int? bathrooms;
  final int? floor;
  final num? sizeSqm;
  final String status;
  final double? lat;
  final double? lng;
  final List<String> images;
  final String? ownerName;
  final String? ownerPhone;

  String? get cover => images.isNotEmpty ? images.first : null;

  factory Listing.fromJson(Map<String, dynamic> j) {
    final media = (j['listing_media'] as List?) ?? const [];
    final imgs = media
        .map((m) => (m as Map)['url']?.toString())
        .whereType<String>()
        .toList();
    return Listing(
      id: '${j['id']}',
      ownerId: '${j['owner_id'] ?? ''}',
      title: '${j['title'] ?? ''}',
      description: _s(j['description']),
      purpose: '${j['purpose'] ?? 'sale'}',
      type: '${j['type'] ?? 'apartment'}',
      price: _n(j['price']),
      currency: '${j['currency'] ?? 'EGP'}',
      area: _s(j['area']),
      address: _s(j['address']),
      bedrooms: _i(j['bedrooms']),
      bathrooms: _i(j['bathrooms']),
      floor: _i(j['floor']),
      sizeSqm: _n(j['size_sqm']),
      status: '${j['status'] ?? 'pending'}',
      lat: (j['lat'] as num?)?.toDouble(),
      lng: (j['lng'] as num?)?.toDouble(),
      images: imgs,
    );
  }
}

class ListingService {
  ListingService._();
  static final ListingService instance = ListingService._();
  SupabaseClient get _db => Supabase.instance.client;

  static const _sel = '*, listing_media(url, sort)';

  // Normalise Arabic so أ/إ/آ/ا and ة/ه and ى/ي match, and drop tashkeel.
  static String _norm(String s) => s
      .replaceAll(RegExp('[ؐ-ًؚ-ٰٟ]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .toLowerCase()
      .trim();

  // Keyword → filter maps (Arabic + English) so "ايجار" == rent, "شقة" == apartment.
  static const _purposeWords = {
    'rent': ['ايجار', 'للايجار', 'ايجارات', 'rent', 'rental', 'lease'],
    'sale': ['بيع', 'للبيع', 'تمليك', 'للتمليك', 'شراء', 'sale', 'buy', 'sell', 'own'],
  };
  static const _typeWords = {
    'apartment': ['شقه', 'شقق', 'apartment', 'flat'],
    'villa': ['فيلا', 'فيله', 'villa'],
    'duplex': ['دوبلكس', 'duplex'],
    'studio': ['استوديو', 'ستوديو', 'studio'],
    'townhouse': ['تاون', 'townhouse', 'town'],
    'twinhouse': ['توين', 'twinhouse', 'twin'],
    'chalet': ['شاليه', 'chalet'],
    'penthouse': ['بنتهاوس', 'penthouse'],
  };

  // Bilingual area groups so an English query matches an Arabic-stored area and
  // vice-versa. Each list holds the raw forms as they appear in listing text.
  static const _areaGroups = <List<String>>[
    ['new cairo', '5th settlement', 'التجمع الخامس', 'التجمع', 'القاهرة الجديدة'],
    ['sheikh zayed', 'zayed', 'الشيخ زايد', 'زايد'],
    ['6 october', '6th october', 'october', 'اكتوبر', 'أكتوبر', '٦ اكتوبر'],
    ['new capital', 'administrative capital', 'العاصمة الادارية', 'العاصمة'],
    ['north coast', 'sahel', 'الساحل الشمالي', 'الساحل'],
    ['madinaty', 'مدينتي'],
    ['mostakbal', 'المستقبل'],
    ['shorouk', 'الشروق'],
    ['obour', 'العبور'],
    ['maadi', 'المعادي'],
    ['ain sokhna', 'sokhna', 'السخنة', 'العين السخنة'],
    ['dreamland', 'dream land', 'دريم لاند'],
  ];

  /// If [text] names an area, return that area's full alias list (so we can
  /// search all forms); otherwise just [text].
  static List<String> _expandArea(String text) {
    final n = _norm(text);
    for (final g in _areaGroups) {
      if (g.any((a) => _norm(a) == n || n.contains(_norm(a)) || _norm(a).contains(n))) {
        return {text, ...g}.toList();
      }
    }
    return [text];
  }

  /// Pull purpose/type keywords out of a free-text query and return the
  /// leftover words (for a location/name match). Bilingual + Arabic-normalised.
  static ({String text, String? purpose, String? type}) _parse(String raw) {
    final tokens = _norm(raw).split(RegExp(r'[\s,،]+')).where((t) => t.isNotEmpty).toList();
    String? purpose, type;
    final rest = <String>[];
    for (final t in tokens) {
      String? matched;
      _purposeWords.forEach((k, ws) {
        if (purpose == null && ws.any((w) => t == w || t.contains(w))) purpose = k;
      });
      if (purpose != null && _purposeWords[purpose]!.any((w) => t.contains(w))) {
        matched = 'p';
      }
      _typeWords.forEach((k, ws) {
        if (type == null && ws.any((w) => t == w || t.contains(w))) type = k;
      });
      if (matched == null && type != null && _typeWords[type]!.any((w) => t.contains(w))) {
        matched = 't';
      }
      if (matched == null) rest.add(t);
    }
    return (text: rest.join(' ').trim(), purpose: purpose, type: type);
  }

  /// Public browse of active listings, with optional filters. When [search] is
  /// given it is parsed for bilingual purpose/type keywords, so "شقة للايجار
  /// في زايد" filters purpose=rent, type=apartment and text-matches "زايد".
  Future<List<Listing>> browse({
    String? search,
    String? area,
    String? type,
    String? purpose,
    num? priceMax,
  }) async {
    var q = _db.from('listings').select(_sel).eq('status', 'active');
    if (search != null && search.trim().isNotEmpty) {
      final p = _parse(search);
      purpose ??= p.purpose;
      type ??= p.type;
      if (p.text.isNotEmpty) {
        // Match the term (and its area aliases) across title/area/address.
        final conds = <String>[];
        for (final t in _expandArea(p.text)) {
          conds.add('title.ilike.%$t%');
          conds.add('area.ilike.%$t%');
          conds.add('address.ilike.%$t%');
        }
        q = q.or(conds.join(','));
      }
    }
    if (area != null && area.isNotEmpty) q = q.ilike('area', '%$area%');
    if (type != null && type.isNotEmpty) q = q.eq('type', type);
    if (purpose != null && purpose.isNotEmpty) q = q.eq('purpose', purpose);
    if (priceMax != null) q = q.lte('price', priceMax);
    final rows = await q.order('created_at', ascending: false).limit(100);
    return (rows as List)
        .map((r) => Listing.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// The signed-in user's own listings (any status).
  Future<List<Listing>> myListings() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _db
        .from('listings')
        .select(_sel)
        .eq('owner_id', uid)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => Listing.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Listing> detail(String id) async {
    final row = await _db.from('listings').select(_sel).eq('id', id).single();
    final listing = Listing.fromJson(row);
    // Owner contact comes from the profiles table (no direct FK to embed).
    try {
      final prof = await _db
          .from('profiles')
          .select('full_name, phone')
          .eq('id', listing.ownerId)
          .maybeSingle();
      if (prof != null) {
        return Listing(
          id: listing.id,
          ownerId: listing.ownerId,
          title: listing.title,
          description: listing.description,
          purpose: listing.purpose,
          type: listing.type,
          price: listing.price,
          currency: listing.currency,
          area: listing.area,
          address: listing.address,
          bedrooms: listing.bedrooms,
          bathrooms: listing.bathrooms,
          floor: listing.floor,
          sizeSqm: listing.sizeSqm,
          status: listing.status,
          lat: listing.lat,
          lng: listing.lng,
          images: listing.images,
          ownerName: _s(prof['full_name']),
          ownerPhone: _s(prof['phone']),
        );
      }
    } catch (_) {}
    return listing;
  }

  /// Create a listing and return its id. Starts as 'pending'.
  Future<String> create({
    required String title,
    String? description,
    required String purpose,
    required String type,
    num? price,
    String? area,
    String? address,
    int? bedrooms,
    int? bathrooms,
    int? floor,
    num? sizeSqm,
    double? lat,
    double? lng,
  }) async {
    final uid = _db.auth.currentUser!.id;
    final row = await _db.from('listings').insert({
      'owner_id': uid,
      'title': title,
      'description': description,
      'purpose': purpose,
      'type': type,
      'price': price,
      'area': area,
      'address': address,
      'bedrooms': bedrooms,
      'bathrooms': bathrooms,
      'floor': floor,
      'size_sqm': sizeSqm,
      'lat': lat,
      'lng': lng,
      'status': 'active',
    }).select('id').single();
    return '${row['id']}';
  }

  Future<void> setStatus(String id, String status) =>
      _db.from('listings').update({'status': status}).eq('id', id);

  Future<void> remove(String id) =>
      _db.from('listings').delete().eq('id', id);

  /// Upload a photo to the 'listings' bucket and attach it to the listing.
  Future<String> addPhoto(String listingId, Uint8List bytes, String ext,
      {int sort = 0}) async {
    final uid = _db.auth.currentUser!.id;
    final path =
        '$uid/$listingId/${DateTime.now().millisecondsSinceEpoch}_$sort.$ext';
    await _db.storage.from('listings').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
              contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
              upsert: true),
        );
    final url = _db.storage.from('listings').getPublicUrl(path);
    await _db.from('listing_media').insert(
        {'listing_id': listingId, 'url': url, 'sort': sort});
    return url;
  }
}
