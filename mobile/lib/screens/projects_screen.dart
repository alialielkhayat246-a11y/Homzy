import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/catalog_service.dart';
import '../theme.dart';
import 'project_detail_screen.dart';

const _unitTypes = [
  'apartment', 'studio', 'duplex', 'penthouse',
  'villa', 'townhouse', 'twinhouse', 'chalet', 'hotel apartment',
];

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  String _search = '';
  String? _area;
  String? _type;
  List<String> _areas = [];

  late Future<List<Project>> _future;

  @override
  void initState() {
    super.initState();
    _future = CatalogService.instance.projects();
    CatalogService.instance.areas().then((a) {
      if (mounted) setState(() => _areas = a);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _load() {
    setState(() {
      _future = CatalogService.instance.projects(
        search: _search,
        area: _area,
        unitType: _type,
      );
    });
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search = v;
      _load();
    });
  }

  void _clear() {
    _searchCtrl.clear();
    setState(() {
      _search = '';
      _area = null;
      _type = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final hasFilters = _search.isNotEmpty || _area != null || _type != null;
    return Scaffold(
      appBar: AppBar(title: Text(tr('projects_title'))),
      body: Column(
        children: [
          // search + filters
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearch,
                  decoration: InputDecoration(
                    hintText: tr('search_projects'),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Brand.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Brand.line),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _FilterDropdown(
                        label: tr('filter_area'),
                        value: _area,
                        items: _areas,
                        display: (v) => v,
                        onChanged: (v) {
                          setState(() => _area = v);
                          _load();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FilterDropdown(
                        label: tr('filter_type'),
                        value: _type,
                        items: _unitTypes,
                        display: (v) => tr('type_$v'),
                        onChanged: (v) {
                          setState(() => _type = v);
                          _load();
                        },
                      ),
                    ),
                    if (hasFilters)
                      IconButton(
                        tooltip: tr('clear_filters'),
                        icon: const Icon(Icons.filter_alt_off,
                            color: Brand.muted),
                        onPressed: _clear,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Project>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data ?? [];
                if (items.isEmpty) {
                  return ListView(children: [
                    const SizedBox(height: 100),
                    const Icon(Icons.search_off, size: 56, color: Brand.muted),
                    const SizedBox(height: 12),
                    Center(
                        child: Text(tr('no_projects'),
                            style: const TextStyle(color: Brand.muted))),
                  ]);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
                      child: Text('${items.length} ${tr('results_count')}',
                          style: const TextStyle(
                              color: Brand.muted, fontSize: 12)),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) =>
                            _ProjectCard(project: items[i]),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> items;
  final String Function(String) display;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: value != null ? Brand.blue : Brand.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          isDense: true,
          value: value,
          hint: Text(label,
              style: const TextStyle(fontSize: 13, color: Brand.muted)),
          icon: const Icon(Icons.keyboard_arrow_down, size: 18),
          items: [
            DropdownMenuItem<String?>(
                value: null, child: Text(tr('filter_all'))),
            ...items.map((e) => DropdownMenuItem<String?>(
                value: e,
                child: Text(display(e),
                    maxLines: 1, overflow: TextOverflow.ellipsis))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ProjectDetailScreen(projectId: project.id))),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Brand.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 8,
                child: project.coverImageUrl != null
                    ? Image.network(project.coverImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const _CoverFallback())
                    : const _CoverFallback(),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 3),
                    Text(
                      [project.developerName, project.area]
                          .where((e) => e != null && e.isNotEmpty)
                          .join(' · '),
                      style: const TextStyle(color: Brand.muted, fontSize: 13),
                    ),
                    if (project.status != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: Brand.blueLight,
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(project.status!,
                            style: const TextStyle(
                                color: Color(0xFF0B4FAE),
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Brand.navy,
      child: const Center(
        child: Icon(Icons.apartment, color: Colors.white24, size: 48),
      ),
    );
  }
}
