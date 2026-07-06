import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/catalog_service.dart';
import '../services/valuation_service.dart';
import '../theme.dart';
import '../widgets/listing_card.dart' show egp, typeLabel;

const _types = [
  'apartment', 'studio', 'duplex', 'penthouse',
  'villa', 'townhouse', 'twinhouse', 'chalet',
];
const _finishes = <(String, String, String)>[
  ('fully finished', 'تشطيب كامل', 'Fully finished'),
  ('semi finished', 'نصف تشطيب', 'Semi finished'),
  ('core & shell', 'على المحارة', 'Core & shell'),
];

class ValuationScreen extends StatefulWidget {
  const ValuationScreen({super.key});

  @override
  State<ValuationScreen> createState() => _ValuationScreenState();
}

class _ValuationScreenState extends State<ValuationScreen> {
  final _size = TextEditingController();
  String? _area;
  String _type = 'apartment';
  String? _finishing;
  List<String> _areas = [];
  bool _loading = false;
  Estimate? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    CatalogService.instance.areas().then((a) {
      if (mounted) setState(() => _areas = a);
    });
  }

  @override
  void dispose() {
    _size.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final size = num.tryParse(_size.text.trim());
    if (size == null || size <= 0) {
      setState(() => _error = tr('val_need_size'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await ValuationService.instance.estimate(
        area: _area, type: _type, size: size, finishing: _finishing);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (r.ok) {
          _result = r;
        } else {
          _error = tr('val_not_enough');
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = Lang.instance.isAr;
    return Scaffold(
      appBar: AppBar(title: Text(tr('val_title'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(tr('val_sub'),
              style: const TextStyle(color: Brand.muted, height: 1.5)),
          const SizedBox(height: 18),
          _label(tr('filter_area')),
          DropdownButtonFormField<String>(
            initialValue: _area,
            isExpanded: true,
            decoration: const InputDecoration(),
            hint: Text(tr('choose_area')),
            items: _areas
                .map((a) => DropdownMenuItem(
                    value: a, child: Text(a, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => setState(() => _area = v),
          ),
          const SizedBox(height: 14),
          _label(tr('property_type')),
          DropdownButtonFormField<String>(
            initialValue: _type,
            isExpanded: true,
            decoration: const InputDecoration(),
            items: _types
                .map((t) =>
                    DropdownMenuItem(value: t, child: Text(typeLabel(t))))
                .toList(),
            onChanged: (v) => setState(() => _type = v ?? 'apartment'),
          ),
          const SizedBox(height: 14),
          _label('${tr('lst_size')} (م²)'),
          TextField(
            controller: _size,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '160'),
          ),
          const SizedBox(height: 14),
          _label(tr('finishing_label')),
          DropdownButtonFormField<String>(
            initialValue: _finishing,
            isExpanded: true,
            decoration: const InputDecoration(),
            hint: Text(tr('optional')),
            items: _finishes
                .map((f) => DropdownMenuItem(
                    value: f.$1, child: Text(ar ? f.$2 : f.$3)))
                .toList(),
            onChanged: (v) => setState(() => _finishing = v),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _run,
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(tr('val_cta')),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Brand.red)),
          ],
          if (_result != null) _resultCard(_result!),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13, color: Brand.navy)),
      );

  Widget _resultCard(Estimate r) {
    return Container(
      margin: const EdgeInsets.only(top: 22),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Brand.navy,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('val_estimate'),
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text(egp(r.estimate),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('${tr('val_range')}: ${egp(r.low)} — ${egp(r.high)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _pill('${egp(r.ppsqm)} / م²'),
            _pill('${r.nComps} ${tr('val_comps')}'),
          ]),
          const SizedBox(height: 8),
          Text(r.source == 'resale' ? tr('val_src_resale') : tr('val_src_catalog'),
              style: TextStyle(
                  color: r.source == 'resale' ? Brand.green : Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 12),
          Text(tr('val_based_on'),
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          ...r.comps.take(4).map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${c.name ?? ''} · ${c.size}م²',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12.5),
                      ),
                    ),
                    Text(egp(c.price),
                        style: const TextStyle(
                            color: Brand.coral,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              )),
          const SizedBox(height: 10),
          Text(tr('val_disclaimer'),
              style: const TextStyle(
                  color: Colors.white54, fontSize: 11, height: 1.4)),
        ],
      ),
    );
  }

  Widget _pill(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}
