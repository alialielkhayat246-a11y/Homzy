import 'package:flutter/material.dart';

import '../services/chat_store.dart';
import '../theme.dart';
import 'chat_screen.dart';

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  late Future<List<SavedConversation>> _future;

  @override
  void initState() {
    super.initState();
    _future = ChatStore.instance.list();
  }

  void _refresh() {
    setState(() => _future = ChatStore.instance.list());
  }

  Future<void> _open(SavedConversation c) async {
    final msgs = await ChatStore.instance.messages(c.id);
    if (!mounted) return;
    final full = SavedConversation(
      id: c.id,
      title: c.title,
      language: c.language,
      updatedAt: c.updatedAt,
      messages: msgs,
    );
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(restored: full)),
    );
    _refresh();
  }

  Future<void> _delete(SavedConversation c) async {
    await ChatStore.instance.delete(c.id);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved chats'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Brand.muted),
              onPressed: _refresh),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<SavedConversation>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                Icon(Icons.bookmark_border, size: 56, color: Brand.muted),
                SizedBox(height: 12),
                Center(
                  child: Text(
                    'No saved chats yet.\nTap the 🔖 in a chat to save it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Brand.muted),
                  ),
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final c = items[i];
                return Dismissible(
                  key: ValueKey(c.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                        color: Brand.red,
                        borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => _delete(c),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _open(c),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Brand.line),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                  color: Brand.blueLight,
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.chat_bubble_outline,
                                  color: Brand.blue, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textDirection: c.language == 'ar'
                                        ? TextDirection.rtl
                                        : TextDirection.ltr,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    _ago(c.updatedAt),
                                    style: const TextStyle(
                                        color: Brand.muted, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                color: Brand.muted),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}
