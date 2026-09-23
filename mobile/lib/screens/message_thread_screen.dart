import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/message_service.dart';
import '../theme.dart';
import '../widgets/report_dialog.dart';

class MessageThreadScreen extends StatefulWidget {
  const MessageThreadScreen(
      {super.key,
      required this.conversationId,
      required this.title,
      this.otherUserId});
  final String conversationId;
  final String title;
  final String? otherUserId;

  @override
  State<MessageThreadScreen> createState() => _MessageThreadScreenState();
}

class _MessageThreadScreenState extends State<MessageThreadScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _working = false;
  MessageSafety? _safety;
  String? _safetyError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    List<ChatMessage> m = [];
    MessageSafety? safety;
    String? safetyError;
    try {
      m = await MessageService.instance.messages(widget.conversationId);
      safety = await MessageService.instance.safety(widget.conversationId);
    } catch (_) {
      safetyError = tr('safety_load_failed');
    }
    if (!mounted) return;
    setState(() {
      _messages = m;
      _safety = safety;
      _safetyError = safetyError;
      _loading = false;
    });
    _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _safety?.canSend != true) return;
    _input.clear();
    try {
      await MessageService.instance.send(widget.conversationId, text);
      await _load();
    } catch (_) {
      if (!mounted) return;
      _input.text = text;
      _notice(tr('message_send_blocked'));
      await _load();
    }
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _toggleBlock() async {
    final safety = _safety;
    final otherId = safety?.otherUserId ?? widget.otherUserId;
    if (otherId == null || _working) return;
    if (safety?.blockedByMe == true) {
      setState(() => _working = true);
      try {
        await MessageService.instance.unblockUser(otherId);
        _notice(tr('user_unblocked'));
        await _load();
      } finally {
        if (mounted) setState(() => _working = false);
      }
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('block_user')),
        content: Text(tr('block_user_confirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('block'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      await MessageService.instance.blockUser(otherId);
      _notice(tr('user_blocked'));
      await _load();
    } catch (_) {
      _notice(tr('action_failed'));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _report({ChatMessage? message}) async {
    if (message?.mine == true || _working) return;
    final draft = await showReportDialog(context);
    if (draft == null || !mounted) return;
    setState(() => _working = true);
    try {
      if (message != null) {
        await MessageService.instance.reportMessage(
          messageId: message.id,
          reason: draft.reason,
          details: draft.details,
        );
      } else {
        await MessageService.instance.reportUser(
          conversationId: widget.conversationId,
          reason: draft.reason,
          details: draft.details,
        );
      }
      _notice(tr('report_sent'));
    } catch (_) {
      _notice(tr('action_failed'));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          PopupMenuButton<String>(
            enabled: !_working && _safety != null,
            onSelected: (value) {
              if (value == 'report') _report();
              if (value == 'block') _toggleBlock();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'report',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(tr('report_user')),
                ),
              ),
              PopupMenuItem(
                value: 'block',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_safety?.blockedByMe == true
                      ? Icons.lock_open_outlined
                      : Icons.block_outlined),
                  title: Text(_safety?.blockedByMe == true
                      ? tr('unblock_user')
                      : tr('block_user')),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_safetyError != null)
            _SafetyBanner(text: _safetyError!, warning: true)
          else if (_safety?.blockedByMe == true)
            _SafetyBanner(text: tr('blocked_by_you'))
          else if (_safety?.blockedMe == true)
            _SafetyBanner(text: tr('messaging_unavailable')),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _bubble(_messages[i]),
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              color: Brand.card,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: _safety?.canSend == true && !_working,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(hintText: tr('message_hint')),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Brand.navy,
                    child: IconButton(
                      icon:
                          const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed:
                          _safety?.canSend == true && !_working ? _send : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(ChatMessage m) {
    final bubble = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: m.mine ? Brand.navy : Brand.card,
        borderRadius: BorderRadius.circular(14),
        border: m.mine ? null : Border.all(color: Brand.line),
      ),
      child: Text(m.body,
          style: TextStyle(
              color: m.mine ? Colors.white : Brand.navy, height: 1.4)),
    );
    return Align(
      alignment: m.mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: m.mine
          ? bubble
          : GestureDetector(
              onLongPress: () => _report(message: m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bubble,
                  TextButton.icon(
                    onPressed: _working ? null : () => _report(message: m),
                    icon: const Icon(Icons.flag_outlined, size: 15),
                    label: Text(tr('report_message')),
                    style: TextButton.styleFrom(
                        foregroundColor: Brand.muted,
                        visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SafetyBanner extends StatelessWidget {
  const _SafetyBanner({required this.text, this.warning = false});
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: warning ? Colors.amber.shade100 : Brand.cream,
        child: Text(text, textAlign: TextAlign.center),
      );
}
