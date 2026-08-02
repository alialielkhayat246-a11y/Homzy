import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n.dart';
import '../services/cobroking_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import '../widgets/listing_card.dart' show egp, typeLabel;

class CobrokingScreen extends StatefulWidget {
  const CobrokingScreen({super.key});
  @override
  State<CobrokingScreen> createState() => _CobrokingScreenState();
}

class _CobrokingScreenState extends State<CobrokingScreen> {
  late Future<List<CoPost>> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() => setState(() => _future = CobrokingService.instance.list());

  Future<void> _add() async {
    final done = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const CoPostFormScreen()));
    if (done == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('cobroking_title'))),
      floatingActionButton: ProfileService.instance.isBroker
          ? FloatingActionButton.extended(
              backgroundColor: Brand.navy,
              foregroundColor: Colors.white,
              onPressed: _add,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(tr('co_add'),
                  style: const TextStyle(color: Colors.white)),
            )
          : null,
      body: FutureBuilder<List<CoPost>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return Center(
                child: Text(tr('co_empty'),
                    style: const TextStyle(color: Brand.muted)));
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _card(items[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _card(CoPost p) {
    final brief = [
      if (p.purpose != null) tr(p.purpose == 'rent' ? 'for_rent' : 'for_sale'),
      if (p.type != null) typeLabel(p.type!),
      if (p.area != null && p.area!.isNotEmpty) p.area!,
      if (p.bedrooms != null) '${p.bedrooms} ${tr('beds_short')}',
      if (p.budget != null) egp(p.budget),
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: p.isWant ? Brand.coralLight : Brand.cream,
                  borderRadius: BorderRadius.circular(8)),
              child: Text(p.isWant ? tr('co_want') : tr('co_have'),
                  style: TextStyle(
                      color: p.isWant ? Brand.coral : Brand.navy,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(p.title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          if (brief.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(brief, style: const TextStyle(color: Brand.muted, fontSize: 12.5)),
          ],
          if (p.description != null && p.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(p.description!, style: const TextStyle(height: 1.4, fontSize: 13.5)),
          ],
          if (p.phone != null && p.phone!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () {
                  final ph = p.phone!.replaceAll(RegExp(r'[^0-9]'), '');
                  launchUrl(Uri.parse('https://wa.me/$ph'),
                      mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.chat, size: 16, color: Brand.green),
                label: Text(tr('co_contact')),
                style: OutlinedButton.styleFrom(
                    foregroundColor: Brand.green,
                    side: const BorderSide(color: Brand.line)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class CoPostFormScreen extends StatefulWidget {
  const CoPostFormScreen({super.key});
  @override
  State<CoPostFormScreen> createState() => _CoPostFormScreenState();
}

class _CoPostFormScreenState extends State<CoPostFormScreen> {
  final _title = TextEditingController();
  final _area = TextEditingController();
  final _beds = TextEditingController();
  final _budget = TextEditingController();
  final _desc = TextEditingController();
  final _phone = TextEditingController();
  String _kind = 'have';
  String _purpose = 'sale';
  String? _type;
  bool _saving = false;

  static const _types = [
    'apartment', 'studio', 'duplex', 'penthouse',
    'villa', 'townhouse', 'twinhouse', 'chalet', 'office', 'shop',
  ];

  @override
  void initState() {
    super.initState();
    _phone.text = ProfileService.instance.cachedPhone ?? '';
  }

  @override
  void dispose() {
    for (final c in [_title, _area, _beds, _budget, _desc, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('title_required'))));
      return;
    }
    setState(() => _saving = true);
    try {
      await CobrokingService.instance.create({
        'kind': _kind,
        'title': _title.text.trim(),
        'purpose': _purpose,
        'type': _type,
        'area': _t(_area),
        'bedrooms': int.tryParse(_beds.text.trim()),
        'budget': num.tryParse(_budget.text.replaceAll(',', '').trim()),
        'description': _t(_desc),
        'phone': _t(_phone),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
        setState(() => _saving = false);
      }
    }
  }

  String? _t(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('co_add'))),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Row(children: [
          for (final k in const ['have', 'want'])
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _kind = k),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _kind == k ? Brand.navy : Brand.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _kind == k ? Brand.navy : Brand.line),
                    ),
                    child: Text(k == 'want' ? tr('co_want') : tr('co_have'),
                        style: TextStyle(
                            color: _kind == k ? Colors.white : Brand.navy,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        _field(_title, tr('launch_title_field')),
        const SizedBox(height: 12),
        Row(children: [
          for (final p in const ['sale', 'rent'])
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _purpose = p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _purpose == p ? Brand.navy : Brand.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _purpose == p ? Brand.navy : Brand.line),
                    ),
                    child: Text(p == 'sale' ? tr('for_sale') : tr('for_rent'),
                        style: TextStyle(
                            color: _purpose == p ? Colors.white : Brand.navy,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _type,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('property_type')),
          items: _types
              .map((t) => DropdownMenuItem(value: t, child: Text(typeLabel(t))))
              .toList(),
          onChanged: (v) => setState(() => _type = v),
        ),
        const SizedBox(height: 12),
        _field(_area, tr('filter_area')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _field(_beds, tr('lst_beds'),
                  keyboard: TextInputType.number)),
          const SizedBox(width: 10),
          Expanded(
              child: _field(_budget, tr('client_budget'),
                  keyboard: TextInputType.number)),
        ]),
        const SizedBox(height: 12),
        _field(_desc, tr('launch_desc'), maxLines: 3),
        const SizedBox(height: 12),
        _field(_phone, tr('client_phone'), keyboard: TextInputType.phone),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(tr('launch_publish')),
          ),
        ),
      ]),
    );
  }

  Widget _field(TextEditingController c, String label,
          {int maxLines = 1, TextInputType? keyboard}) =>
      TextField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label),
      );
}
