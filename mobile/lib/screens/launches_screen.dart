import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n.dart';
import '../services/launch_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';

class LaunchesScreen extends StatefulWidget {
  const LaunchesScreen({super.key});

  @override
  State<LaunchesScreen> createState() => _LaunchesScreenState();
}

class _LaunchesScreenState extends State<LaunchesScreen> {
  late Future<List<Launch>> _future;

  @override
  void initState() {
    super.initState();
    _future = LaunchService.instance.list();
  }

  void _refresh() =>
      setState(() => _future = LaunchService.instance.list());

  Future<void> _add() async {
    final done = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const AddLaunchScreen()));
    if (done == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('launches_title'))),
      floatingActionButton: ProfileService.instance.isBroker
          ? FloatingActionButton.extended(
              backgroundColor: Brand.navy,
              foregroundColor: Colors.white,
              onPressed: _add,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(tr('add_launch'),
                  style: const TextStyle(color: Colors.white)),
            )
          : null,
      body: FutureBuilder<List<Launch>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return Center(
                child: Text(tr('no_launches'),
                    style: const TextStyle(color: Brand.muted)));
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _LaunchCard(launch: items[i]),
            ),
          );
        },
      ),
    );
  }
}

class _LaunchCard extends StatelessWidget {
  const _LaunchCard({required this.launch});
  final Launch launch;

  @override
  Widget build(BuildContext context) {
    final sub = [launch.developer, launch.project, launch.area]
        .where((e) => e != null && e.isNotEmpty)
        .join(' · ');
    return Container(
      decoration: BoxDecoration(
        color: Brand.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (launch.imageUrl != null)
            AspectRatio(
              aspectRatio: 16 / 8,
              child: Image.network(launch.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Container(color: Brand.cream)),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: launch.isOffer
                            ? Brand.coralLight
                            : Brand.cream,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(
                        launch.isOffer ? tr('kind_offer') : tr('kind_launch'),
                        style: TextStyle(
                            color: launch.isOffer ? Brand.coral : Brand.navy,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(launch.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(sub,
                      style: const TextStyle(
                          color: Brand.muted, fontSize: 12.5)),
                ],
                if (launch.description != null &&
                    launch.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(launch.description!,
                      style: const TextStyle(height: 1.5, fontSize: 13.5)),
                ],
                if (launch.link != null && launch.link!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final u = Uri.tryParse(launch.link!);
                      if (u != null) {
                        await launchUrl(u,
                            mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(tr('view_details')),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Brand.navy,
                        side: const BorderSide(color: Brand.line)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AddLaunchScreen extends StatefulWidget {
  const AddLaunchScreen({super.key});

  @override
  State<AddLaunchScreen> createState() => _AddLaunchScreenState();
}

class _AddLaunchScreenState extends State<AddLaunchScreen> {
  final _title = TextEditingController();
  final _developer = TextEditingController();
  final _project = TextEditingController();
  final _area = TextEditingController();
  final _desc = TextEditingController();
  final _link = TextEditingController();
  String _kind = 'launch';
  (Uint8List, String)? _image;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_title, _developer, _project, _area, _desc, _link]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1400, imageQuality: 80);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    final ext = x.name.split('.').last.toLowerCase();
    setState(() => _image = (bytes, ext == 'png' ? 'png' : 'jpeg'));
  }

  Future<void> _publish() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('title_required'))));
      return;
    }
    setState(() => _saving = true);
    try {
      String? img;
      if (_image != null) {
        img = await LaunchService.instance
            .uploadImage(_image!.$1, _image!.$2);
      }
      await LaunchService.instance.create(
        kind: _kind,
        title: _title.text.trim(),
        developer: _t(_developer),
        project: _t(_project),
        area: _t(_area),
        description: _t(_desc),
        imageUrl: img,
        link: _t(_link),
      );
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

  String? _t(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('add_launch'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(children: [
            for (final k in const ['launch', 'offer'])
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
                      child: Text(
                          k == 'offer' ? tr('kind_offer') : tr('kind_launch'),
                          style: TextStyle(
                              color: _kind == k ? Colors.white : Brand.navy,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _pick,
            child: Container(
              height: 130,
              decoration: BoxDecoration(
                  color: Brand.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Brand.line)),
              clipBehavior: Clip.antiAlias,
              child: _image != null
                  ? Image.memory(_image!.$1, fit: BoxFit.cover)
                  : const Center(
                      child: Icon(Icons.add_a_photo_outlined,
                          color: Brand.navy, size: 30)),
            ),
          ),
          const SizedBox(height: 14),
          _field(_title, tr('launch_title_field')),
          const SizedBox(height: 12),
          _field(_developer, tr('launch_developer')),
          const SizedBox(height: 12),
          _field(_project, tr('launch_project')),
          const SizedBox(height: 12),
          _field(_area, tr('filter_area')),
          const SizedBox(height: 12),
          _field(_desc, tr('launch_desc'), maxLines: 4),
          const SizedBox(height: 12),
          _field(_link, tr('launch_link'), keyboard: TextInputType.url),
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
                  : Text(tr('launch_publish')),
            ),
          ),
        ],
      ),
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
