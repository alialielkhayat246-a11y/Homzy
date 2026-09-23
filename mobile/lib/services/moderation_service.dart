import 'package:supabase_flutter/supabase_flutter.dart';

class ModerationService {
  ModerationService._();
  static final ModerationService instance = ModerationService._();

  SupabaseClient get _db => Supabase.instance.client;

  Future<void> reportAiResponse({
    required String content,
    required String reason,
    String? conversationId,
    String? details,
  }) async {
    await _db.rpc('report_ai_content', params: {
      'p_content': content,
      'p_reason': reason,
      'p_conversation': conversationId,
      'p_details': details,
    });
  }
}
