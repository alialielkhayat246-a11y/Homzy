import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../i18n.dart';
import '../services/stays_service.dart';
import '../theme.dart';

String _st(String en, String ar) => Lang.instance.isAr ? ar : en;

class StaysScreen extends StatefulWidget {
  const StaysScreen({super.key});
  @override
  State<StaysScreen> createState() => _StaysScreenState();
}

class _StaysScreenState extends State<StaysScreen>
    with SingleTickerProviderStateMixin {
  late final TabController tabs;
  late Future<List<Map<String, dynamic>>> stays;
  late Future<List<Map<String, dynamic>>> bookings;
  late Future<List<dynamic>> hosting;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 3, vsync: this);
    refresh();
  }

  void refresh() {
    stays = StaysService.instance.browse();
    bookings = StaysService.instance.bookings();
    hosting = Future.wait<dynamic>([
      StaysService.instance.ensureHost(),
      StaysService.instance.hostProperties(),
      StaysService.instance.verifications(),
    ]);
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Homzy Stays'),
          bottom: TabBar(controller: tabs, tabs: [
            Tab(text: _st('Explore', 'استكشف')),
            Tab(text: _st('My bookings', 'حجوزاتي')),
            Tab(text: _st('Hosting', 'الاستضافة')),
          ]),
        ),
        body: TabBarView(controller: tabs, children: [
          _future(stays, stayCard,
              _st('No stays available yet.', 'لا توجد إقامات متاحة بعد.')),
          _future(bookings, bookingCard,
              _st('No bookings yet.', 'لا توجد حجوزات بعد.')),
          _hosting(),
        ]),
      );

  Widget _hosting() => FutureBuilder<List<dynamic>>(
        future: hosting,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_st('Could not load hosting.', 'تعذّر تحميل الاستضافة.')),
              TextButton(
                  onPressed: () => setState(refresh),
                  child: Text(_st('Retry', 'إعادة المحاولة'))),
            ]));
          }
          final host = Map<String, dynamic>.from(snapshot.data![0] as Map);
          final properties =
              (snapshot.data![1] as List).cast<Map<String, dynamic>>();
          final docs = (snapshot.data![2] as List).cast<Map<String, dynamic>>();
          return RefreshIndicator(
            onRefresh: () async => setState(refresh),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                color: Brand.navy,
                child: ListTile(
                  leading: const Icon(Icons.verified_user_outlined,
                      color: Colors.white),
                  title: Text(_st('Host verification', 'توثيق المضيف'),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800)),
                  subtitle: Text('${host['verification_status'] ?? 'pending'}',
                      style: const TextStyle(color: Colors.white70)),
                  trailing:
                      const Icon(Icons.chevron_right, color: Colors.white),
                  onTap: () => _verification(host, docs),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: Text(_st('My properties', 'وحداتي'),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800))),
                FilledButton.icon(
                  onPressed: _addProperty,
                  icon: const Icon(Icons.add_home_work_outlined),
                  label: Text(_st('Add unit', 'أضف وحدة')),
                ),
              ]),
              const SizedBox(height: 8),
              if (properties.isEmpty)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Center(
                        child: Text(
                            _st('No properties yet.', 'لا توجد وحدات بعد.')))),
              ...properties.map((property) {
                final pricing = property['stay_pricing'] is List &&
                        (property['stay_pricing'] as List).isNotEmpty
                    ? Map<String, dynamic>.from(
                        (property['stay_pricing'] as List).first as Map)
                    : const <String, dynamic>{};
                return Card(
                    child: ListTile(
                  leading:
                      const CircleAvatar(child: Icon(Icons.home_work_outlined)),
                  title: Text('${property['title'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${property['city'] ?? property['area'] ?? ''} · ${pricing['base_price'] ?? 0} EGP'),
                  trailing:
                      Chip(label: Text('${property['status'] ?? 'draft'}')),
                ));
              }),
            ]),
          );
        },
      );

  Future<void> _verification(
      Map<String, dynamic> host, List<Map<String, dynamic>> docs) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_st('Host verification', 'توثيق المضيف'),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                  _st('Upload your national ID. Documents are private and reviewed only by Homzy.',
                      'ارفع صورة بطاقتك. المستندات سرية ولا يراجعها إلا فريق Homzy.'),
                  style: const TextStyle(color: Brand.muted)),
              const SizedBox(height: 12),
              Text(
                  '${_st('Status', 'الحالة')}: ${host['verification_status'] ?? 'pending'}'),
              ...docs.map((doc) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_outlined),
                    title: Text('${doc['doc_type']}'),
                    trailing: Text('${doc['status'] ?? 'pending'}'),
                  )),
              FilledButton.icon(
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(_st('Upload ID document', 'رفع مستند الهوية')),
                onPressed: () async {
                  final file = await ImagePicker()
                      .pickImage(source: ImageSource.gallery, imageQuality: 90);
                  if (file == null) return;
                  try {
                    await StaysService.instance.uploadVerification(
                        await file.readAsBytes(), file.name, 'national_id');
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    if (mounted) setState(refresh);
                  } catch (e) {
                    if (sheetContext.mounted) {
                      ScaffoldMessenger.of(sheetContext)
                          .showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
              ),
            ]),
      ),
    );
  }

  Future<void> _addProperty() async {
    final title = TextEditingController();
    final description = TextEditingController();
    final city = TextEditingController();
    final area = TextEditingController();
    final guests = TextEditingController(text: '2');
    final bedrooms = TextEditingController(text: '1');
    final price = TextEditingController();
    var type = 'apartment';
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
                title: Text(_st('Add stay unit', 'إضافة وحدة إقامة')),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: title,
                      decoration: InputDecoration(
                          labelText: _st('Title', 'عنوان الوحدة'))),
                  TextField(
                      controller: description,
                      maxLines: 3,
                      decoration: InputDecoration(
                          labelText: _st('Description', 'الوصف'))),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration:
                        InputDecoration(labelText: _st('Type', 'النوع')),
                    items: const [
                      'apartment',
                      'studio',
                      'villa',
                      'chalet',
                      'hotel_room',
                      'serviced_apartment',
                      'entire_home',
                      'private_room'
                    ]
                        .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.replaceAll('_', ' '))))
                        .toList(),
                    onChanged: (value) =>
                        update(() => type = value ?? 'apartment'),
                  ),
                  TextField(
                      controller: city,
                      decoration:
                          InputDecoration(labelText: _st('City', 'المدينة'))),
                  TextField(
                      controller: area,
                      decoration:
                          InputDecoration(labelText: _st('Area', 'المنطقة'))),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: guests,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                                labelText: _st('Guests', 'الضيوف')))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: bedrooms,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                                labelText: _st('Bedrooms', 'غرف النوم')))),
                  ]),
                  TextField(
                      controller: price,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText:
                              _st('Nightly price (EGP)', 'سعر الليلة (ج.م)'))),
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(tr('cancel'))),
                  FilledButton(
                      onPressed: saving
                          ? null
                          : () async {
                              if (title.text.trim().length < 3 ||
                                  price.text.trim().isEmpty) {
                                return;
                              }
                              update(() => saving = true);
                              try {
                                await StaysService.instance.createProperty({
                                  'title': title.text.trim(),
                                  'description': description.text.trim(),
                                  'type_slug': type,
                                  'city': city.text.trim(),
                                  'area': area.text.trim(),
                                  'governorate': city.text.trim(),
                                  'max_guests': int.tryParse(guests.text) ?? 2,
                                  'bedrooms': int.tryParse(bedrooms.text) ?? 1,
                                  'beds': int.tryParse(bedrooms.text) ?? 1,
                                  'bathrooms': 1,
                                },
                                    basePrice: num.tryParse(
                                            price.text.replaceAll(',', '')) ??
                                        0);
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                                if (mounted) {
                                  setState(refresh);
                                }
                              } catch (e) {
                                update(() => saving = false);
                                if (dialogContext.mounted) {
                                  ScaffoldMessenger.of(dialogContext)
                                      .showSnackBar(
                                          SnackBar(content: Text('$e')));
                                }
                              }
                            },
                      child: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(tr('save'))),
                ],
              )),
    );
    for (final controller in [
      title,
      description,
      city,
      area,
      guests,
      bedrooms,
      price
    ]) {
      controller.dispose();
    }
  }

  Widget _future(
    Future<List<Map<String, dynamic>>> future,
    Widget Function(Map<String, dynamic>) builder,
    String empty,
  ) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child:
                    Text(_st('Could not load data.', 'تعذّر تحميل البيانات.')));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) return Center(child: Text(empty));
          return RefreshIndicator(
            onRefresh: () async => setState(refresh),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: snapshot.data!.length,
              itemBuilder: (_, index) => builder(snapshot.data![index]),
            ),
          );
        },
      );

  Widget stayCard(Map<String, dynamic> stay) {
    final cover = stay['cover']?.toString();
    final price = num.tryParse('${stay['base_price'] ?? ''}');
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${stay['title'] ?? ''}',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                      '${stay['type_en'] ?? ''} · ${stay['area'] ?? stay['city'] ?? ''}'),
                  const SizedBox(height: 8),
                  Text(_st(
                    '${stay['max_guests'] ?? 0} guests · ${stay['bedrooms'] ?? 0} bedrooms',
                    '${stay['max_guests'] ?? 0} ضيوف · ${stay['bedrooms'] ?? 0} غرف',
                  )),
                ]),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (cover != null && cover.isNotEmpty)
            Image.network(cover,
                height: 190,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder())
          else
            _placeholder(),
          Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${stay['title'] ?? ''}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${stay['area'] ?? stay['city'] ?? ''}',
                  style: const TextStyle(color: Brand.muted)),
              const SizedBox(height: 8),
              Text(
                price == null
                    ? ''
                    : '${price.toStringAsFixed(0)} ${stay['currency'] ?? 'EGP'} / ${_st('night', 'ليلة')}',
                style: const TextStyle(
                    color: Brand.navy, fontWeight: FontWeight.w800),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _placeholder() => Container(
        height: 160,
        color: Brand.line,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported_outlined,
            color: Brand.muted, size: 38),
      );

  Widget bookingCard(Map<String, dynamic> booking) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: const Icon(Icons.calendar_month_outlined),
          title: Text(_st(
            '${booking['check_in']} → ${booking['check_out']}',
            '${booking['check_in']} ← ${booking['check_out']}',
          )),
          subtitle: Text('${booking['status'] ?? ''}'),
          trailing: Text(
              '${booking['total_amount'] ?? ''} ${booking['currency'] ?? 'EGP'}'),
        ),
      );
}
