import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../i18n.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/house_logo.dart';
import 'search_results_screen.dart';

/// Home: greeting + natural-language search that opens the results screen,
/// plus recent searches. Matches the 2026 design (screen 2).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialHealth, this.onStartChat});
  final HealthInfo? initialHealth;
  final VoidCallback? onStartChat;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  List<String> _recent = [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _recent = p.getStringList('homzy_recent') ?? []);
  }

  Future<void> _run(String query) async {
    final q = query.trim();
    // Empty search browses all active listings; a term is saved as recent.
    if (q.isNotEmpty) {
      final p = await SharedPreferences.getInstance();
      final list = [q, ..._recent.where((e) => e != q)].take(6).toList();
      await p.setStringList('homzy_recent', list);
      if (mounted) setState(() => _recent = list);
    }
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SearchResultsScreen(query: q.isEmpty ? null : q)));
  }

  @override
  Widget build(BuildContext context) {
    final name = (AuthService.instance.displayName ?? '').split(' ').first;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                        color: Brand.navy,
                        borderRadius: BorderRadius.circular(12)),
                    child: const HouseLogo(
                        size: 22, outline: Colors.white, window: Brand.coral),
                  ),
                  const SizedBox(width: 10),
                  const Text('Homzy',
                      style: TextStyle(
                          color: Brand.navy,
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                ]),
                IconButton(
                  onPressed: widget.onStartChat,
                  icon: const Icon(Icons.smart_toy_outlined, color: Brand.navy),
                  tooltip: 'Homzy AI',
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('${tr('greeting_hi')}${name.isNotEmpty ? ' $name' : ''} 👋',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr('home_help_today'),
                style: const TextStyle(color: Brand.muted, fontSize: 15)),
            const SizedBox(height: 18),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Brand.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Brand.line)),
              child: Column(
                children: [
                  TextField(
                    controller: _search,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _run,
                    decoration: InputDecoration(
                      hintText: tr('search_nl_hint'),
                      prefixIcon: const Icon(Icons.auto_awesome,
                          color: Brand.coral, size: 20),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(tr('search_nl_example'),
                          style: const TextStyle(
                              color: Brand.muted, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_recent.isNotEmpty) ...[
              Text(tr('recent_searches'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 10),
              ..._recent.map((r) => _RecentTile(text: r, onTap: () => _run(r))),
              const SizedBox(height: 12),
            ],

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _run(_search.text),
                icon: const Icon(Icons.search, size: 20),
                label: Text('${tr('search_with_homzy')} ✨'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: Brand.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Brand.line)),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.history, color: Brand.muted, size: 20),
        title: Text(text, style: const TextStyle(fontSize: 14)),
        trailing: const Icon(Icons.north_west, color: Brand.muted, size: 16),
        onTap: onTap,
      ),
    );
  }
}
