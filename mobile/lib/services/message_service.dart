import 'package:supabase_flutter/supabase_flutter.dart';

class Conversation {
  Conversation({
    required this.id,
    required this.listingId,
    required this.otherId,
    this.otherName,
    this.otherAvatar,
    this.listingTitle,
    this.lastMessage,
    this.lastAt,
  });

  final String id;
  final String? listingId;
  final String otherId;
  String? otherName;
  String? otherAvatar;
  String? listingTitle;
  final String? lastMessage;
  final DateTime? lastAt;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.mine = false,
  });
  final String id;
  final String senderId;
  final String body;
  final DateTime createdAt;
  final bool mine;
}

/// User-to-user messaging about a listing.
class MessageService {
  MessageService._();
  static final MessageService instance = MessageService._();
  SupabaseClient get _db => Supabase.instance.client;

  String? get _uid => _db.auth.currentUser?.id;

  /// Find (or create) the conversation between me (buyer) and a listing's owner.
  Future<String> startOrGet({
    required String listingId,
    required String sellerId,
  }) async {
    final uid = _uid!;
    final existing = await _db
        .from('listing_conversations')
        .select('id')
        .eq('listing_id', listingId)
        .eq('buyer_id', uid)
        .maybeSingle();
    if (existing != null) return '${existing['id']}';
    final row = await _db.from('listing_conversations').insert({
      'listing_id': listingId,
      'buyer_id': uid,
      'seller_id': sellerId,
    }).select('id').single();
    return '${row['id']}';
  }

  /// All conversations I'm part of, newest first, with the other person's name.
  Future<List<Conversation>> conversations() async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _db
        .from('listing_conversations')
        .select('id, listing_id, buyer_id, seller_id, last_message, last_at, '
            'listing:listings(title)')
        .or('buyer_id.eq.$uid,seller_id.eq.$uid')
        .order('last_at', ascending: false, nullsFirst: false);
    final convos = <Conversation>[];
    final otherIds = <String>{};
    for (final r in rows as List) {
      final m = r as Map<String, dynamic>;
      final other = m['buyer_id'] == uid
          ? '${m['seller_id']}'
          : '${m['buyer_id']}';
      otherIds.add(other);
      convos.add(Conversation(
        id: '${m['id']}',
        listingId: m['listing_id']?.toString(),
        otherId: other,
        listingTitle: (m['listing'] as Map?)?['title']?.toString(),
        lastMessage: m['last_message']?.toString(),
        lastAt: m['last_at'] != null
            ? DateTime.tryParse('${m['last_at']}')
            : null,
      ));
    }
    if (otherIds.isNotEmpty) {
      final profs = await _db
          .from('profiles')
          .select('id, full_name, avatar_url')
          .inFilter('id', otherIds.toList());
      final byId = {
        for (final p in profs) '${(p as Map)['id']}': p
      };
      for (final c in convos) {
        final p = byId[c.otherId] as Map?;
        c.otherName = p?['full_name']?.toString();
        c.otherAvatar = p?['avatar_url']?.toString();
      }
    }
    return convos;
  }

  Future<List<ChatMessage>> messages(String conversationId) async {
    final uid = _uid;
    final rows = await _db
        .from('listing_messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      return ChatMessage(
        id: '${m['id']}',
        senderId: '${m['sender_id']}',
        body: '${m['body']}',
        createdAt: DateTime.tryParse('${m['created_at']}') ?? DateTime.now(),
        mine: '${m['sender_id']}' == uid,
      );
    }).toList();
  }

  Future<void> send(String conversationId, String body) async {
    final uid = _uid!;
    await _db.from('listing_messages').insert({
      'conversation_id': conversationId,
      'sender_id': uid,
      'body': body,
    });
    await _db.from('listing_conversations').update({
      'last_message': body,
      'last_at': DateTime.now().toIso8601String(),
    }).eq('id', conversationId);
  }
}
