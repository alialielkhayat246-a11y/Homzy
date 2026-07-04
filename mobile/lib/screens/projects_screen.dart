import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/catalog_service.dart';
import '../theme.dart';
import 'project_detail_screen.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late Future<List<Project>> _future;

  @override
  void initState() {
    super.initState();
    _future = CatalogService.instance.projects();
  }

  void _refresh() =>
      setState(() {
        _future = CatalogService.instance.projects();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('projects_title')),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Brand.muted),
              onPressed: _refresh),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<Project>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 120),
                const Icon(Icons.apartment_outlined,
                    size: 56, color: Brand.muted),
                const SizedBox(height: 12),
                Center(
                    child: Text(tr('no_projects'),
                        style: const TextStyle(color: Brand.muted))),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _ProjectCard(project: items[i]),
            );
          },
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
