import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A single chat turn.
class ChatMsg {
  ChatMsg(this.role, this.content);
  final String role; // 'user' | 'assistant'
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
  factory ChatMsg.fromJson(Map<String, dynamic> j) =>
      ChatMsg('${j['role']}', '${j['content']}');
}

/// A saved conversation (header).
class SavedConversation {
  SavedConversation({
    required this.id,
    required this.title,
    required this.language,
    required this.updatedAt,
    this.messages = const [],
  });

  final String id;
  final String title;
  final String language;
  final DateTime updatedAt;
  final List<ChatMsg> messages;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'language': language,
        'updated_at': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory SavedConversation.fromJson(Map<String, dynamic> j) =>
      SavedConversation(
        id: '${j['id']}',
        title: '${j['title'] ?? 'Chat'}',
        language: '${j['language'] ?? 'en'}',
        updatedAt:
            DateTime.tryParse('${j['updated_at']}')?.toLocal() ?? DateTime.now(),
        messages: ((j['messages'] as List?) ?? [])
            .map((m) => ChatMsg.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

/// Saves & restores chat memory — both online (Supabase, per user) and locally
/// (shared_preferences cache, so saved chats are visible offline too).
class ChatStore {
  ChatStore._();
  static final ChatStore instance = ChatStore._();

  SupabaseClient get _db => Supabase.instance.client;
  String? get _uid => _db.auth.currentUser?.id;
  String get _cacheKey => 'homzy_saved_${_uid ?? "anon"}';

  /// Save (or update) a conversation. Returns its id.
  Future<String> save({
    String? id,
    required String title,
    required String language,
    required List<ChatMsg> messages,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');

    String convId = id ?? '';
    if (convId.isEmpty) {
      final row = await _db
          .from('conversations')
          .insert({'user_id': uid, 'title': title, 'language': language})
          .select('id')
          .single();
      convId = '${row['id']}';
    } else {
      await _db.from('conversations').update(
          {'title': title, 'language': language}).eq('id', convId);
      await _db.from('messages').delete().eq('conversation_id', convId);
    }

    if (messages.isNotEmpty) {
      await _db.from('messages').insert([
        for (final m in messages)
          {
            'conversation_id': convId,
            'user_id': uid,
            'role': m.role,
            'content': m.content,
          }
      ]);
    }

    await _cacheUpsert(SavedConversation(
      id: convId,
      title: title,
      language: language,
      updatedAt: DateTime.now(),
      messages: messages,
    ));
    return convId;
  }

  /// List saved conversation headers (newest first). Falls back to the local
  /// cache when offline.
  Future<List<SavedConversation>> list() async {
    try {
      final rows = await _db
          .from('conversations')
          .select('id,title,language,updated_at')
          .order('updated_at', ascending: false);
      final items = (rows as List)
          .map((r) => SavedConversation.fromJson(r as Map<String, dynamic>))
          .toList();
      return items;
    } catch (_) {
      return _cacheRead();
    }
  }

  /// Load the full message list for a conversation (online, else cache).
  Future<List<ChatMsg>> messages(String conversationId) async {
    try {
      final rows = await _db
          .from('messages')
          .select('role,content,created_at')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);
      return (rows as List)
          .map((r) => ChatMsg.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      final cached = (await _cacheRead())
          .where((c) => c.id == conversationId)
          .toList();
      return cached.isEmpty ? <ChatMsg>[] : cached.first.messages;
    }
  }

  Future<void> delete(String conversationId) async {
    try {
      await _db.from('conversations').delete().eq('id', conversationId);
    } catch (_) {/* keep going; still drop from cache */}
    final items = await _cacheRead()
      ..removeWhere((c) => c.id == conversationId);
    await _cacheWrite(items);
  }

  // ---- local cache (shared_preferences) ----------------------------------
  Future<List<SavedConversation>> _cacheRead() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => SavedConversation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _cacheWrite(List<SavedConversation> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _cacheKey, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> _cacheUpsert(SavedConversation conv) async {
    final items = await _cacheRead()..removeWhere((c) => c.id == conv.id);
    items.insert(0, conv);
    await _cacheWrite(items);
  }
}
