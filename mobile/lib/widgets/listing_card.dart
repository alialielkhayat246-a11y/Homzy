import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/listing_service.dart';
import '../theme.dart';

/// EGP price with thousands separators, e.g. 3850000 -> "3,850,000 ج".
String egp(num? v) {
  if (v == null) return '—';
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '$b ${Lang.instance.isAr ? 'ج' : 'EGP'}';
}

String typeLabel(String type) {
  final key = 'type_${type.toLowerCase()}';
  final t = tr(key);
  return t == key ? type : t;
}

/// The horizontal property card used in search results and favorites.
class ListingCard extends StatelessWidget {
  const ListingCard({
    super.key,
    required this.listing,
    required this.onTap,
    this.isFavorite = false,
    this.onFavorite,
  });

  final Listing listing;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback? onFavorite;

  @override
  Widget build(BuildContext context) {
    final beds = listing.bedrooms;
    final parts = <String>[
      if (listing.area != null && listing.area!.isNotEmpty) listing.area!,
      if (listing.sizeSqm != null) '${listing.sizeSqm!.round()} م²',
    ];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Brand.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Brand.line),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 96,
                height: 96,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    listing.cover != null
                        ? Image.network(listing.cover!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _ph())
                        : _ph(),
                    if (onFavorite != null)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: GestureDetector(
                          onTap: onFavorite,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                                color: Colors.white70, shape: BoxShape.circle),
                            child: Icon(
                              isFavorite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 16,
                              color: Brand.coral,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(egp(listing.price),
                      style: const TextStyle(
                          color: Brand.coral,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    listing.title.isNotEmpty
                        ? listing.title
                        : '${typeLabel(listing.type)}${beds != null ? ' · $beds ${tr('beds_short')}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 3),
                  Text(parts.join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Brand.muted, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ph() => Container(
        color: Brand.cream,
        child: const Icon(Icons.apartment, color: Brand.muted, size: 30),
      );
}
