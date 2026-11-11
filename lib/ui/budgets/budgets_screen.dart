import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../domain/analysis.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import 'plan_sections.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(summaryProvider)!;
    final data = ref.watch(appDataProvider).requireValue;
    final k = context.k;
    final left = s.totalBudget - s.spent;
    final rows = s.cats.values.where((c) => c.category.key != 'fees' || c.spent > 0).toList()
      ..sort((a, b) => a.category.sortOrder.compareTo(b.category.sortOrder));

    final blocks = <Widget>[
      if (data.extrasAvailable) ...[const GoalsSection(), const OwedSection()] else const ExtrasMissingCard(),
      const RepeatsSection(),
      const SectionHeader('Budgets'),
      KCard(
        child: Row(
          children: [
            Ring(
              fraction: s.budgetUsed,
              size: 96,
              stroke: 10,
              track: k.surface2,
              color: s.budgetUsed > 1 ? k.bad : k.accent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CountUp(
                    value: s.budgetUsed * 100,
                    format: (v) => '${v.round()}%',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  Text('used', style: context.text.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                children: [
                  _Line(
                    'Budget',
                    CountUp(
                      value: s.totalBudget.toDouble(),
                      format: Money.fmt,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  _Line(
                    'Spent',
                    CountUp(
                      value: s.spent.toDouble(),
                      format: Money.fmt,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  _Line(
                    'Left',
                    CountUp(
                      value: left.toDouble(),
                      format: Money.fmt,
                      style: TextStyle(fontWeight: FontWeight.w700, color: left >= 0 ? k.good : k.bad),
                    ),
                  ),
                  _Line(
                    'Days left',
                    Text(
                      '${s.daysInMonth - s.day + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: kTabular),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      KCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Suggested budgets', style: context.text.titleSmall),
                  Text('10% below last month', style: context.text.bodySmall),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: () async {
                try {
                  await ref.read(appDataProvider.notifier).setBudgets(suggestBudgets(s));
                  if (context.mounted) toast(context, 'Suggested budgets applied');
                } catch (e) {
                  if (context.mounted) toast(context, e.toString());
                }
              },
              style: FilledButton.styleFrom(backgroundColor: k.surface2, foregroundColor: k.ink),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
      KCard(
        child: Column(
          children: [
            for (final (i, c) in rows.indexed) ...[
              if (i > 0) Divider(height: 24, color: k.line),
              Enter(
                index: i + 2,
                child: _BudgetRow(stat: c, s: s),
              ),
            ],
          ],
        ),
      ),
      Text('Faint line on each bar = today', style: context.text.bodySmall),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        for (final (i, b) in blocks.indexed)
          if (b is! SizedBox)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Enter(index: i, child: b),
            ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);
  final String label;
  final Widget value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label, style: context.text.bodyMedium)),
        value,
      ],
    ),
  );
}

class _BudgetRow extends ConsumerWidget {
  const _BudgetRow({required this.stat, required this.s});
  final CatStat stat;
  final MonthSummary s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final c = stat;
    final (Pill pill, Color color) = c.budget == 0
        ? (const Pill(PillKind.info, 'No budget'), k.accent)
        : c.overBudget
        ? (Pill(PillKind.bad, 'Over by ${Money.fmt(c.spent - c.budget)}'), k.bad)
        : c.likelyOver
        ? (const Pill(PillKind.warn, 'Likely over'), k.warn)
        : (const Pill(PillKind.good, 'On track'), k.good);
    final variable = c.recExpected < c.projected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CatIcon(c.category.isCustom ? 'tag' : c.category.icon),
            const SizedBox(width: 10),
            Expanded(child: Text(c.category.name, style: context.text.titleSmall?.copyWith(fontSize: 14))),
            LinkButton('Edit', onTap: () => _edit(context, ref)),
          ],
        ),
        const SizedBox(height: 4),
        GrowBar(
          fraction: c.budget > 0 ? c.spent / c.budget : 0,
          color: color,
          track: k.surface2,
          marker: c.budget > 0 && variable ? s.monthProgress : null,
          markerColor: k.ink2.withValues(alpha: .6),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                '${Money.fmt(c.spent)} of ${c.budget > 0 ? Money.fmt(c.budget) : '—'}',
                style: context.text.bodySmall?.copyWith(fontFeatures: kTabular),
              ),
            ),
            pill,
          ],
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final ctl = TextEditingController(text: stat.budget > 0 ? '${(stat.budget / 100).round()}' : '');
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Budget for ${stat.category.name}'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
          decoration: InputDecoration(prefixText: '${Money.symbol} ', hintText: 'Monthly limit'),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v) ?? 0),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctl.text) ?? 0), child: const Text('Save')),
        ],
      ),
    );
    ctl.dispose();
    if (value == null) return;
    try {
      await ref.read(appDataProvider.notifier).setBudget(stat.category.id, value * 100);
      if (context.mounted) toast(context, 'Budget saved');
    } catch (e) {
      if (context.mounted) toast(context, e.toString());
    }
  }
}
