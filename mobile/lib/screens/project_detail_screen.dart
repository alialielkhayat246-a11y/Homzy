import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n.dart';
import '../services/catalog_service.dart';
import '../theme.dart';

String _money(num? v) {
  if (v == null) return '—';
  final s = v.round().toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return 'EGP $b';
}

String _range(num? a, num? b, String suffix) {
  if (a == null && b == null) return '—';
  if (b == null || b == a) return '${a?.round()}$suffix';
  return '${a?.round()}–${b.round()}$suffix';
}

class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.projectId});
  final String projectId;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  late Future<ProjectDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = CatalogService.instance.detail(widget.projectId);
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Open a brochure PDF inside the app (via Google's document viewer in an
  /// in-app browser), so the client sees it without leaving Homzy.
  Future<void> _openBrochure(String url) async {
    final viewer =
        'https://docs.google.com/viewer?embedded=true&url=${Uri.encodeComponent(url)}';
    final uri = Uri.parse(viewer);
    try {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<ProjectDetail>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!;
          final p = d.project;
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                backgroundColor: Brand.navy,
                foregroundColor: Colors.white,
                flexibleSpace: FlexibleSpaceBar(
                  background: _Gallery(images: d.images, cover: p.coverImageUrl),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name,
                          style: GoogleFonts.poppins(
                              fontSize: 22, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        [p.developerName, p.area]
                            .where((e) => e != null && e.isNotEmpty)
                            .join(' · '),
                        style: const TextStyle(color: Brand.muted, fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (p.status != null) _chip(Icons.flag_outlined, p.status!),
                        if (p.delivery != null)
                          _chip(Icons.event_outlined,
                              '${tr('delivery')}: ${p.delivery}'),
                      ]),
                      if (p.description != null) ...[
                        const SizedBox(height: 16),
                        Text(p.description!,
                            style: const TextStyle(height: 1.5)),
                      ],
                      if (p.amenities != null && p.amenities!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _sectionTitle(tr('amenities')),
                        const SizedBox(height: 6),
                        Text(p.amenities!,
                            style: const TextStyle(color: Brand.muted, height: 1.5)),
                      ],

                      // Media buttons
                      if (d.brochures.isNotEmpty || d.videos.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Wrap(spacing: 10, runSpacing: 10, children: [
                          for (final b in d.brochures)
                            _mediaBtn(Icons.picture_as_pdf_outlined,
                                tr('brochure'), () => _openBrochure(b.url)),
                          for (final v in d.videos)
                            _mediaBtn(Icons.play_circle_outline, tr('video'),
                                () => _open(v.url)),
                        ]),
                      ],

                      // Unit types
                      const SizedBox(height: 22),
                      _sectionTitle(tr('unit_types')),
                      const SizedBox(height: 10),
                      ...d.units.map(_unitCard),

                      // Developer
                      if (p.developerAbout != null ||
                          p.developerTrack != null) ...[
                        const SizedBox(height: 22),
                        _sectionTitle(tr('about_developer')),
                        const SizedBox(height: 8),
                        if (p.developerName != null)
                          Text(p.developerName!,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15)),
                        if (p.developerAbout != null) ...[
                          const SizedBox(height: 4),
                          Text(p.developerAbout!,
                              style: const TextStyle(
                                  color: Brand.muted, height: 1.5)),
                        ],
                        if (p.developerTrack != null) ...[
                          const SizedBox(height: 10),
                          Text(tr('track_record'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(p.developerTrack!,
                              style: const TextStyle(
                                  color: Brand.muted, height: 1.5)),
                        ],
                      ],
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600));

  Widget _chip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: Brand.blueLight, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: const Color(0xFF0B4FAE)),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF0B4FAE),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _mediaBtn(IconData icon, String label, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: Brand.navy,
          side: const BorderSide(color: Brand.line),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

  Widget _unitCard(UnitType u) {
    final beds = (u.type == 'studio' || u.bedrooms == 0)
        ? 'Studio'
        : (u.bedrooms != null ? '${u.bedrooms} BR' : '');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  [u.type, beds].where((e) => e != null && e.isNotEmpty)
                      .join(' · '),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                u.priceFrom != null
                    ? '${tr('from_price')} ${_money(u.priceFrom)}'
                    : '—',
                style: const TextStyle(
                    color: Brand.blue, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_range(u.sizeFrom, u.sizeTo, ' m²')}'
            '${u.finishing != null ? ' · ${u.finishing}' : ''}',
            style: const TextStyle(color: Brand.muted, fontSize: 13),
          ),
          if (u.downPayment != null || u.paymentPlan != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.payments_outlined,
                    size: 16, color: Brand.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    u.paymentPlan ??
                        '${tr('down_payment')}: ${u.downPayment}',
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.images, this.cover});
  final List<ProjectMedia> images;
  final String? cover;

  @override
  Widget build(BuildContext context) {
    final urls = <String>[
      if (cover != null) cover!,
      ...images.map((m) => m.url),
    ];
    if (urls.isEmpty) {
      return Container(
        color: Brand.navy,
        child: const Center(
            child: Icon(Icons.apartment, color: Colors.white24, size: 64)),
      );
    }
    return PageView(
      children: [
        for (final u in urls)
          GestureDetector(
            onTap: () => _fullScreen(context, u),
            child: Image.network(u,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: Brand.navy)),
          ),
      ],
    );
  }

  void _fullScreen(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Center(child: Image.network(url)),
            ),
            Positioned(
              top: 40,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
