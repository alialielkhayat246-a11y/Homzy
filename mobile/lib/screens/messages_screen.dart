import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/message_service.dart';
import '../theme.dart';
import 'message_thread_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  late Future<List<Conversation>> _future;

  @override
  void initState() {
    super.initState();
    _future = MessageService.instance.conversations();
  }

  void _refresh() =>
      setState(() => _future = MessageService.instance.conversations());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('messages_title'))),
      body: FutureBuilder<List<Conversation>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final convos = snap.data!;
          if (convos.isEmpty) {
            return Center(
              child: Text(tr('no_messages'),
                  style: const TextStyle(color: Brand.muted)),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: convos.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Brand.line, indent: 76),
              itemBuilder: (_, i) {
                final c = convos[i];
                final name = c.otherName ?? c.listingTitle ?? '—';
                return ListTile(
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: Brand.navy,
                    backgroundImage: c.otherAvatar != null
                        ? NetworkImage(c.otherAvatar!)
                        : null,
                    child: c.otherAvatar == null
                        ? Text(
                            name.isNotEmpty ? name.substring(0, 1) : '?',
                            style: const TextStyle(color: Colors.white))
                        : null,
                  ),
                  title: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(c.lastMessage ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: c.lastAt != null
                      ? Text(_time(c.lastAt!),
                          style: const TextStyle(
                              color: Brand.muted, fontSize: 11))
                      : null,
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MessageThreadScreen(
                            conversationId: c.id, title: name)));
                    _refresh();
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _time(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${t.day}/${t.month}';
  }
}
