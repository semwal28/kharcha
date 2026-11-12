import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/analysis.dart';

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

/// A savings plan worked out on the device from the money-leak rules.
/// Used when the server AI isn't available, so the plan always works.
List<PlanItem> localPlan(MonthSummary s) => [
  for (final l in s.leaks.take(5))
    PlanItem(
      title: l.title,
      why: l.detail,
      action: l.action,
      monthlyPaise: l.monthlyPaise,
      difficulty: switch (l.kind) {
        LeakKind.leak => 'Easy',
        LeakKind.alert => 'Easy',
        LeakKind.habit => 'Medium',
      },
    ),
];

/// Used when there is no server AI: no account, or a build made with
/// --dart-define=AI_ENABLED=false. The app answers on the device instead.
class OfflineAiCoach implements AiCoach {
  static const message = 'The AI coach needs an account. On-device tips are shown instead.';
  @override
  bool get available => false;
  @override
  Future<List<PlanItem>> plan(String summary) async => throw AiException(message, unavailable: true);
  @override
  Future<String> chat(String summary, List<ChatTurn> turns) async => throw AiException(message, unavailable: true);
}

/// Calls the `ai-coach` Supabase Edge Function, which calls a free AI model
/// (or Claude). The API key never ships inside the app.
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
      throw AiException('The AI coach sent an empty answer. Try again.');
    } on FunctionException catch (e) {
      final details = e.details;
      final msg = details is Map ? details['message'] as String? : null;
      switch (e.status) {
        case 401:
          throw AiException('Sign in again to use AI.');
        case 429:
          throw AiException(msg ?? 'Daily AI limit reached. Try again tomorrow.');
        case 404:
          // The function isn't deployed yet.
          throw AiException('AI is not set up on the server yet.', unavailable: true);
        case 503:
          // Not set up (use on-device answers) or busy (say so).
          final notSetUp = details is Map && details['error'] == 'not_configured';
          throw AiException(msg ?? 'The AI coach is busy. Try again in a minute.', unavailable: notSetUp);
        default:
          throw AiException(msg ?? 'The AI coach could not answer right now. Try again.');
      }
    }
  }

  @override
  Future<List<PlanItem>> plan(String summary) async {
    final data = await _call({'mode': 'plan', 'summary': summary});
    final items = [for (final j in (data['items'] as List? ?? const [])) PlanItem.fromJson(j)].whereType<PlanItem>().toList();
    if (items.isEmpty) throw AiException('The AI coach did not return a plan. Try again.');
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
    if (reply.isEmpty) throw AiException('The AI coach sent an empty answer. Try again.');
    return reply;
  }
}
