import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../i18n.dart';
import '../services/listing_service.dart';
import '../theme.dart';
import '../widgets/listing_card.dart';

/// Common Egyptian areas the seller can pick from (value stored is Arabic to
/// match the catalog; English label shown in English mode).
const _areaOptions = <(String, String)>[
  ('التجمع الخامس', 'New Cairo'),
  ('العاصمة الإدارية', 'New Capital'),
  ('الشيخ زايد', 'Sheikh Zayed'),
  ('٦ أكتوبر', '6th of October'),
  ('زايد الجديدة', 'New Zayed'),
  ('حدائق أكتوبر', 'October Gardens'),
  ('مدينتي', 'Madinaty'),
  ('مستقبل سيتي', 'Mostakbal City'),
  ('الشروق', 'El Shorouk'),
  ('العبور', 'El Obour'),
  ('المعادي', 'Maadi'),
  ('الساحل الشمالي', 'North Coast'),
  ('رأس الحكمة', 'Ras El Hekma'),
  ('العلمين الجديدة', 'New Alamein'),
  ('العين السخنة', 'Ain Sokhna'),
  ('المنصورة الجديدة', 'New Mansoura'),
];

class AddListingScreen extends StatefulWidget {
  const AddListingScreen({super.key});

  @override
  State<AddListingScreen> createState() => _AddListingScreenState();
}

class _AddListingScreenState extends State<AddListingScreen> {
  final _title = TextEditingController();
  final _price = TextEditingController();
  String? _area;
  final _address = TextEditingController();
  final _beds = TextEditingController();
  final _baths = TextEditingController();
  final _size = TextEditingController();
  final _desc = TextEditingController();
  String _purpose = 'sale';
  String _type = 'apartment';
  final List<(Uint8List, String)> _photos = [];
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _title, _price, _address, _beds, _baths, _size, _desc
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final imgs = await ImagePicker()
        .pickMultiImage(maxWidth: 1400, imageQuality: 80);
    for (final x in imgs) {
      final bytes = await x.readAsBytes();
      final ext = x.name.split('.').last.toLowerCase();
      _photos.add((bytes, ext == 'png' ? 'png' : 'jpeg'));
    }
    if (mounted) setState(() {});
  }

  Future<void> _publish() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('title_required'))));
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await ListingService.instance.create(
        title: _title.text.trim(),
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        purpose: _purpose,
        type: _type,
        price: num.tryParse(_price.text.replaceAll(',', '').trim()),
        area: _area,
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        bedrooms: int.tryParse(_beds.text.trim()),
        bathrooms: int.tryParse(_baths.text.trim()),
        sizeSqm: num.tryParse(_size.text.trim()),
      );
      for (var i = 0; i < _photos.length; i++) {
        await ListingService.instance
            .addPhoto(id, _photos[i].$1, _photos[i].$2, sort: i);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('published_ok'))));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('add_property'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(tr('add_photos'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          SizedBox(
            height: 92,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                GestureDetector(
                  onTap: _pick,
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                        color: Brand.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Brand.line)),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_outlined, color: Brand.navy),
                        SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                for (final p in _photos)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(p.$1,
                          width: 92, height: 92, fit: BoxFit.cover),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(tr('basic_info'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _field(_title, tr('lst_title')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _purposeSeg()),
          ]),
          const SizedBox(height: 12),
          _dropdown(),
          const SizedBox(height: 12),
          _areaDropdown(),
          const SizedBox(height: 12),
          _field(_price, tr('enter_price'),
              keyboard: TextInputType.number),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _field(_beds, tr('lst_beds'),
                    keyboard: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(
                child: _field(_baths, tr('lst_baths'),
                    keyboard: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(
                child: _field(_size, tr('lst_size'),
                    keyboard: TextInputType.number)),
          ]),
          const SizedBox(height: 12),
          _field(_address, tr('lst_address')),
          const SizedBox(height: 12),
          _field(_desc, tr('lst_desc'), maxLines: 4),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _publish,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(tr('publish')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
          {TextInputType? keyboard, int maxLines = 1}) =>
      TextField(
        controller: c,
        keyboardType: keyboard,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      );

  Widget _purposeSeg() => Row(
        children: [
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
                            color:
                                _purpose == p ? Colors.white : Brand.navy,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
        ],
      );

  Widget _areaDropdown() => DropdownButtonFormField<String>(
        initialValue: _area,
        isExpanded: true,
        decoration: InputDecoration(labelText: tr('choose_area')),
        items: _areaOptions
            .map((a) => DropdownMenuItem(
                value: a.$1,
                child: Text(Lang.instance.isAr ? a.$1 : a.$2,
                    overflow: TextOverflow.ellipsis)))
            .toList(),
        onChanged: (v) => setState(() => _area = v),
      );

  Widget _dropdown() => DropdownButtonFormField<String>(
        initialValue: _type,
        decoration: InputDecoration(labelText: tr('property_type')),
        items: const [
          'apartment',
          'duplex',
          'villa',
          'studio',
          'chalet',
          'townhouse',
          'penthouse',
          'office',
        ]
            .map((t) =>
                DropdownMenuItem(value: t, child: Text(typeLabel(t))))
            .toList(),
        onChanged: (v) => setState(() => _type = v ?? 'apartment'),
      );
}
