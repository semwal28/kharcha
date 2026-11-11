import 'dart:math' as math;

import '../core/money.dart';
import '../data/models.dart';

/// Everything shown on the shareable monthly report.
class MonthReport {
  const MonthReport({
    required this.year,
    required this.month,
    required this.total,
    required this.count,
    required this.dailyAverage,
    required this.categories,
    this.biggest,
    this.compareTo,
    this.compareLabel,
  });

  final int year;
  final int month;
  final int total;
  final int count;
  final int dailyAverage;

  /// Top categories, biggest first: (category, amount).
  final List<(Category, int)> categories;
  final Txn? biggest;

  /// Spend in the comparison period, if the app has it.
  final int? compareTo;
  final String? compareLabel;

  String get title => '${monthNames[month - 1]} $year';
  double? get change => compareTo == null || compareTo == 0 ? null : (total - compareTo!) / compareTo!;
}

/// Builds the report for a month. For the current month it counts days so
/// far and compares with the same days of the month before.
MonthReport buildMonthReport(AppData data, DateTime now, {required bool lastMonth}) {
  final start = lastMonth ? DateTime(now.year, now.month - 1, 1) : DateTime(now.year, now.month, 1);
  final inMonth = data.txns.where((t) => t.spentAt.year == start.year && t.spentAt.month == start.month).toList();
  final total = inMonth.fold(0, (s, t) => s + t.amountPaise);
  final days = lastMonth ? daysInMonth(start.year, start.month) : now.day;
  final byCat = <String, int>{};
  for (final t in inMonth) {
    byCat.update(t.categoryId, (v) => v + t.amountPaise, ifAbsent: () => t.amountPaise);
  }
  final cats = byCat.entries.map((e) => (data.cat(e.key), e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
  final biggest = inMonth.where((t) => !t.isRecurring).fold<Txn?>(null, (b, t) => b == null || t.amountPaise > b.amountPaise ? t : b);

  // This month: compare with the same days of last month.
  // Last month: compare with the whole month before it.
  int? compare;
  String? label;
  final prev = DateTime(start.year, start.month - 1, 1);
  final prevTxns = data.txns.where((t) => t.spentAt.year == prev.year && t.spentAt.month == prev.month);
  if (prevTxns.isNotEmpty) {
    compare = prevTxns.where((t) => lastMonth || t.spentAt.day <= now.day).fold<int>(0, (s, t) => s + t.amountPaise);
    label = lastMonth ? 'in ${monthNames[prev.month - 1]}' : 'same days last month';
  }
  return MonthReport(
    year: start.year,
    month: start.month,
    total: total,
    count: inMonth.length,
    dailyAverage: total ~/ math.max(1, days),
    categories: cats.take(4).toList(),
    biggest: biggest,
    compareTo: compare,
    compareLabel: label,
  );
}
