import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../i18n.dart';
import '../theme.dart';

/// Shows a property's location on an OpenStreetMap map (no API key needed).
class LocationScreen extends StatelessWidget {
  const LocationScreen({
    super.key,
    required this.lat,
    required this.lng,
    required this.title,
    this.subtitle,
  });

  final double lat;
  final double lng;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(lat, lng);
    return Scaffold(
      appBar: AppBar(title: Text(tr('location_label'))),
      body: Column(
        children: [
          SizedBox(
            height: 320,
            child: FlutterMap(
              options: MapOptions(initialCenter: point, initialZoom: 14),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.homzy.app',
                ),
                MarkerLayer(markers: [
                  Marker(
                    point: point,
                    width: 44,
                    height: 44,
                    child: const Icon(Icons.location_on,
                        color: Brand.coral, size: 44),
                  ),
                ]),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!,
                      style: const TextStyle(color: Brand.muted, fontSize: 13)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
