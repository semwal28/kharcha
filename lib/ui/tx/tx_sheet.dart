import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../add/add_expense_sheet.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';

/// Which expense was just added, so its row can flash on Home.
class JustAdded extends Notifier<String?> {
  @override
  String? build() => null;
  void mark(String? id) => state = id;
}

final justAddedProvider = NotifierProvider<JustAdded, String?>(JustAdded.new);

/// One expense row: icon, title, category · time · payment, amount.
class TxTile extends ConsumerWidget {
  const TxTile(this.txn, {super.key, required this.onAddAgain});
  final Txn txn;
  final ValueChanged<AddPrefill> onAddAgain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final data = ref.watch(appDataProvider).requireValue;
    final cat = data.cat(txn.categoryId);
    final isNew = ref.watch(justAddedProvider) == txn.id;
    Widget row = InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => openTxSheet(context, txn, onAddAgain: onAddAgain),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        child: Row(
          children: [
            CatIcon(cat.isCustom ? 'tag' : cat.icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(txn.titleOr(cat.name), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontSize: 14)),
                  const SizedBox(height: 1),
                  Text('${cat.name} · ${hhmm(txn.spentAt)} · ${txn.pay.label}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              Money.inr(txn.amountPaise),
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: k.ink, fontFeatures: kTabular),
            ),
          ],
        ),
      ),
    );
    if (isNew && !reduceMotion(context)) {
      row = row
          .animate()
          .slideX(begin: -.06, end: 0, duration: 500.ms, curve: Curves.easeOutCubic)
          .fadeIn(duration: 300.ms)
          .custom(
            duration: 2200.ms,
            builder: (context, v, child) => DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(k.popSoft, k.popSoft.withValues(alpha: 0), Curves.easeIn.transform(v)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: child,
            ),
          );
    }
    return row;
  }
}

Future<void> openTxSheet(BuildContext context, Txn txn, {required ValueChanged<AddPrefill> onAddAgain}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _TxSheet(txn, onAddAgain: onAddAgain),
);

class _TxSheet extends ConsumerWidget {
  const _TxSheet(this.txn, {required this.onAddAgain});
  final Txn txn;
  final ValueChanged<AddPrefill> onAddAgain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final data = ref.watch(appDataProvider).requireValue;
    final current = data.txns.where((t) => t.id == txn.id).firstOrNull ?? txn;
    final cat = data.cat(current.categoryId);
    final notifier = ref.read(appDataProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(current.titleOr(cat.name), style: context.text.titleLarge),
          const SizedBox(height: 14),
          Row(
            children: [
              CatIcon(cat.isCustom ? 'tag' : cat.icon, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Money.inr(current.amountPaise), style: context.text.displayMedium?.copyWith(fontSize: 28, fontFeatures: kTabular)),
                    Text(
                      '${fmtDay(current.spentAt)} · ${hhmm(current.spentAt)} · ${current.pay.label}${current.isRecurring ? ' · Monthly' : ''}',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Category', style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: cat.id,
            isExpanded: true,
            items: [for (final c in data.categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
            onChanged: (id) async {
              if (id == null || id == current.categoryId) return;
              try {
                await notifier.changeCategory(current.id, id);
                if (context.mounted) toast(context, 'Category updated');
              } catch (e) {
                if (context.mounted) toast(context, e.toString());
              }
            },
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    // The detail sheet closes first, so open the editor from the app's navigator.
                    final navContext = Navigator.of(context).context;
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(context);
                    final result = await openEditSheet(navContext, current);
                    if (result != null) messenger.showSnackBar(SnackBar(content: Text('Saved ${Money.inr(result.amountPaise)} · ${result.categoryName}')));
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    foregroundColor: k.ink,
                    side: BorderSide(color: k.line),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onAddAgain(AddPrefill(amountPaise: current.amountPaise, categoryId: current.categoryId, note: current.titleOr(cat.name), pay: current.pay));
                  },
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: const Text('Add again'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    foregroundColor: k.ink,
                    side: BorderSide(color: k.line),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(context);
                    try {
                      await notifier.deleteTxn(current.id);
                      messenger.showSnackBar(const SnackBar(content: Text('Expense deleted')));
                    } catch (e) {
                      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
                    }
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Delete'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: k.badSoft, foregroundColor: k.bad),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
