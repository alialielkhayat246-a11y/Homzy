import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/listing_service.dart';
import '../theme.dart';
import '../widgets/listing_card.dart';
import 'add_listing_screen.dart';
import 'listing_detail_screen.dart';

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  late Future<List<Listing>> _future;
  String _tab = 'all'; // all | active | pending | inactive

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() =>
      setState(() => _future = ListingService.instance.myListings());

  Future<void> _add() async {
    final done = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const AddListingScreen()));
    if (done == true) _refresh();
  }

  Future<void> _setStatus(Listing l, String status) async {
    await ListingService.instance.setStatus(l.id, status);
    _refresh();
  }

  Future<void> _delete(Listing l) async {
    await ListingService.instance.remove(l.id);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('my_listings_title'))),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Brand.navy,
        foregroundColor: Colors.white,
        onPressed: _add,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(tr('add_new_listing'),
            style: const TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              children: [
                _tabChip('all', tr('tab_all')),
                _tabChip('active', tr('st_active')),
                _tabChip('pending', tr('st_pending')),
                _tabChip('inactive', tr('st_inactive')),
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
                final all = snap.data!;
                final items = _tab == 'all'
                    ? all
                    : all.where((l) => l.status == _tab).toList();
                if (items.isEmpty) {
                  return Center(
                    child: Text(tr('no_projects'),
                        style: const TextStyle(color: Brand.muted)),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                  children: [
                    ...items.map(_ownedCard),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(String key, String label) {
    final active = _tab == key;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        selected: active,
        showCheckmark: false,
        label: Text(label,
            style: TextStyle(
                color: active ? Colors.white : Brand.navy,
                fontWeight: FontWeight.w600,
                fontSize: 12.5)),
        selectedColor: Brand.navy,
        backgroundColor: Brand.card,
        side: BorderSide(color: active ? Brand.navy : Brand.line),
        onSelected: (_) => setState(() => _tab = key),
      ),
    );
  }

  Widget _ownedCard(Listing l) {
    return Stack(
      children: [
        ListingCard(
          listing: l,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ListingDetailScreen(listingId: l.id))),
        ),
        PositionedDirectional(
          top: 14,
          end: 14,
          child: Row(
            children: [
              _statusBadge(l.status),
              const SizedBox(width: 4),
              _menu(l),
            ],
          ),
        ),
      ],
    );
  }

  Widget _menu(Listing l) => PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18, color: Brand.muted),
        onSelected: (v) {
          if (v == 'delete') {
            _delete(l);
          } else {
            _setStatus(l, v);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'active', child: Text(tr('st_active'))),
          PopupMenuItem(value: 'inactive', child: Text(tr('st_inactive'))),
          PopupMenuItem(
              value: 'delete',
              child: Text(tr('delete_listing'),
                  style: const TextStyle(color: Brand.red))),
        ],
      );

  Widget _statusBadge(String status) {
    late Color c;
    late String label;
    switch (status) {
      case 'active':
        c = Brand.green;
        label = tr('st_active');
        break;
      case 'pending':
        c = Brand.amber;
        label = tr('st_pending');
        break;
      default:
        c = Brand.muted;
        label = tr('st_inactive');
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: c.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: TextStyle(
              color: c, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
