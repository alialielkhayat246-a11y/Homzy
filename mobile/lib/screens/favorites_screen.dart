import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/catalog_service.dart';
import '../services/favorite_service.dart';
import '../services/listing_service.dart';
import '../theme.dart';
import '../widgets/listing_card.dart';
import 'listing_detail_screen.dart';
import 'project_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  late Future<_Favs> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Favs> _load() async {
    final results = await Future.wait([
      FavoriteService.instance.favoriteProjects(),
      FavoriteService.instance.favoriteListings(),
    ]);
    return _Favs(results[0] as List<Project>, results[1] as List<Listing>);
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _unfavListing(String id) async {
    await FavoriteService.instance.toggle(id);
    _refresh();
  }

  Future<void> _unfavProject(String id) async {
    await FavoriteService.instance.toggleProject(id);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('favorites_title'))),
      body: FutureBuilder<_Favs>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final projects = snap.data!.projects;
          final listings = snap.data!.listings;
          if (projects.isEmpty && listings.isEmpty) {
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
                for (final p in projects)
                  _FavProjectCard(
                    project: p,
                    onUnfav: () => _unfavProject(p.id),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            ProjectDetailScreen(projectId: p.id))),
                  ),
                for (final l in listings)
                  ListingCard(
                    listing: l,
                    isFavorite: true,
                    onFavorite: () => _unfavListing(l.id),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ListingDetailScreen(listingId: l.id))),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Favs {
  _Favs(this.projects, this.listings);
  final List<Project> projects;
  final List<Listing> listings;
}

class _FavProjectCard extends StatelessWidget {
  const _FavProjectCard(
      {required this.project, required this.onTap, required this.onUnfav});
  final Project project;
  final VoidCallback onTap;
  final VoidCallback onUnfav;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Brand.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: project.coverImageUrl != null
                  ? Image.network(project.coverImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          color: Brand.navy,
                          child: const Icon(Icons.apartment,
                              color: Colors.white24)))
                  : Container(
                      color: Brand.navy,
                      child:
                          const Icon(Icons.apartment, color: Colors.white24)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(
                    [project.developerName, project.area]
                        .where((e) => e != null && e.isNotEmpty)
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Brand.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.favorite, color: Brand.coral),
              onPressed: onUnfav,
            ),
          ],
        ),
      ),
    );
  }
}
