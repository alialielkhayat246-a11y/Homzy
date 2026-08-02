import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n.dart';
import '../services/listing_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import '../widgets/listing_card.dart';
import 'listing_detail_screen.dart';

const _appLink = 'https://alialielkhayat246-a11y.github.io/Homzy/';

/// The broker's shareable storefront — their active listings + branded share.
class StorefrontScreen extends StatefulWidget {
  const StorefrontScreen({super.key});
  @override
  State<StorefrontScreen> createState() => _StorefrontScreenState();
}

class _StorefrontScreenState extends State<StorefrontScreen> {
  Map<String, dynamic>? _profile;
  List<Listing> _listings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await ProfileService.instance.get();
    final all = await ListingService.instance.myListings();
    if (!mounted) return;
    setState(() {
      _profile = p;
      _listings = all.where((l) => l.status == 'active').toList();
      _loading = false;
    });
  }

  Future<void> _share() async {
    final name = (_profile?['full_name'] ??
            ProfileService.instance.cachedName ??
            'Homzy')
        .toString();
    final phone = (_profile?['phone'] ?? '').toString();
    final company = (_profile?['company'] ?? '').toString();
    final ar = Lang.instance.isAr;
    final lines = <String>[
      '🏢 ${ar ? 'وحدات' : 'Listings by'} $name${company.isNotEmpty ? ' — $company' : ''}',
      '',
      ..._listings.take(15).map((l) =>
          '• ${l.title}${l.price != null ? ' · ${egp(l.price)}' : ''}${l.area != null ? ' · ${l.area}' : ''}'),
      '',
      if (phone.isNotEmpty) '${ar ? 'للتواصل' : 'Contact'}: $phone',
      _appLink,
    ];
    await launchUrl(
        Uri.parse('https://wa.me/?text=${Uri.encodeComponent(lines.join('\n'))}'),
        mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final name = (_profile?['full_name'] ??
            ProfileService.instance.cachedName ??
            '')
        .toString();
    final phone = (_profile?['phone'] ?? '').toString();
    final company = (_profile?['company'] ?? '').toString();
    return Scaffold(
      appBar: AppBar(title: Text(tr('storefront_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Brand.navy,
                      borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isEmpty ? 'Homzy' : name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      if (company.isNotEmpty)
                        Text(company,
                            style: const TextStyle(color: Colors.white70)),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(phone,
                            style: const TextStyle(color: Colors.white70)),
                      ],
                      const SizedBox(height: 4),
                      Text('${_listings.length} ${tr('st_active')}',
                          style: const TextStyle(
                              color: Brand.coral, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _listings.isEmpty ? null : _share,
                    icon: const Icon(Icons.share, size: 18),
                    label: Text(tr('share_storefront')),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Brand.green,
                        foregroundColor: Colors.white),
                  ),
                ),
                const SizedBox(height: 16),
                if (_listings.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                        child: Text(tr('storefront_empty'),
                            style: const TextStyle(color: Brand.muted))),
                  )
                else
                  ..._listings.map((l) => ListingCard(
                        listing: l,
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    ListingDetailScreen(listingId: l.id))),
                      )),
              ],
            ),
    );
  }
}
