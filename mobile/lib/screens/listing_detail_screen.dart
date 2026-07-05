import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n.dart';
import '../services/favorite_service.dart';
import '../services/listing_service.dart';
import '../services/message_service.dart';
import '../theme.dart';
import '../widgets/listing_card.dart';
import 'location_screen.dart';
import 'message_thread_screen.dart';

class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({super.key, required this.listingId});
  final String listingId;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  late Future<Listing> _future;
  bool _fav = false;

  @override
  void initState() {
    super.initState();
    _future = ListingService.instance.detail(widget.listingId);
    FavoriteService.instance.isFavorite(widget.listingId).then((v) {
      if (mounted) setState(() => _fav = v);
    });
  }

  Future<void> _toggleFav() async {
    final now = await FavoriteService.instance.toggle(widget.listingId);
    setState(() => _fav = now);
  }

  Future<void> _whatsapp(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final num = digits.startsWith('0') ? '2$digits' : digits;
    final uri = Uri.parse('https://wa.me/$num');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _contact(Listing l) async {
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null || me == l.ownerId) return;
    final convId = await MessageService.instance
        .startOrGet(listingId: l.id, sellerId: l.ownerId);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MessageThreadScreen(
            conversationId: convId, title: l.ownerName ?? l.title)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Listing>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final l = snap.data!;
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 250,
                pinned: true,
                backgroundColor: Brand.navy,
                foregroundColor: Colors.white,
                actions: [
                  IconButton(
                    onPressed: _toggleFav,
                    icon: Icon(_fav ? Icons.favorite : Icons.favorite_border,
                        color: _fav ? Brand.coral : Colors.white),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: _Gallery(images: l.images),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: Brand.navy,
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(tr('featured'),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ),
                          Text(egp(l.price),
                              style: const TextStyle(
                                  color: Brand.coral,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(l.title,
                          style: const TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.location_on_outlined,
                            size: 16, color: Brand.muted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                              [l.area, l.address]
                                  .where((e) => e != null && e.isNotEmpty)
                                  .join(' · '),
                              style: const TextStyle(
                                  color: Brand.muted, fontSize: 13)),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          if (l.floor != null)
                            _spec(Icons.stairs_outlined, '${l.floor}',
                                tr('floor_short')),
                          if (l.bathrooms != null)
                            _spec(Icons.bathtub_outlined, '${l.bathrooms}',
                                tr('baths_short')),
                          if (l.bedrooms != null)
                            _spec(Icons.king_bed_outlined, '${l.bedrooms}',
                                tr('beds_short')),
                          if (l.sizeSqm != null)
                            _spec(Icons.straighten,
                                '${l.sizeSqm!.round()}', 'م²'),
                        ],
                      ),
                      if (l.description != null &&
                          l.description!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(tr('desc_label'),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(l.description!,
                            style: const TextStyle(
                                color: Brand.muted, height: 1.6)),
                      ],
                      if (l.lat != null && l.lng != null) ...[
                        const SizedBox(height: 20),
                        _locationButton(l),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _contact(l),
                              icon: const Icon(Icons.chat_bubble_outline,
                                  size: 18),
                              label: Text(tr('contact_owner')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Brand.green),
                              onPressed: () => _whatsapp(l.ownerPhone),
                              icon: const Icon(Icons.call, size: 18),
                              label: Text(tr('whatsapp')),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
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

  Widget _locationButton(Listing l) => GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => LocationScreen(
                lat: l.lat!,
                lng: l.lng!,
                title: l.area ?? l.title,
                subtitle: l.address))),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Brand.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Brand.line)),
          child: Row(children: [
            const Icon(Icons.map_outlined, color: Brand.navy),
            const SizedBox(width: 10),
            Text(tr('view_location'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Brand.muted),
          ]),
        ),
      );

  Widget _spec(IconData icon, String value, String label) => Column(
        children: [
          Icon(icon, color: Brand.navy, size: 22),
          const SizedBox(height: 4),
          Text('$value $label',
              style: const TextStyle(fontSize: 12, color: Brand.muted)),
        ],
      );
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.images});
  final List<String> images;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return Container(
        color: Brand.navy,
        child: const Center(
            child: Icon(Icons.apartment, color: Colors.white24, size: 64)),
      );
    }
    return PageView(
      children: [
        for (final u in images)
          Image.network(u,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: Brand.navy)),
      ],
    );
  }
}
