import 'package:supabase_flutter/supabase_flutter.dart';

class PlanItem {
  const PlanItem({required this.title, required this.why, required this.action, required this.monthlyPaise, required this.difficulty});
  final String title;
  final String why;
  final String action;
  final int monthlyPaise;

  /// Easy, Medium or Hard
  final String difficulty;

  static PlanItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final title = j['title'];
    if (title is! String || title.trim().isEmpty) return null;
    final d = j['difficulty'];
    return PlanItem(
      title: title.trim(),
      why: (j['why'] as String? ?? '').trim(),
      action: (j['action'] as String? ?? '').trim(),
      monthlyPaise: (((j['monthly_saving'] as num?) ?? 0).clamp(0, 10000000) * 100).round(),
      difficulty: const ['Easy', 'Medium', 'Hard'].contains(d) ? d as String : 'Medium',
    );
  }
}

class ChatTurn {
  const ChatTurn(this.fromUser, this.text);
  final bool fromUser;
  final String text;
  Map<String, String> toJson() => {'role': fromUser ? 'user' : 'assistant', 'content': text};
}

class AiException implements Exception {
  AiException(this.message, {this.unavailable = false});
  final String message;

  /// True when AI can't be used at all here (demo mode, not configured).
  final bool unavailable;
  @override
  String toString() => message;
}

abstract class AiCoach {
  bool get available;
  Future<List<PlanItem>> plan(String summary);
  Future<String> chat(String summary, List<ChatTurn> turns);
}

/// Demo mode: AI needs the backend (it holds the Claude API key).
class OfflineAiCoach implements AiCoach {
  static const message = 'AI needs the Kharcha server. Connect Supabase to turn it on.';
  @override
  bool get available => false;
  @override
  Future<List<PlanItem>> plan(String summary) async => throw AiException(message, unavailable: true);
  @override
  Future<String> chat(String summary, List<ChatTurn> turns) async => throw AiException(message, unavailable: true);
}

/// Calls the `ai-coach` Supabase Edge Function, which calls Claude.
/// The API key never ships inside the app.
class SupabaseAiCoach implements AiCoach {
  SupabaseAiCoach(this._db);
  final SupabaseClient _db;

  @override
  bool get available => true;

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final res = await _db.functions.invoke('ai-coach', body: body);
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      throw AiException('Claude sent an empty answer. Try again.');
    } on FunctionException catch (e) {
      final details = e.details;
      final msg = details is Map ? details['message'] as String? : null;
      switch (e.status) {
        case 401:
          throw AiException('Sign in again to use AI.');
        case 429:
          throw AiException(msg ?? 'Daily AI limit reached. Try again tomorrow.');
        case 503:
          throw AiException(msg ?? 'AI is not set up on the server yet.', unavailable: true);
        default:
          throw AiException(msg ?? 'Claude could not answer right now. Try again.');
      }
    }
  }

  @override
  Future<List<PlanItem>> plan(String summary) async {
    final data = await _call({'mode': 'plan', 'summary': summary});
    final items = [for (final j in (data['items'] as List? ?? const [])) PlanItem.fromJson(j)].whereType<PlanItem>().toList();
    if (items.isEmpty) throw AiException('Claude did not return a plan. Try again.');
    return items;
  }

  @override
  Future<String> chat(String summary, List<ChatTurn> turns) async {
    final data = await _call({
      'mode': 'chat',
      'summary': summary,
      'messages': [for (final t in turns.length > 8 ? turns.sublist(turns.length - 8) : turns) t.toJson()],
    });
    final reply = (data['reply'] as String? ?? '').trim();
    if (reply.isEmpty) throw AiException('Claude sent an empty answer. Try again.');
    return reply;
  }
}
