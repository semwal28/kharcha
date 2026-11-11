import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../domain/analysis.dart';
import '../../domain/category_guess.dart';
import '../../services/ai_coach.dart';
import '../../state/app_state.dart';
import '../theme.dart';

const _suggestions = <(String, String)>[
  ('Where can I save?', 'Where can I save money this month?'),
  ('Food delivery spend?', 'How much did I spend on food delivery this month?'),
  ('Afford a new phone?', 'Can I afford a new phone this month?'),
  ('Why more this month?', 'Why is this month more expensive than last month?'),
];

/// Chat with your money. Uses Claude when the server is connected,
/// and simple on-device answers otherwise.
class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key});
  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends ConsumerState<AskScreen> {
  final _turns = <ChatTurn>[const ChatTurn(false, 'Hi! Ask me anything about your spending.')];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  });

  String _localAnswer(String q) {
    final data = ref.read(appDataProvider).requireValue;
    final s = ref.read(summaryProvider)!;
    final ql = q.toLowerCase();
    final cat = guessCategory(q, data) ?? (ql.contains('food') ? data.byKey('delivery') : null);
    if (cat != null) {
      final c = s.cats[cat.id]!;
      return '${cat.name}: ${Money.fmt(c.spent)} this month (${c.count} spends). Last month by now: ${Money.fmt(c.prevSame)}.';
    }
    return 'I can answer questions about a category or shop for now, like “Swiggy spend?” or “Groceries?”. ${OfflineAiCoach.message}';
  }

  Future<void> _send(String q) async {
    q = q.trim();
    if (q.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _turns.add(ChatTurn(true, q));
      _busy = true;
    });
    _toBottom();
    final coach = ref.read(aiCoachProvider);
    String reply;
    if (!coach.available) {
      await Future.delayed(const Duration(milliseconds: 350));
      reply = _localAnswer(q);
    } else {
      try {
        final s = ref.read(summaryProvider)!;
        final data = ref.read(appDataProvider).requireValue;
        // Skip the greeting: the conversation sent to Claude starts with the user.
        reply = await coach.chat(aiSummary(s, data), _turns.skip(1).toList());
      } on AiException catch (e) {
        reply = e.message;
      } catch (_) {
        reply = 'Could not reach the server. Check your internet.';
      }
    }
    if (!mounted) return;
    setState(() {
      _turns.add(ChatTurn(false, reply));
      _busy = false;
    });
    _toBottom();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            children: [
              Row(
                children: [
                  Expanded(child: Text('Ask about your money', style: context.text.titleMedium)),
                  Text(ref.watch(aiCoachProvider).available ? 'Powered by Claude' : 'Quick answers', style: context.text.bodySmall),
                ],
              ),
              const SizedBox(height: 10),
              for (final (i, t) in _turns.indexed)
                Align(
                  key: ValueKey('turn$i'),
                  alignment: t.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: () {
                    final bubble = Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      constraints: const BoxConstraints(maxWidth: 320),
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                      decoration: BoxDecoration(
                        color: t.fromUser ? k.accent : k.surface,
                        border: t.fromUser ? null : Border.all(color: k.line),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(t.fromUser ? 16 : 5),
                          bottomRight: Radius.circular(t.fromUser ? 5 : 16),
                        ),
                      ),
                      child: Text(t.text, style: TextStyle(fontSize: 14, height: 1.45, color: t.fromUser ? k.accentInk : k.ink)),
                    );
                    return still
                        ? bubble
                        : bubble
                              .animate()
                              .fadeIn(duration: 220.ms)
                              .scaleXY(
                                begin: .85,
                                end: 1,
                                duration: 380.ms,
                                curve: Curves.easeOutBack,
                                alignment: t.fromUser ? Alignment.bottomRight : Alignment.bottomLeft,
                              );
                  }(),
                ),
              if (_busy)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: k.surface,
                      border: Border.all(color: k.line),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < 3; i++)
                          Container(
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(color: k.accent, shape: BoxShape.circle),
                              )
                              .animate(onPlay: (c) => c.repeat(), delay: (i * 160).ms)
                              .fade(begin: .25, end: 1, duration: 400.ms)
                              .then()
                              .fade(begin: 1, end: .25, duration: 400.ms),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (label, q) in _suggestions)
                    ActionChip(
                      label: Text(label),
                      onPressed: _busy ? null : () => _send(q),
                      backgroundColor: k.surface,
                      side: BorderSide(color: k.line),
                      labelStyle: TextStyle(fontSize: 13, color: k.ink2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                    ),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          color: k.bg,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: InputDecoration(hintText: 'Ask about your spending', fillColor: k.surface),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _busy ? null : () => _send(_input.text),
                icon: const Icon(Icons.arrow_upward_rounded),
                style: IconButton.styleFrom(backgroundColor: k.accent, foregroundColor: k.accentInk, fixedSize: const Size(46, 46)),
                tooltip: 'Send',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
