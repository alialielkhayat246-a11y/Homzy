import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../i18n.dart';
import '../services/auth_service.dart';
import '../services/chat_store.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import '../widgets/house_logo.dart';

/// Detects Arabic so we can render RTL + Cairo, matching the web UI.
bool _isArabic(String t) => RegExp(r'[؀-ۿ]').hasMatch(t);

class _Msg {
  _Msg(this.text, this.fromUser, {this.typing = false, this.rec});
  final String text;
  final bool fromUser;
  final bool typing;

  /// A unit the broker recommended this turn — rendered as a card (photos +
  /// brochure) below the bubble.
  final Listing? rec;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.restored});

  /// When opened from "Saved chats", the conversation to preload.
  final SavedConversation? restored;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messages = <_Msg>[];
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _sessionId =
      'sess-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';

  HealthInfo? _health;
  bool _sending = false;
  bool _greeted = false;
  bool _saving = false;
  String? _conversationId; // set after first save (or when restored)
  bool _dirty = false; // unsaved changes since last save

  static const _chips = <(String, String)>[
    ('🏠  I want to rent', "I'm looking to rent"),
    ('🔑  I want to buy', "I'm looking to buy"),
    ('📍  Sheikh Zayed', 'Show me options in Sheikh Zayed'),
    ('🏙️  6th of October', 'Show me options in 6th of October'),
  ];

  @override
  void initState() {
    super.initState();
    final r = widget.restored;
    if (r != null) {
      _conversationId = r.id;
      _greeted = true;
      for (final m in r.messages) {
        _messages.add(_Msg(m.content, m.role == 'user'));
      }
    }
    _init();
  }

  Future<void> _init() async {
    final h = await HomzyApi.instance.health();
    if (!mounted) return;
    setState(() {
      _health = h;
      if (!_greeted) {
        _greeted = true;
        final broker = h?.broker ?? 'Homzy';
        final isBroker = ProfileService.instance.isBroker;
        _messages.add(_Msg(
          isBroker
              ? "أهلاً $broker 👋 قوللي طلب عميلك بالتفصيل — إيجار ولا تمليك، "
                  "الميزانية، المنطقة، عدد الغرف، ومحتاج يستلم دلوقتي ولا عادي "
                  "بعد سنتين-تلاتة — وأنا أطلعلك أنسب وحدة تعرضها عليه مع البروشور والصور."
              : "أهلاً! أنا $broker، مستشارك العقاري 👋 عشان أرشّحلك أنسب وحدة، "
                  "هسألك كام سؤال سريع: بتدوّر على إيجار ولا تمليك؟ ميزانيتك تقريبًا؟ "
                  "أنهي منطقة؟ كام غرفة؟ ومحتاج تستلم دلوقتي ولا عادي بعد سنتين-تلاتة؟",
          false,
        ));
      }
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _sending) return;
    _controller.clear();
    // conversation so far (so the AI remembers) — before adding this message
    final history = _messages
        .where((m) => !m.typing)
        .map((m) => {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text})
        .toList();
    setState(() {
      _sending = true;
      _messages.add(_Msg(text, true));
      _messages.add(_Msg('', false, typing: true));
    });
    _scrollToEnd();

    try {
      final reply = await HomzyApi.instance
          .chat(sessionId: _sessionId, message: text, history: history);
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m.typing);
        _messages.add(_Msg(reply.reply, false, rec: reply.recommendation));
        _dirty = true;
      });
      // keep saved chats up to date automatically (only if signed in)
      if (AuthService.instance.isLoggedIn) _autoSave();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m.typing);
        _messages.add(_Msg(e.message, false));
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  List<ChatMsg> _turns() => _messages
      .where((m) => !m.typing)
      .map((m) => ChatMsg(m.fromUser ? 'user' : 'assistant', m.text))
      .toList();

  Future<String?> _persist() async {
    final turns = _turns();
    if (turns.length <= 1) return null;
    final firstUser = _messages.firstWhere((m) => m.fromUser && !m.typing,
        orElse: () => _Msg('Chat', true));
    final title = firstUser.text.length > 40
        ? '${firstUser.text.substring(0, 40)}…'
        : firstUser.text;
    final lang = _isArabic(firstUser.text) ? 'ar' : 'en';
    return ChatStore.instance.save(
      id: _conversationId,
      title: title.isEmpty ? 'Chat' : title,
      language: lang,
      messages: turns,
    );
  }

  /// Silent auto-save after each exchange (keeps saved chats up to date).
  Future<void> _autoSave() async {
    try {
      final id = await _persist();
      if (id != null && mounted) {
        setState(() {
          _conversationId = id;
          _dirty = false;
        });
      }
    } catch (_) {/* best effort */}
  }

  Future<void> _saveChat() async {
    if (!AuthService.instance.isLoggedIn) {
      _toast(tr('sign_in_to_save'));
      return;
    }
    if (_turns().length <= 1) {
      _toast(tr('nothing_to_save'));
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await _persist();
      if (!mounted) return;
      setState(() {
        if (id != null) _conversationId = id;
        _dirty = false;
      });
      _toast(tr('saved_ok'));
    } catch (e) {
      _toast('Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _editServer() async {
    final field = TextEditingController(text: HomzyApi.instance.baseUrl);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('API server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Base URL of the Homzy backend. Use 10.0.2.2 for the Android '
              'emulator, or your PC\'s LAN IP for a real device.',
              style: TextStyle(fontSize: 12, color: Brand.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: field,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'http://10.0.2.2:8000',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      await HomzyApi.instance.setBaseUrl(field.text);
      await _init();
    }
  }

  @override
  Widget build(BuildContext context) {
    final showChips = _messages.length <= 1;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            const BrokerAvatar(size: 34),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_health?.broker ?? 'Homzy',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                Text(
                  _health == null
                      ? 'connecting…'
                      : (_health!.isAi ? 'AI' : 'Preview mode'),
                  style: TextStyle(
                      fontSize: 11,
                      color: _health?.isAi == true
                          ? Brand.green
                          : Brand.muted),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: tr('save_chat'),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(
                    _dirty ? Icons.bookmark_add : Icons.bookmark_added,
                    color: _dirty ? Brand.blue : Brand.green,
                  ),
            onPressed: _saving ? null : _saveChat,
          ),
          IconButton(
            tooltip: tr('server_settings'),
            icon: const Icon(Icons.tune, color: Brand.muted),
            onPressed: _editServer,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
              itemCount: _messages.length + (showChips ? 1 : 0),
              itemBuilder: (context, i) {
                if (showChips && i == _messages.length) {
                  return _ChipsRow(
                      chips: _chips,
                      onTap: _sending ? null : (p) => _send(p));
                }
                return _Bubble(msg: _messages[i]);
              },
            ),
          ),
          _Composer(
            controller: _controller,
            enabled: !_sending,
            onSend: () => _send(_controller.text),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg});
  final _Msg msg;

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: msg.text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(Lang.instance.isAr ? 'اتنسخ ✓' : 'Copied ✓'),
      duration: const Duration(seconds: 1),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (msg.typing) return const _TypingBubble();
    final rtl = _isArabic(msg.text);
    final align = msg.fromUser ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor = msg.fromUser ? Brand.blue : Colors.white;
    final textColor = msg.fromUser ? Colors.white : Brand.navy;

    final bubble = Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78),
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(msg.fromUser ? 18 : 6),
          bottomRight: Radius.circular(msg.fromUser ? 6 : 18),
        ),
        border: msg.fromUser ? null : Border.all(color: Brand.line),
      ),
      child: Text(
        msg.text,
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        style: (rtl ? Brand.arabic() : const TextStyle()).copyWith(
            color: textColor, fontSize: 15, height: 1.5),
      ),
    );

    final tappable = GestureDetector(
      onLongPress: () => _copy(context),
      child: bubble,
    );

    if (msg.fromUser) {
      return Align(alignment: align, child: tappable);
    }
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 8, bottom: 6),
          child: BrokerAvatar(size: 30),
        ),
        Flexible(child: tappable),
      ],
    );
    if (msg.rec == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        Padding(
          padding: const EdgeInsets.only(left: 38, top: 2, bottom: 4),
          child: _RecCard(rec: msg.rec!),
        ),
      ],
    );
  }
}

