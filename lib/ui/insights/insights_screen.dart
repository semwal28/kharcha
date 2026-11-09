import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../domain/analysis.dart';
import '../../services/ai_coach.dart';
import '../../state/app_state.dart';
import '../home/home_screen.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(summaryProvider)!;
    final k = context.k;
    final left = s.income - s.projected;
    final all = s.cats.values.where((c) => c.spent > 0 || c.prevSame > 0).toList()..sort((a, b) => b.spent.compareTo(a.spent));

    final blocks = <Widget>[
      _SaveCard(s: s),
      SectionHeader('Where to save', trailing: Text('${s.leaks.length} found', style: context.text.bodySmall)),
      KCard(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: s.leaks.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Nothing yet. Check back in a few weeks.', style: context.text.bodyMedium),
              )
            : Column(
                children: [
                  for (final (i, l) in s.leaks.indexed) ...[if (i > 0) Divider(height: 1, color: k.line), Enter(index: i + 2, child: LeakTile(l))],
                ],
              ),
      ),
      if (ref.watch(aiCoachProvider).available) ...[const SectionHeader('AI savings plan'), const _AiPlanCard()],
      const SectionHeader('This month'),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.3,
        children: [
          _Stat('Forecast spend', s.projected),
          _Stat(s.income > 0 ? 'Left from income' : 'Set income in ⚙', s.income > 0 ? left : 0, color: s.income > 0 ? (left >= 0 ? k.good : k.bad) : null),
          _Stat('Weekend day, avg', s.weekendAvg),
          _Stat('Weekday, avg', s.weekdayAvg),
        ],
      ),
      SectionHeader('Daily spends', trailing: Text('excl. fixed bills', style: context.text.bodySmall)),
      _DailyChartCard(s: s),
      const SectionHeader('All categories'),
      KCard(
        child: Column(
          children: [
            CategoryRows(stats: all),
            const SizedBox(height: 12),
            const BarLegend(),
          ],
        ),
      ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        for (final (i, b) in blocks.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Enter(index: i, child: b),
          ),
      ],
    );
  }
}

class _SaveCard extends StatelessWidget {
  const _SaveCard({required this.s});
  final MonthSummary s;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return KCard(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -60,
            top: -60,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(color: k.goodSoft, shape: BoxShape.circle),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1, end: 1.15, duration: 2.seconds, curve: Curves.easeInOut),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('YOU COULD SAVE', style: context.text.labelSmall),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Odometer(
                    text: Money.inr(s.monthlySavings),
                    style: TextStyle(fontFamily: kDisplay, fontSize: 36, fontWeight: FontWeight.w700, color: k.good, letterSpacing: -.8),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '/month',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: k.good),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${Money.inr(s.monthlySavings * 12)} a year${s.oneTimeSavings > 0 ? ' + ${Money.inr(s.oneTimeSavings)} to get back' : ''}',
                style: context.text.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.paise, {this.color});
  final String label;
  final double paise;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: context.k.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.k.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
        const SizedBox(height: 2),
        CountUp(
          value: paise,
          format: Money.inr,
          delay: const Duration(milliseconds: 300),
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color ?? context.k.ink),
        ),
      ],
    ),
  );
}

/// Ask Claude for a ranked plan. Idle → loading → plan (or a clear error).
class _AiPlanCard extends ConsumerStatefulWidget {
  const _AiPlanCard();
  @override
  ConsumerState<_AiPlanCard> createState() => _AiPlanCardState();
}

class _AiPlanCardState extends ConsumerState<_AiPlanCard> {
  bool _loading = false;
  List<PlanItem>? _items;
  String? _error;

  Future<void> _run() async {
    final coach = ref.read(aiCoachProvider);
    final s = ref.read(summaryProvider)!;
    final data = ref.read(appDataProvider).requireValue;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await coach.plan(aiSummary(s, data));
      if (mounted) setState(() => _items = items);
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the server. Check your internet.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final available = ref.watch(aiCoachProvider).available;
    Widget body;
    if (_loading) {
      body = Row(
        children: [
          SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: k.accent)),
          const SizedBox(width: 10),
          Text('Claude is thinking…', style: context.text.bodyMedium),
        ],
      );
    } else if (_items != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, it) in _items!.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: k.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: k.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(it.title, style: context.text.titleSmall)),
                        Text(
                          '${Money.inr(it.monthlyPaise)}/mo',
                          style: TextStyle(fontWeight: FontWeight.w700, color: k.good, fontFeatures: kTabular),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Pill(switch (it.difficulty) {
                          'Easy' => PillKind.good,
                          'Hard' => PillKind.bad,
                          _ => PillKind.warn,
                        }, it.difficulty),
                        Text(it.why, style: context.text.bodyMedium?.copyWith(fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ActionLine(it.action),
                  ],
                ),
              ).animate(delay: (i * 110).ms).fadeIn(duration: 350.ms).slideY(begin: .15, end: 0, curve: Curves.easeOutCubic),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: LinkButton('New plan', onTap: _run),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _error ?? (available ? 'A step-by-step plan from Claude, easiest first.' : OfflineAiCoach.message),
            style: context.text.bodyMedium?.copyWith(color: _error != null ? k.bad : null),
          ),
          if (available) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _run,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('Build my plan'),
              style: FilledButton.styleFrom(
                backgroundColor: k.accent,
                foregroundColor: k.accentInk,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      );
    }
    return KCard(
      child: AnimatedSize(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic, alignment: Alignment.topCenter, child: body),
    );
  }
}

