import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../../domain/analysis.dart';
import '../../state/app_state.dart';
import '../add/add_expense_sheet.dart';
import '../theme.dart';
import '../tx/tx_sheet.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.onAdd, required this.onSeeTips});
  final ValueChanged<AddPrefill?> onAdd;
  final VoidCallback onSeeTips;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider).requireValue;
    final s = ref.watch(summaryProvider)!;
    final isExample = ref.watch(repositoryProvider).hasExampleData;
    final top = s.leaks.isEmpty ? null : s.leaks.first;
    final topCats = s.cats.values.where((c) => c.spent > 0 && c.category.key != 'rent').toList()..sort((a, b) => b.spent.compareTo(a.spent));
    final top5 = topCats.take(5).toList();
    final list = _showAll ? s.cur : s.cur.take(10).toList();

    final blocks = <Widget>[
      if (isExample) const _ExampleChip(),
      _HeroCard(s: s),
      const SectionHeader('Quick add'),
      _QuickAdd(data: data, now: s.now, onAdd: widget.onAdd),
      if (top != null) _TipCard(leak: top, total: s.leaks.length, onSeeAll: widget.onSeeTips),
      SectionHeader('Where it went', trailing: Text('excl. rent', style: context.text.bodySmall)),
      KCard(
        child: top5.isEmpty
            ? Text('Your top categories will show up here.', style: context.text.bodyMedium)
            : Column(
                children: [
                  CategoryRows(stats: top5),
                  const SizedBox(height: 12),
                  const BarLegend(),
                ],
              ),
      ),
      SectionHeader(
        'Recent',
        trailing: s.cur.length > 10 ? LinkButton(_showAll ? 'Show less' : 'See all', onTap: () => setState(() => _showAll = !_showAll)) : null,
      ),
      KCard(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
        child: list.isEmpty
            ? const FloatingEmpty(title: 'No expenses yet', subtitle: 'Tap + to add your first one.')
            : _RecentList(txns: list, now: s.now, onAddAgain: widget.onAdd),
      ),
    ];
    return RefreshIndicator(
      color: context.k.accent,
      onRefresh: () => ref.read(appDataProvider.notifier).refresh(),
      child: ListView(
        key: const ValueKey('home-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          for (final (i, b) in blocks.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Enter(index: i, child: b),
            ),
        ],
      ),
    );
  }
}

class _ExampleChip extends StatelessWidget {
  const _ExampleChip();
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: context.k.surface2, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: context.k.pop, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text('Example data', style: context.text.bodySmall?.copyWith(color: context.k.ink2)),
        ],
      ),
    ),
  );
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.s});
  final MonthSummary s;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final diff = s.spent - s.prevSameTotal;
    final pct = (s.budgetUsed * 100).round();
    final ink = TextStyle(color: k.heroInk, fontFamily: kBody);
    return AuroraBackground(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SPENT IN ${s.monthName.toUpperCase()}',
                        style: ink.copyWith(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .9, color: k.heroInk.withValues(alpha: .8)),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Odometer(
                          text: Money.fmt(s.spent),
                          style: TextStyle(fontFamily: kDisplay, fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -1.2, color: k.heroInk),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(diff > 0 ? Icons.north_east_rounded : Icons.south_east_rounded, size: 15, color: k.heroInk),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              s.spent == 0 ? 'Nothing spent yet this month' : '${Money.fmt(diff.abs())} ${diff > 0 ? 'more' : 'less'} than last month',
                              style: ink.copyWith(fontSize: 13, color: k.heroInk.withValues(alpha: .92)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Ring(
                  fraction: s.budgetUsed,
                  size: 78,
                  stroke: 8,
                  track: k.heroInk.withValues(alpha: .18),
                  color: s.budgetUsed > 1 ? k.bad : k.pop,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CountUp(
                        value: pct.toDouble(),
                        format: (v) => '${v.round()}%',
                        style: ink.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      Text('of budget', style: ink.copyWith(fontSize: 10, color: k.heroInk.withValues(alpha: .85))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Semantics(
              label: '$pct% of budget used, ${(s.monthProgress * 100).round()}% of the month gone',
              child: GrowBar(
                fraction: s.budgetUsed,
                color: k.heroInk,
                track: k.heroInk.withValues(alpha: .2),
                marker: s.monthProgress,
                markerColor: k.pop,
                height: 8,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              children: [
                Text('Budget ${Money.fmt(s.totalBudget)}', style: ink.copyWith(fontSize: 12, color: k.heroInk.withValues(alpha: .85))),
                Text('Yellow line = today', style: ink.copyWith(fontSize: 12, color: k.heroInk.withValues(alpha: .85))),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _HeroStat(label: 'Safe to spend today', paise: s.safeToday),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HeroStat(label: 'Month-end forecast', paise: s.projected),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.paise});
  final String label;
  final double paise;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: k.heroInk.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: k.heroInk.withValues(alpha: .85)),
          ),
          const SizedBox(height: 2),
          CountUp(
            value: paise,
            format: Money.fmt,
            delay: const Duration(milliseconds: 300),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: k.heroInk),
          ),
        ],
      ),
    );
  }
}

