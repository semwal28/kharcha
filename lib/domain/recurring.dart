import 'dart:math' as math;

import '../core/money.dart';
import '../data/models.dart';

/// One expense that "repeats monthly" and is due to be added this month.
class DueRecurring {
  const DueRecurring(this.ledgerKey, this.txn, this.label);

  /// Remembered after adding, so a deleted copy is not added back.
  final String ledgerKey;
  final NewTxn txn;
  final String label;
}

String seriesKey(Txn t) => '${t.categoryId}|${t.titleOr('').toLowerCase()}';

/// Finds monthly expenses that are due this month but not added yet.
/// A series is due once today has reached the day of the month it last
/// happened on (capped to the month's last day).
List<DueRecurring> dueRecurring(AppData data, DateTime now, Set<String> alreadyAdded) {
  final latest = <String, Txn>{};
  for (final t in data.txns.where((t) => t.isRecurring)) {
    final k = seriesKey(t);
    final seen = latest[k];
    if (seen == null || t.spentAt.isAfter(seen.spentAt)) latest[k] = t;
  }
  final dim = daysInMonth(now.year, now.month);
  final out = <DueRecurring>[];
  for (final e in latest.entries) {
    final t = e.value;
    if (t.spentAt.year == now.year && t.spentAt.month == now.month) continue;
    if (t.spentAt.isAfter(now)) continue;
    final day = math.min(t.spentAt.day, dim);
    final ledgerKey = '${e.key}|${now.year}-${now.month}';
    if (now.day < day || alreadyAdded.contains(ledgerKey)) continue;
    out.add(
      DueRecurring(
        ledgerKey,
        NewTxn(
          amountPaise: t.amountPaise,
          categoryId: t.categoryId,
          spentAt: DateTime(now.year, now.month, day, t.spentAt.hour, t.spentAt.minute),
          note: t.note ?? t.merchant,
          pay: t.pay,
          isRecurring: true,
        ),
        t.titleOr(data.cat(t.categoryId).name),
      ),
    );
  }
  return out;
}

/// Equal shares for a bill you paid and split with [people].
/// You pay what is left after rounding, so shares always add up exactly.
({int yours, List<({String person, int amountPaise})> theirs}) splitEqually(int totalPaise, List<String> people) {
  final names = [
    for (final p in people.map((p) => p.trim()))
      if (p.isNotEmpty) p,
  ];
  if (names.isEmpty) return (yours: totalPaise, theirs: const []);
  final each = totalPaise ~/ (names.length + 1);
  return (yours: totalPaise - each * names.length, theirs: [for (final n in names) (person: n, amountPaise: each)]);
}

/// An in-app alert when an expense pushes a category past 80% or 100% of its budget.
class BudgetAlert {
  const BudgetAlert({required this.category, required this.percent, required this.spentPaise, required this.budgetPaise});
  final Category category;
  final int percent;
  final int spentPaise;
  final int budgetPaise;
  bool get over => spentPaise > budgetPaise;
  String get message =>
      over ? '${category.name} is over budget by ${Money.fmt(spentPaise - budgetPaise)}' : '${category.name} has used $percent% of its budget';
}

BudgetAlert? budgetAlertFor({required Category category, required int beforePaise, required int afterPaise, required int budgetPaise}) {
  if (budgetPaise <= 0) return null;
  for (final threshold in const [1.0, .8]) {
    final line = budgetPaise * threshold;
    if (beforePaise < line && afterPaise >= line) {
      return BudgetAlert(category: category, percent: (afterPaise / budgetPaise * 100).round(), spentPaise: afterPaise, budgetPaise: budgetPaise);
    }
  }
  return null;
}
