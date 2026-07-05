import 'package:supabase_flutter/supabase_flutter.dart';

import 'listing_service.dart';

/// Saved listings (and byit projects) for the current user.
class FavoriteService {
  FavoriteService._();
  static final FavoriteService instance = FavoriteService._();
  SupabaseClient get _db => Supabase.instance.client;

  /// Ids of listings the user has favorited (for filled/empty hearts).
  Future<Set<String>> listingIds() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return {};
    final rows = await _db
        .from('favorites')
        .select('listing_id')
        .eq('user_id', uid)
        .not('listing_id', 'is', null);
    return (rows as List)
        .map((r) => (r as Map)['listing_id']?.toString())
        .whereType<String>()
        .toSet();
  }

  Future<bool> isFavorite(String listingId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return false;
    final row = await _db
        .from('favorites')
        .select('id')
        .eq('user_id', uid)
        .eq('listing_id', listingId)
        .maybeSingle();
    return row != null;
  }

  /// Toggle a listing favorite; returns the new state (true = now saved).
  Future<bool> toggle(String listingId) async {
    final uid = _db.auth.currentUser!.id;
    final existing = await _db
        .from('favorites')
        .select('id')
        .eq('user_id', uid)
        .eq('listing_id', listingId)
        .maybeSingle();
    if (existing != null) {
      await _db.from('favorites').delete().eq('id', existing['id']);
      return false;
    }
    await _db
        .from('favorites')
        .insert({'user_id': uid, 'listing_id': listingId});
    return true;
  }

  /// Full listing objects the user has saved.
  Future<List<Listing>> favoriteListings() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _db
        .from('favorites')
        .select('listing:listings(*, listing_media(url, sort))')
        .eq('user_id', uid)
        .not('listing_id', 'is', null)
        .order('created_at', ascending: false);
    final out = <Listing>[];
    for (final r in rows as List) {
      final l = (r as Map)['listing'];
      if (l != null) out.add(Listing.fromJson(l as Map<String, dynamic>));
    }
    return out;
  }
}