class _DailyChartCard extends StatefulWidget {
  const _DailyChartCard({required this.s});
  final MonthSummary s;
  @override
  State<_DailyChartCard> createState() => _DailyChartCardState();
}

class _DailyChartCardState extends State<_DailyChartCard> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  int? _sel;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _readout() {
    final s = widget.s;
    if (_sel == null) return 'Tap a bar for details';
    final day = DateTime(s.now.year, s.now.month, _sel!);
    if (_sel! > s.day) return '${fmtDay(day)}: not yet';
    final d = s.daily[_sel! - 1];
    final over = d.amount - s.dailyBudget;
    return '${fmtDay(day)} · ${Money.inr(d.amount)} · ${d.count} spend${d.count == 1 ? '' : 's'}${over > 0 ? ' · ${Money.inr(over)} over' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final s = widget.s;
    final still = reduceMotion(context);
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(_readout(), key: ValueKey(_sel), style: context.text.bodyMedium?.copyWith(fontSize: 13)),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, box) {
              const h = 160.0;
              return GestureDetector(
                onTapDown: (d) {
                  const pl = 36.0;
                  final bw = (box.maxWidth - pl - 4) / s.daysInMonth;
                  final day = ((d.localPosition.dx - pl) / bw).floor() + 1;
                  if (day >= 1 && day <= s.daysInMonth) setState(() => _sel = day);
                },
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => CustomPaint(
                    size: Size(box.maxWidth, h),
                    painter: _DailyPainter(
                      s: s,
                      t: still ? 1 : _c.value,
                      selected: _sel,
                      bar: k.bar,
                      barStrong: k.barStrong,
                      grid: k.line,
                      label: k.muted,
                      budget: k.pop,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 6,
                    decoration: BoxDecoration(color: k.bar, borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(width: 6),
                  Text('Spent', style: context.text.bodySmall),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    child: CustomPaint(size: const Size(14, 2), painter: _DashPainter(k.pop)),
                  ),
                  const SizedBox(width: 6),
                  Text('Daily budget ${Money.inr(s.dailyBudget)}', style: context.text.bodySmall),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

double _niceMax(double v) {
  if (v <= 0) return 10000;
  final p = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  final n = v / p;
  return (n <= 1
          ? 1
          : n <= 2
          ? 2
          : n <= 2.5
          ? 2.5
          : n <= 5
          ? 5
          : 10) *
      p;
}

class _DailyPainter extends CustomPainter {
  _DailyPainter({
    required this.s,
    required this.t,
    required this.selected,
    required this.bar,
    required this.barStrong,
    required this.grid,
    required this.label,
    required this.budget,
  });
  final MonthSummary s;
  final double t;
  final int? selected;
  final Color bar, barStrong, grid, label, budget;

  @override
  void paint(Canvas canvas, Size size) {
    const pl = 36.0, pr = 4.0, pt = 8.0, pb = 18.0;
    final iw = size.width - pl - pr, ih = size.height - pt - pb;
    final maxV = _niceMax(math.max(s.dailyBudget, s.daily.fold<double>(0, (m, d) => math.max(m, d.amount.toDouble()))));
    double y(double v) => pt + ih - v / maxV * ih;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    void text(String str, Offset at, {TextAlign align = TextAlign.right}) {
      final tp = TextPainter(
        text: TextSpan(
          text: str,
          style: TextStyle(fontSize: 10, color: label, fontFamily: kBody),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = align == TextAlign.right ? at.dx - tp.width : at.dx - tp.width / 2;
      tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
    }

    for (final v in [0.0, maxV / 2, maxV]) {
      canvas.drawLine(Offset(pl, y(v)), Offset(size.width - pr, y(v)), gridPaint);
      text(Money.short(v), Offset(pl - 6, y(v)));
    }
    final bw = iw / s.daysInMonth;
    final gap = math.max(1.5, bw * .28);
    for (final d in s.daily) {
      if (d.amount <= 0 || d.day > s.day) continue;
      final i = d.day - 1;
      final local = ((t - i * .012) / .55).clamp(0.0, 1.0);
      final grow = Curves.easeOutBack.transform(local);
      final top = y(d.amount * grow);
      final x = pl + i * bw + gap / 2, w = bw - gap, base = y(0);
      if (base - top < .5) continue;
      final r = math.min(3.0, math.min(w / 2, base - top));
      final strong = d.day == s.day || d.day == selected;
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTRB(x, top, x + w, base), topLeft: Radius.circular(r), topRight: Radius.circular(r)),
        Paint()..color = strong ? barStrong : bar,
      );
    }
    // Daily budget: dashed line
    final by = y(s.dailyBudget);
    final dash = Paint()
      ..color = budget
      ..strokeWidth = 2;
    for (var x = pl; x < size.width - pr; x += 8) {
      canvas.drawLine(Offset(x, by), Offset(math.min(x + 4, size.width - pr), by), dash);
    }
    for (final dd in {1, 8, 15, 22, s.daysInMonth}) {
      text('$dd', Offset(pl + (dd - .5) * bw, size.height - 6), align: TextAlign.center);
    }
  }

  @override
  bool shouldRepaint(_DailyPainter o) => o.t != t || o.selected != selected || o.s != s || o.bar != bar;
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, size.height / 2), Offset(5, size.height / 2), p);
    canvas.drawLine(Offset(9, size.height / 2), Offset(14, size.height / 2), p);
  }

  @override
  bool shouldRepaint(_DashPainter o) => o.color != color;
}
