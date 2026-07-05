import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/favorite_service.dart';
import '../services/listing_service.dart';
import '../theme.dart';
import '../widgets/listing_card.dart';
import 'listing_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  late Future<List<Listing>> _future;

  @override
  void initState() {
    super.initState();
    _future = FavoriteService.instance.favoriteListings();
  }

  void _refresh() =>
      setState(() => _future = FavoriteService.instance.favoriteListings());

  Future<void> _unfav(String id) async {
    await FavoriteService.instance.toggle(id);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('favorites_title'))),
      body: FutureBuilder<List<Listing>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite_border,
                      color: Brand.muted, size: 48),
                  const SizedBox(height: 12),
                  Text(tr('no_favorites'),
                      style: const TextStyle(color: Brand.muted)),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                ...items.map((l) => ListingCard(
                      listing: l,
                      isFavorite: true,
                      onFavorite: () => _unfav(l.id),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              ListingDetailScreen(listingId: l.id))),
                    )),
              ],
            ),
          );
        },
      ),
    );
  }
}
