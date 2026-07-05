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

  /// Public browse of active listings, with optional filters.
  Future<List<Listing>> browse({
    String? search,
    String? area,
    String? type,
    String? purpose,
    num? priceMax,
  }) async {
    var q = _db.from('listings').select(_sel).eq('status', 'active');
    if (search != null && search.trim().isNotEmpty) {
      final s = search.trim().replaceAll(',', ' ');
      q = q.or('title.ilike.%$s%,area.ilike.%$s%,address.ilike.%$s%');
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
