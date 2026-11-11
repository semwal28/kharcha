import 'package:flutter/material.dart' hide Split;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../../domain/recurring.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../widgets/success_burst.dart';

/// Shown in place of goals and splits when the server needs the newer
/// database update.
class ExtrasMissingCard extends StatelessWidget {
  const ExtrasMissingCard({super.key});

  @override
  Widget build(BuildContext context) => KCard(
    color: context.k.warnSoft,
    child: Row(
      children: [
        Icon(Icons.build_circle_outlined, color: context.k.warn),
        const SizedBox(width: 12),
        Expanded(child: Text('Goals and bill splits need a quick database update. See the README.', style: context.text.bodyMedium)),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Savings goals

class GoalsSection extends ConsumerWidget {
  const GoalsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(appDataProvider).requireValue.goals;
    final k = context.k;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Savings goals', trailing: LinkButton('+ New goal', onTap: () => _newGoal(context, ref))),
        const SizedBox(height: 10),
        if (goals.isEmpty)
          KCard(
            child: InkWell(
              onTap: () => _newGoal(context, ref),
              child: Row(
                children: [
                  Ring(
                    fraction: 0,
                    size: 48,
                    stroke: 6,
                    track: k.surface2,
                    color: k.accent,
                    child: Icon(Icons.flag_outlined, color: k.ink2, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Save for something', style: context.text.titleSmall),
                        Text('A trip, a phone, a rainy-day fund', style: context.text.bodySmall),
                      ],
                    ),
                  ),
                  Icon(Icons.add_circle_outline, color: k.accent),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 176,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: goals.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => Enter(
                index: i,
                child: _GoalCard(goal: goals[i]),
              ),
            ),
          ),
      ],
    );
  }

  static Future<void> _newGoal(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<(String, int)>(context: context, isScrollControlled: true, builder: (ctx) => const _GoalForm());
    if (result == null) return;
    try {
      await ref.read(appDataProvider.notifier).addGoal(result.$1, result.$2);
      if (context.mounted) toast(context, 'Goal added');
    } catch (e) {
      if (context.mounted) toast(context, e.toString());
    }
  }
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final g = goal;
    return Squish(
      child: SizedBox(
        width: 148,
        child: Material(
          color: k.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: k.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => _GoalDetail(goalId: g.id),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Ring(
                    fraction: g.progress,
                    size: 72,
                    stroke: 8,
                    track: k.surface2,
                    color: g.reached ? k.good : k.accent,
                    child: g.reached
                        ? Icon(Icons.check_rounded, color: k.good, size: 28)
                        : CountUp(
                            value: g.progress * 100,
                            format: (v) => '${v.round()}%',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                  ),
                  const Spacer(),
                  Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    g.reached ? 'Reached ${Money.short(g.targetPaise)}' : '${Money.short(g.savedPaise)} of ${Money.short(g.targetPaise)}',
                    style: context.text.bodySmall?.copyWith(fontFeatures: kTabular),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalForm extends StatefulWidget {
  const _GoalForm();

  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  final _name = TextEditingController();
  final _target = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final target = int.tryParse(_target.text) ?? 0;
    if (name.isEmpty || target <= 0) {
      HapticFeedback.heavyImpact();
      return;
    }
    Navigator.pop(context, (name, Money.fromMajor(target)));
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New goal', style: context.text.titleLarge),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'What for?', hintText: 'e.g. Goa trip', counterText: ''),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _target,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
            decoration: InputDecoration(labelText: 'Target', prefixText: '${Money.symbol} '),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: k.accent,
              foregroundColor: k.accentInk,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Add goal'),
          ),
        ],
      ),
    );
  }
}

class _GoalDetail extends ConsumerStatefulWidget {
  const _GoalDetail({required this.goalId});
  final String goalId;

  @override
  ConsumerState<_GoalDetail> createState() => _GoalDetailState();
}

class _GoalDetailState extends ConsumerState<_GoalDetail> {
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _move(Goal g, {required bool add}) async {
    final v = Money.fromMajor(int.tryParse(_amount.text) ?? 0);
    if (v <= 0) {
      HapticFeedback.heavyImpact();
      return;
    }
    final saved = add ? g.savedPaise + v : (g.savedPaise - v).clamp(0, g.savedPaise);
    final updated = g.copyWith(savedPaise: saved);
    _amount.clear();
    HapticFeedback.mediumImpact();
    try {
      await ref.read(appDataProvider.notifier).updateGoal(updated);
      if (!mounted) return;
      if (!g.reached && updated.reached) {
        await showSuccessBurst(context, amount: Money.fmt(updated.targetPaise), subtitle: 'Goal reached: ${g.name}');
      }
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _delete(Goal g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${g.name}"?'),
        content: const Text('This only removes the goal. Your expenses stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.pop(context);
    try {
      await ref.read(appDataProvider.notifier).deleteGoal(g.id);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final g = ref.watch(appDataProvider).value?.goals.where((x) => x.id == widget.goalId).firstOrNull;
    if (g == null) return const SizedBox(height: 120);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(g.name, style: context.text.titleLarge)),
              IconButton(
                tooltip: 'Delete goal',
                onPressed: () => _delete(g),
                icon: Icon(Icons.delete_outline, color: k.ink2),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Ring(
            fraction: g.progress,
            size: 132,
            stroke: 12,
            track: k.surface2,
            color: g.reached ? k.good : k.accent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CountUp(
                  value: g.savedPaise.toDouble(),
                  format: Money.short,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                Text('of ${Money.short(g.targetPaise)}', style: context.text.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              g.reached ? 'Goal reached. Well done!' : '${Money.fmt(g.leftPaise)} to go',
              key: ValueKey(g.reached),
              style: TextStyle(fontWeight: FontWeight.w600, color: g.reached ? k.good : k.ink2),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
            decoration: InputDecoration(labelText: 'Amount', prefixText: '${Money.symbol} '),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _move(g, add: false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Take out'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => _move(g, add: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: k.accent,
                    foregroundColor: k.accentInk,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Add money'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bill splits

class OwedSection extends ConsumerWidget {
  const OwedSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final splits = ref.watch(appDataProvider).requireValue.splits;
    final open = splits.where((s) => !s.settled).toList();
    final settled = splits.where((s) => s.settled).take(5).toList();
    if (splits.isEmpty) return const SizedBox.shrink();
    final k = context.k;
    final total = open.fold(0, (a, s) => a + s.amountPaise);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Owed to you',
          trailing: Text(
            open.isEmpty ? 'All settled' : Money.fmt(total),
            style: TextStyle(fontWeight: FontWeight.w700, color: open.isEmpty ? k.good : k.accent, fontFeatures: kTabular),
          ),
        ),
        const SizedBox(height: 10),
        KCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              for (final (i, s) in [...open, ...settled].indexed) ...[if (i > 0) Divider(height: 1, color: k.line), _SplitRow(split: s)],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text('Tap the circle when they pay you back', style: context.text.bodySmall),
      ],
    );
  }
}

class _SplitRow extends ConsumerWidget {
  const _SplitRow({required this.split});
  final Split split;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final s = split;
    final initial = s.person.characters.first.toUpperCase();
    return Dismissible(
      key: ValueKey('split-${s.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 8),
        child: Icon(Icons.delete_outline, color: k.bad),
      ),
      onDismissed: (_) => ref.read(appDataProvider.notifier).deleteSplit(s.id).catchError((_) {}),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: s.settled ? k.surface2 : k.popSoft,
              child: Text(
                initial,
                style: TextStyle(fontWeight: FontWeight.w700, color: s.settled ? k.muted : k.popInk),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.person,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: s.settled ? k.muted : k.ink,
                      decoration: s.settled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text('${s.note ?? 'Bill'} · ${dayLabel(s.createdAt, DateTime.now())}', style: context.text.bodySmall),
                ],
              ),
            ),
            Text(
              Money.fmt(s.amountPaise),
              style: TextStyle(fontWeight: FontWeight.w700, fontFeatures: kTabular, color: s.settled ? k.muted : k.ink),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: s.settled ? 'Mark as not paid' : 'Mark as paid back',
              onPressed: () {
                HapticFeedback.selectionClick();
                ref.read(appDataProvider.notifier).settleSplit(s.id, !s.settled).catchError((_) {});
              },
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Icon(
                  s.settled ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                  key: ValueKey(s.settled),
                  color: s.settled ? k.good : k.ink2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Repeats monthly

class RepeatsSection extends ConsumerWidget {
  const RepeatsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).requireValue;
    final latest = <String, Txn>{};
    for (final t in data.txns.where((t) => t.isRecurring)) {
      latest.putIfAbsent(seriesKey(t), () => t); // txns are newest first
    }
    if (latest.isEmpty) return const SizedBox.shrink();
    final k = context.k;
    final items = latest.values.toList()..sort((a, b) => a.spentAt.day.compareTo(b.spentAt.day));
    final total = items.fold(0, (a, t) => a + t.amountPaise);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Repeats monthly',
          trailing: Text(
            '${Money.fmt(total)}/mo',
            style: TextStyle(fontWeight: FontWeight.w700, fontFeatures: kTabular, color: k.ink2),
          ),
        ),
        const SizedBox(height: 10),
        KCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              for (final (i, t) in items.indexed) ...[
                if (i > 0) Divider(height: 1, color: k.line),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      CatIcon(data.cat(t.categoryId).isCustom ? 'tag' : data.cat(t.categoryId).icon),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.titleOr(data.cat(t.categoryId).name), style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text('Every month on the ${_ordinal(t.spentAt.day)}', style: context.text.bodySmall),
                          ],
                        ),
                      ),
                      Text(
                        Money.fmt(t.amountPaise),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: kTabular),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Stop repeating',
                        onPressed: () => _stop(context, ref, data, t),
                        icon: Icon(Icons.close_rounded, size: 20, color: k.ink2),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text('Added for you on the day each month', style: context.text.bodySmall),
      ],
    );
  }

  static String _ordinal(int d) {
    if (d >= 11 && d <= 13) return '${d}th';
    return switch (d % 10) {
      1 => '${d}st',
      2 => '${d}nd',
      3 => '${d}rd',
      _ => '${d}th',
    };
  }

  static Future<void> _stop(BuildContext context, WidgetRef ref, AppData data, Txn t) async {
    final key = seriesKey(t);
    final series = data.txns.where((x) => x.isRecurring && seriesKey(x) == key).toList();
    try {
      final notifier = ref.read(appDataProvider.notifier);
      for (final x in series) {
        await notifier.updateTxn(x.copyWith(isRecurring: false));
      }
      if (context.mounted) toast(context, 'Stopped. Past entries stay.');
    } catch (e) {
      if (context.mounted) toast(context, e.toString());
    }
  }
}
