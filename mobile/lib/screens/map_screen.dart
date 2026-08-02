import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../i18n.dart';
import '../services/catalog_service.dart';
import '../theme.dart';
import 'projects_screen.dart';

/// Approximate centre of each area, so catalog projects (which don't all carry
/// exact coordinates) cluster on their city on the map.
const Map<String, LatLng> _centroids = {
  'new cairo': LatLng(30.030, 31.470),
  'new capital': LatLng(30.020, 31.750),
  'north coast': LatLng(30.900, 28.900),
  'new zayed': LatLng(30.020, 30.940),
  'sheikh zayed': LatLng(30.020, 30.970),
  'october': LatLng(29.950, 30.920),
  'mostakbal': LatLng(30.100, 31.650),
  'madinaty': LatLng(30.100, 31.640),
  'shorouk': LatLng(30.120, 31.620),
  'obour': LatLng(30.220, 31.470),
  'maadi': LatLng(29.960, 31.280),
  'sokhna': LatLng(29.600, 32.310),
  'galala': LatLng(29.350, 32.280),
  'ras el hekma': LatLng(31.100, 27.800),
  'alamein': LatLng(30.830, 28.950),
  'mansoura': LatLng(31.440, 31.360),
  'alexandria': LatLng(31.200, 29.920),
};

LatLng? _centroidFor(String area) {
  final a = area.toLowerCase();
  for (final e in _centroids.entries) {
    if (a.contains(e.key)) return e.value;
  }
  return null;
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<CityCount> _cities = [];

  @override
  void initState() {
    super.initState();
    CatalogService.instance
        .cities()
        .then((v) => mounted ? setState(() => _cities = v) : null);
  }

  @override
  Widget build(BuildContext context) {
    // Merge areas that share a centroid (e.g. "6 October" + "6th of October").
    final merged = <LatLng, ({String area, int projects})>{};
    for (final c in _cities) {
      final pos = _centroidFor(c.area);
      if (pos == null) continue;
      final cur = merged[pos];
      merged[pos] = cur == null || c.projects > cur.projects
          ? (area: c.area, projects: (cur?.projects ?? 0) + c.projects)
          : (area: cur.area, projects: cur.projects + c.projects);
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('map_title'))),
      body: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(30.0, 31.0),
          initialZoom: 6.4,
          minZoom: 5,
          maxZoom: 14,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.homzy.app',
          ),
          MarkerLayer(
            markers: [
              for (final e in merged.entries)
                Marker(
                  point: e.key,
                  width: 120,
                  height: 54,
                  child: _MapPin(
                    area: e.value.area,
                    count: e.value.projects,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ProjectsScreen(
                            initialArea: e.value.area, title: e.value.area))),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.area, required this.count, required this.onTap});
  final String area;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Brand.navy,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 1.2),
            ),
            child: Text('$area · $count',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ),
          const Icon(Icons.location_on, color: Brand.coral, size: 22),
        ],
      ),
    );
  }
}
