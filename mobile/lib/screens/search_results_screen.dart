import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/favorite_service.dart';
import '../services/listing_service.dart';
import '../theme.dart';
import '../widgets/listing_card.dart';
import 'listing_detail_screen.dart';

class SearchResultsScreen extends StatefulWidget {
  const SearchResultsScreen({super.key, this.query});
  final String? query;

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
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

  void _refresh() {
    setState(() {
      _future = ListingService.instance.browse(
        search: widget.query,
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
      appBar: AppBar(title: Text(tr('search_results'))),
      body: Column(
        children: [
          if (widget.query != null && widget.query!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(widget.query!,
                    style: const TextStyle(color: Brand.muted, fontSize: 13)),
              ),
            ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              children: [
                _chip(tr('flt_filter'), Icons.tune, _openFilter),
                _chip(tr('flt_price'), Icons.sell_outlined, _openFilter,
                    active: _priceMax != null),
                _chip(tr('property_type'), Icons.home_work_outlined, _openFilter,
                    active: _type != null),
                _chip(tr('flt_more'), Icons.more_horiz, _openFilter),
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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

  Widget _chip(String label, IconData icon, VoidCallback onTap,
      {bool active = false}) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ActionChip(
        avatar: Icon(icon,
            size: 16, color: active ? Colors.white : Brand.navy),
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
    String? purpose = _purpose;
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
              Text(tr('flt_filter'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              Text(tr('nav_home') == 'Home' ? 'Purpose' : 'الغرض',
                  style: const TextStyle(fontSize: 13, color: Brand.muted)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                _seg(tr('tab_all'), purpose == null,
                    () => setSheet(() => purpose = null)),
                _seg(tr('for_sale'), purpose == 'sale',
                    () => setSheet(() => purpose = 'sale')),
                _seg(tr('for_rent'), purpose == 'rent',
                    () => setSheet(() => purpose = 'rent')),
              ]),
              const SizedBox(height: 14),
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
              Text(priceMax == null ? tr('tab_all') : egp(priceMax),
                  style: const TextStyle(color: Brand.muted, fontSize: 12)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _type = type;
                      _purpose = purpose;
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