/// Your usual spends from the last 30 days, one tap to repeat.
class _QuickAdd extends StatelessWidget {
  const _QuickAdd({required this.data, required this.now, required this.onAdd});
  final AppData data;
  final DateTime now;
  final ValueChanged<AddPrefill?> onAdd;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final since = now.subtract(const Duration(days: 30));
    final groups = <String, (Txn, int)>{};
    for (final t in data.txns) {
      if (t.isRecurring || t.spentAt.isBefore(since)) continue;
      final key = t.titleOr(data.cat(t.categoryId).name);
      final g = groups[key];
      groups[key] = g == null ? (t, 1) : (g.$1, g.$2 + 1); // txns are newest first, so $1 is the latest
    }
    final usual = groups.entries.toList()..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    final chips = <Widget>[
      _QuickChip(
        icon: const CatIcon('tag', size: 30),
        iconOverride: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: k.pop, borderRadius: BorderRadius.circular(9)),
          child: Icon(Icons.add_rounded, color: k.popInk, size: 20),
        ),
        title: 'New',
        subtitle: 'Any amount',
        dashed: true,
        onTap: () => onAdd(null),
      ),
      for (final e in usual.take(6))
        _QuickChip(
          icon: CatIcon(data.cat(e.value.$1.categoryId).isCustom ? 'tag' : data.cat(e.value.$1.categoryId).icon, size: 30),
          title: e.key,
          subtitle: Money.fmt(e.value.$1.amountPaise),
          onTap: () => onAdd(AddPrefill(amountPaise: e.value.$1.amountPaise, categoryId: e.value.$1.categoryId, note: e.key, pay: e.value.$1.pay)),
        ),
    ];
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => Enter(index: i, child: chips[i]),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.icon, required this.title, required this.subtitle, required this.onTap, this.iconOverride, this.dashed = false});
  final Widget icon;
  final Widget? iconOverride;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Squish(
      child: Material(
        color: k.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: dashed ? k.pop : k.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                iconOverride ?? icon,
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Text(subtitle, style: context.text.bodySmall?.copyWith(fontFeatures: kTabular)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.leak, required this.total, required this.onSeeAll});
  final Leak leak;
  final int total;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Squish(
      scale: .985,
      child: GlowBorderCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const AiBadge(label: 'Smart tip'),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Save ${leak.saveText}',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, color: k.good, fontFeatures: kTabular),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(leak.title, style: context.text.titleMedium),
            const SizedBox(height: 2),
            Text(leak.detail, style: context.text.bodyMedium),
            const SizedBox(height: 8),
            ActionLine(leak.action),
            const SizedBox(height: 6),
            LinkButton('See all $total tips', onTap: onSeeAll),
          ],
        ),
      ),
    );
  }
}

/// Small "✦ Smart tip" badge with a twinkling star.
class AiBadge extends StatefulWidget {
  const AiBadge({super.key, required this.label});
  final String label;
  @override
  State<AiBadge> createState() => _AiBadgeState();
}

class _AiBadgeState extends State<AiBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final still = reduceMotion(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
      decoration: BoxDecoration(color: k.accentSoft, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              final t = still ? 0.0 : math.sin(_c.value * math.pi);
              return Transform.rotate(
                angle: t * .8,
                child: Transform.scale(scale: 1 + .25 * t, child: child),
              );
            },
            child: Icon(Icons.auto_awesome_rounded, size: 14, color: k.accent),
          ),
          const SizedBox(width: 5),
          Text(
            widget.label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: k.accent),
          ),
        ],
      ),
    );
  }
}

/// Category rows with a bar for this month and a tick for last month.
class CategoryRows extends StatelessWidget {
  const CategoryRows({super.key, required this.stats});
  final List<CatStat> stats;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final maxV = math.max(1, stats.fold<int>(0, (m, c) => math.max(m, math.max(c.spent, c.prevSame))));
    return Column(
      children: [
        for (final (i, c) in stats.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CatIcon(c.category.isCustom ? 'tag' : c.category.icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.category.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                          ),
                          Text(
                            Money.fmt(c.spent),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFeatures: kTabular),
                          ),
                        ],
                      ),
                      GrowBar(
                        fraction: c.spent / maxV,
                        color: k.accent,
                        track: k.surface2,
                        marker: c.prevSame / maxV,
                        delay: Duration(milliseconds: 250 + i * 70),
                      ),
                      Row(
                        children: [
                          Expanded(child: Text('Last month ${Money.fmt(c.prevSame)}', style: context.text.bodySmall)),
                          Text(
                            c.spent == c.prevSame ? 'same' : '${c.spent > c.prevSame ? '+' : '−'}${Money.fmt((c.spent - c.prevSame).abs())}',
                            style: context.text.bodySmall?.copyWith(fontFeatures: kTabular),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class BarLegend extends StatelessWidget {
  const BarLegend({super.key});
  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 6,
              decoration: BoxDecoration(color: k.accent, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 6),
            Text('This month', style: context.text.bodySmall),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 2, height: 12, color: k.ink2),
            const SizedBox(width: 6),
            Text('Last month, same day', style: context.text.bodySmall),
          ],
        ),
      ],
    );
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({required this.txns, required this.now, required this.onAddAgain});
  final List<Txn> txns;
  final DateTime now;
  final ValueChanged<AddPrefill> onAddAgain;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    DateTime? lastDay;
    for (final t in txns) {
      final day = dateOnly(t.spentAt);
      if (day != lastDay) {
        final total = txns.where((x) => dateOnly(x.spentAt) == day).fold(0, (s, x) => s + x.amountPaise);
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(dayLabel(day, now), style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                ),
                Text(
                  Money.fmt(total),
                  style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600, fontFeatures: kTabular),
                ),
              ],
            ),
          ),
        );
        lastDay = day;
      }
      children.add(TxTile(t, key: ValueKey(t.id), onAddAgain: onAddAgain));
    }
    return Column(children: children);
  }
}
