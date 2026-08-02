import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/catalog_service.dart';
import '../theme.dart';
import 'map_screen.dart';
import 'project_detail_screen.dart';
import 'projects_screen.dart';

/// PropertyHub-style discovery hub: map, cities, developers, latest launches.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  List<CityCount> _cities = [];
  List<DeveloperCount> _devs = [];
  List<Project> _launches = [];

  @override
  void initState() {
    super.initState();
    final c = CatalogService.instance;
    c.cities().then((v) => mounted ? setState(() => _cities = v) : null);
    c.developers().then((v) => mounted ? setState(() => _devs = v) : null);
    c.projects().then((v) =>
        mounted ? setState(() => _launches = v.take(12).toList()) : null);
  }

  void _open(Widget s) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => s));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('discover'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // Interactive map
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _open(const MapScreen()),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Brand.navy, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  const Icon(Icons.map_outlined, color: Colors.white, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('map_explore'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                        Text(tr('map_explore_sub'),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white54),
                ]),
              ),
            ),
          ),

          _sectionTitle(tr('disc_cities')),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _cities.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _cityCard(_cities[i]),
            ),
          ),

          _sectionTitle(tr('disc_developers')),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _devs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _devChip(_devs[i]),
            ),
          ),

          _sectionTitle(tr('disc_launches')),
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _launches.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _launchCard(_launches[i]),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: Text(t,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      );

  Widget _cityCard(CityCount c) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(ProjectsScreen(initialArea: c.area, title: c.area)),
        child: Container(
          width: 150,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Brand.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Brand.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_city, color: Brand.coral, size: 22),
              const Spacer(),
              Text(c.area,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 2),
              Text('${c.projects} ${tr('disc_projects')} · ${c.units} ${tr('disc_units')}',
                  style: const TextStyle(color: Brand.muted, fontSize: 11)),
            ],
          ),
        ),
      );

  Widget _devChip(DeveloperCount d) => InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _open(
            ProjectsScreen(initialDeveloperId: d.id, title: d.name)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Brand.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Brand.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(d.name,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: Brand.coralLight,
                  borderRadius: BorderRadius.circular(10)),
              child: Text('${d.projects}',
                  style: const TextStyle(
                      color: Brand.coral,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      );

  Widget _launchCard(Project p) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () =>
            _open(ProjectDetailScreen(projectId: p.id)),
        child: SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 110,
                  width: 220,
                  child: p.coverImageUrl != null
                      ? Image.network(p.coverImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              color: Brand.navy,
                              child: const Icon(Icons.apartment,
                                  color: Colors.white24)))
                      : Container(
                          color: Brand.navy,
                          child: const Icon(Icons.apartment,
                              color: Colors.white24)),
                ),
              ),
              const SizedBox(height: 6),
              Text(p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)),
              Text(
                  [p.developerName, p.area]
                      .where((e) => e != null && e.isNotEmpty)
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Brand.muted, fontSize: 11)),
            ],
          ),
        ),
      );
}