/// The recommended unit — photos + key facts + a brochure button — shown under
/// the broker's message so the client gets everything in one place.
class _RecCard extends StatelessWidget {
  const _RecCard({required this.rec});
  final Listing rec;

  Future<void> _openBrochure(String url) async {
    final viewer =
        'https://docs.google.com/viewer?embedded=true&url=${Uri.encodeComponent(url)}';
    try {
      await launchUrl(Uri.parse(viewer), mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
    }
  }

  void _viewImage(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Center(child: Image.network(url)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ar = Lang.instance.isAr;
    final name = ar && rec.compoundAr.isNotEmpty ? rec.compoundAr : rec.compound;
    final area = ar && rec.areaAr.isNotEmpty ? rec.areaAr : rec.area;
    final price = ar ? rec.priceAr : rec.priceEn;
    final imgs = rec.images.isNotEmpty
        ? rec.images
        : (rec.cover != null ? [rec.cover!] : const <String>[]);

    return Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imgs.isNotEmpty)
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: imgs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 2),
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () => _viewImage(context, imgs[i]),
                  child: Image.network(
                    imgs[i],
                    width: imgs.length == 1
                        ? MediaQuery.of(context).size.width * 0.82
                        : 200,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(width: 200, color: Brand.cream),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  [if (rec.developer != null) rec.developer!, area]
                      .where((e) => e.isNotEmpty)
                      .join(' · '),
                  style: const TextStyle(color: Brand.muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(price,
                    style: const TextStyle(
                        color: Brand.coral,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (rec.downPayment != null)
                    _chip(Icons.payments_outlined,
                        '${ar ? 'مقدم' : 'Down'} ${rec.downPayment}'),
                  if (rec.delivery != null)
                    _chip(Icons.event_outlined, rec.delivery!),
                ]),
                if (rec.brochureUrl != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _openBrochure(rec.brochureUrl!),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: Text(ar ? 'افتح البروشور' : 'Open brochure'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Brand.navy,
                        side: const BorderSide(color: Brand.line),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: Brand.cream, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Brand.navy),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: Brand.navy, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 8, bottom: 6),
          child: BrokerAvatar(size: 30),
        ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Brand.line),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final t = ((_c.value + i * 0.2) % 1.0);
                final opacity = 0.3 + 0.7 * (1 - (t - 0.5).abs() * 2).clamp(0, 1);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Opacity(
                    opacity: opacity.toDouble(),
                    child: const CircleAvatar(
                        radius: 3.5, backgroundColor: Color(0xFFC3C9D2)),
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChipsRow extends StatelessWidget {
  const _ChipsRow({required this.chips, required this.onTap});
  final List<(String, String)> chips;
  final void Function(String prompt)? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 38, top: 4),
      child: Wrap(
        spacing: 9,
        runSpacing: 9,
        children: chips
            .map((c) => InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onTap == null ? null : () => onTap!(c.$2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Brand.line),
                    ),
                    child: Text(c.$1,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Brand.navy)),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, 10 + MediaQuery.of(context).padding.bottom * 0.3),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: tr('chat_hint'),
                filled: true,
                fillColor: Brand.gray,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: enabled ? Brand.blue : Brand.muted,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onSend : null,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
