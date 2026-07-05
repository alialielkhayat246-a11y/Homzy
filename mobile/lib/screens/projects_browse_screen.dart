import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/favorite_service.dart';
import '../services/listing_service.dart';
import '../theme.dart';
import '../widgets/listing_card.dart';
import 'listing_detail_screen.dart';

/// The "Projects" tab: a search bar + filters over all active listings.
class ProjectsBrowseScreen extends StatefulWidget {
  const ProjectsBrowseScreen({super.key});

  @override
  State<ProjectsBrowseScreen> createState() => _ProjectsBrowseScreenState();
}

class _ProjectsBrowseScreenState extends State<ProjectsBrowseScreen> {
  final _search = TextEditingController();
  late Future<List<Listing>> _future;
  Set<String> _favs = {};
  String? _type;
  String? _purpose;
  num? _priceMax;

  @override
  void initState() {
    super.initState();
    _refresh();
    FavoriteService.instance.listingIds().then((s) {
      if (mounted) setState(() => _favs = s);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _future = ListingService.instance.browse(
        search: _search.text.trim().isEmpty ? null : _search.text.trim(),
        type: _type,
        purpose: _purpose,
        priceMax: _priceMax,
      );
    });
  }

  Future<void> _toggleFav(String id) async {
    final now = await FavoriteService.instance.toggle(id);
    setState(() => now ? _favs.add(id) : _favs.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(tr('nav_projects')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _refresh(),
              decoration: InputDecoration(
                hintText: tr('browse_search_hint'),
                prefixIcon: const Icon(Icons.search, color: Brand.muted),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward, color: Brand.coral),
                  onPressed: _refresh,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Brand.line),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                _chip(tr('flt_filter'), Icons.tune, _openFilter),
                _chip(tr('flt_price'), Icons.sell_outlined, _openFilter,
                    active: _priceMax != null),
                _chip(tr('property_type'), Icons.home_work_outlined, _openFilter,
                    active: _type != null),
                _chip(tr('for_rent'), Icons.vpn_key_outlined,
                    () => _quickPurpose('rent'),
                    active: _purpose == 'rent'),
                _chip(tr('for_sale'), Icons.sell_outlined,
                    () => _quickPurpose('sale'),
                    active: _purpose == 'sale'),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Listing>>(
              future: _future,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data!;
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(30),
                      child: Text(tr('no_results'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Brand.muted)),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  children: [
                    Text('${items.length} ${tr('results_count')}',
                        style:
                            const TextStyle(color: Brand.muted, fontSize: 13)),
                    const SizedBox(height: 8),
                    ...items.map((l) => ListingCard(
                          listing: l,
                          isFavorite: _favs.contains(l.id),
                          onFavorite: () => _toggleFav(l.id),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      ListingDetailScreen(listingId: l.id))),
                        )),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _quickPurpose(String p) {
    setState(() => _purpose = _purpose == p ? null : p);
    _refresh();
  }

  Widget _chip(String label, IconData icon, VoidCallback onTap,
      {bool active = false}) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 16, color: active ? Colors.white : Brand.navy),
        label: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                color: active ? Colors.white : Brand.navy,
                fontWeight: FontWeight.w600)),
        backgroundColor: active ? Brand.navy : Brand.card,
        side: BorderSide(color: active ? Brand.navy : Brand.line),
        onPressed: onTap,
      ),
    );
  }

  void _openFilter() {
    String? type = _type;
    num? priceMax = _priceMax;
    showModalBottomSheet(
      context: context,
      backgroundColor: Brand.cream,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              18, 18, 18, MediaQuery.of(ctx).viewInsets.bottom + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('property_type'),
                  style: const TextStyle(fontSize: 13, color: Brand.muted)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in const [
                  'apartment',
                  'duplex',
                  'villa',
                  'studio',
                  'chalet'
                ])
                  _seg(typeLabel(t), type == t,
                      () => setSheet(() => type = type == t ? null : t)),
              ]),
              const SizedBox(height: 14),
              Text(tr('flt_price'),
                  style: const TextStyle(fontSize: 13, color: Brand.muted)),
              Slider(
                value: (priceMax ?? 20000000).toDouble(),
                min: 500000,
                max: 20000000,
                divisions: 39,
                label: egp(priceMax ?? 20000000),
                activeColor: Brand.coral,
                onChanged: (v) => setSheet(() => priceMax = v),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _type = type;
                      _priceMax =
                          (priceMax != null && priceMax! >= 20000000)
                              ? null
                              : priceMax;
                    });
                    _refresh();
                    Navigator.pop(ctx);
                  },
                  child: Text(tr('flt_filter')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seg(String label, bool active, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? Brand.navy : Brand.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? Brand.navy : Brand.line),
          ),
          child: Text(label,
              style: TextStyle(
                  color: active ? Colors.white : Brand.navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      );
}
