import 'dart:math' as math;

import '../core/money.dart';
import '../data/models.dart';

enum LeakKind { leak, habit, alert }

/// One way to save money, found by rules over the user's own transactions.
class Leak {
  const Leak({
    required this.id,
    required this.kind,
    required this.title,
    required this.detail,
    required this.action,
    this.monthlyPaise = 0,
    this.oneTimePaise = 0,
  });

  final String id;
  final LeakKind kind;
  final String title;
  final String detail;
  final String action;
  final int monthlyPaise;
  final int oneTimePaise;

  String get saveText => monthlyPaise > 0 ? '${Money.inr(monthlyPaise)}/mo' : '${Money.inr(oneTimePaise)} once';
}

class CatStat {
  CatStat(this.category);
  final Category category;
  int spent = 0;
  int prev = 0;
  int prevSame = 0;
  int recExpected = 0;
  int varCur = 0;
  int count = 0;
  int budget = 0;
  double projected = 0;

  bool get overBudget => budget > 0 && spent > budget;
  bool get likelyOver => budget > 0 && !overBudget && projected > budget * 1.05;
}

class DayStat {
  DayStat(this.day);
  final int day;
  int amount = 0;
  int count = 0;
}

class MonthSummary {
  MonthSummary({
    required this.now,
    required this.daysInMonth,
    required this.cur,
    required this.prev,
    required this.cats,
    required this.spent,
    required this.prevSameTotal,
    required this.prevTotal,
    required this.projected,
    required this.totalBudget,
    required this.safeToday,
    required this.daily,
    required this.dailyBudget,
    required this.leaks,
    required this.weekendAvg,
    required this.weekdayAvg,
    required this.lateShare,
    required this.income,
  });

  final DateTime now;
  final int daysInMonth;
  final List<Txn> cur;
  final List<Txn> prev;
  final Map<String, CatStat> cats;
  final int spent;
  final int prevSameTotal;
  final int prevTotal;
  final double projected;
  final int totalBudget;
  final double safeToday;
  final List<DayStat> daily;
  final double dailyBudget;
  final List<Leak> leaks;
  final double weekendAvg;
  final double weekdayAvg;
  final double lateShare;
  final int income;

  int get day => now.day;
  String get monthName => monthNames[now.month - 1];
  String get prevMonthName => monthNames[(now.month + 10) % 12];
  int get monthlySavings => leaks.fold(0, (s, l) => s + l.monthlyPaise);
  int get oneTimeSavings => leaks.fold(0, (s, l) => s + l.oneTimePaise);
  double get budgetUsed => totalBudget > 0 ? spent / totalBudget : 0;
  double get monthProgress => day / daysInMonth;
}

int _sum(Iterable<Txn> t) => t.fold(0, (s, x) => s + x.amountPaise);
bool _inMonth(DateTime d, int y, int m) => d.year == y && d.month == m;

MonthSummary analyze(AppData data, DateTime now) {
  final y = now.year, m = now.month, d = now.day;
  final dim = daysInMonth(y, m);
  final pm = DateTime(y, m - 1, 1);
  final cur = data.txns.where((t) => _inMonth(t.spentAt, y, m)).toList();
  final prev = data.txns.where((t) => _inMonth(t.spentAt, pm.year, pm.month)).toList();
  final prevSame = prev.where((t) => t.spentAt.day <= d).toList();

  final cats = <String, CatStat>{for (final c in data.categories) c.id: CatStat(c)};
  CatStat stat(String id) => cats[id] ?? cats[data.other.id]!;

  final recCur = <String, int>{}, recPrev = <String, int>{};
  for (final t in cur) {
    final s = stat(t.categoryId)
      ..spent += t.amountPaise
      ..count += 1;
    if (t.isRecurring) {
      recCur.update(s.category.id, (v) => v + t.amountPaise, ifAbsent: () => t.amountPaise);
    } else {
      s.varCur += t.amountPaise;
    }
  }
  for (final t in prev) {
    final s = stat(t.categoryId)..prev += t.amountPaise;
    if (t.isRecurring) recPrev.update(s.category.id, (v) => v + t.amountPaise, ifAbsent: () => t.amountPaise);
  }
  for (final t in prevSame) {
    stat(t.categoryId).prevSame += t.amountPaise;
  }
  for (final s in cats.values) {
    s.recExpected = math.max(recCur[s.category.id] ?? 0, recPrev[s.category.id] ?? 0);
    s.projected = s.recExpected + s.varCur / d * dim;
    s.budget = data.budgets[s.category.id] ?? 0;
  }

  final spent = _sum(cur);
  final projected = cats.values.fold<double>(0, (a, s) => a + s.projected);
  final totalBudget = cats.values.fold<int>(0, (a, s) => a + s.budget);
  final fixedExpected = cats.values.fold<int>(0, (a, s) => a + s.recExpected);
  final varSpent = cats.values.fold<int>(0, (a, s) => a + s.varCur);
  final daysLeft = dim - d + 1;
  final safeToday = math.max(0, (totalBudget - fixedExpected - varSpent) / daysLeft).toDouble();

  final daily = [for (var i = 1; i <= dim; i++) DayStat(i)];
  for (final t in cur.where((t) => !t.isRecurring)) {
    daily[t.spentAt.day - 1]
      ..amount += t.amountPaise
      ..count += 1;
  }
  final dailyBudget = math.max(0, (totalBudget - fixedExpected) / dim).toDouble();

  // Weekend vs weekday, day-to-day spend last month.
  var wkS = 0, wkN = 0, wdS = 0, wdN = 0;
  final pdim = daysInMonth(pm.year, pm.month);
  final perDay = List<int>.filled(pdim + 1, 0);
  for (final t in prev.where((t) => !t.isRecurring)) {
    perDay[t.spentAt.day] += t.amountPaise;
  }
  for (var i = 1; i <= pdim; i++) {
    final wd = DateTime(pm.year, pm.month, i).weekday;
    if (wd == DateTime.saturday || wd == DateTime.sunday) {
      wkS += perDay[i];
      wkN++;
    } else {
      wdS += perDay[i];
      wdN++;
    }
  }
  final prevVar = prev.where((t) => !t.isRecurring);
  final late = prevVar.where((t) => t.spentAt.hour >= 21 || t.spentAt.hour < 4);
  final prevVarSum = _sum(prevVar);

  return MonthSummary(
    now: now,
    daysInMonth: dim,
    cur: cur,
    prev: prev,
    cats: cats,
    spent: spent,
    prevSameTotal: _sum(prevSame),
    prevTotal: _sum(prev),
    projected: projected,
    totalBudget: totalBudget,
    safeToday: safeToday,
    daily: daily,
    dailyBudget: dailyBudget,
    leaks: findLeaks(data, cur, prev),
    weekendAvg: wkN > 0 ? wkS / wkN : 0,
    weekdayAvg: wdN > 0 ? wdS / wdN : 0,
    lateShare: prevVarSum > 0 ? _sum(late) / prevVarSum : 0,
    income: data.profile.monthlyIncomePaise,
  );
}

const _videoApps = ['Netflix', 'JioHotstar', 'YouTube Premium', 'Amazon Prime'];

/// Rule-based savings finder. Copy is kept short on purpose.
List<Leak> findLeaks(AppData data, List<Txn> cur, List<Txn> prev) {
  final leaks = <Leak>[];
  String? key(Txn t) => data.keyOf(t.categoryId);

  // Double charges: same merchant, same amount, within 15 minutes.
  final both = [...prev, ...cur]..sort((a, b) => a.spentAt.compareTo(b.spentAt));
  for (var i = 0; i < both.length; i++) {
    for (var j = math.max(0, i - 6); j < i; j++) {
      final a = both[j], b = both[i];
      if (a.isRecurring || a.matchKey.isEmpty) continue;
      if (a.matchKey == b.matchKey && a.amountPaise == b.amountPaise) {
        final gap = b.spentAt.difference(a.spentAt).inMinutes;
        if (gap >= 0 && gap <= 15) {
          leaks.add(
            Leak(
              id: 'dup-${b.id}',
              kind: LeakKind.alert,
              title: 'Double charge at ${a.titleOr('a shop')}',
              detail: '${Money.inr(a.amountPaise)} twice, $gap min apart · ${fmtDay(b.spentAt)}',
              action: 'Ask for a refund',
              oneTimePaise: a.amountPaise,
            ),
          );
        }
      }
    }
  }

  int? lastRecurring(List<Txn> list, String merchant) {
    final hits = list.where((t) => t.isRecurring && t.merchant == merchant).toList()..sort((a, b) => a.spentAt.compareTo(b.spentAt));
    return hits.isEmpty ? null : hits.last.amountPaise;
  }

  // Price rises on subscriptions and memberships.
  final recMerchants = prev.where((t) => t.isRecurring && t.merchant != null && (key(t) == 'subs' || key(t) == 'health')).map((t) => t.merchant!).toSet();
  for (final mer in recMerchants) {
    final p = lastRecurring(prev, mer), c = lastRecurring(cur, mer);
    if (p != null && c != null && c > p) {
      leaks.add(
        Leak(
          id: 'hike-$mer',
          kind: LeakKind.leak,
          title: '$mer price went up',
          detail: '${Money.inr(p)} → ${Money.inr(c)} a month',
          action: 'Ask for the old rate or pay yearly',
          monthlyPaise: c - p,
        ),
      );
    }
  }

  // Too many video apps at once.
  final vids = <(String, int)>[];
  for (final v in _videoApps) {
    final amt = lastRecurring(cur, v) ?? lastRecurring(prev, v);
    if (amt != null) vids.add((v, amt));
  }
  if (vids.length >= 3) {
    final total = vids.fold(0, (s, v) => s + v.$2);
    final top = vids.reduce((a, b) => a.$2 >= b.$2 ? a : b);
    leaks.add(
      Leak(
        id: 'stream',
        kind: LeakKind.leak,
        title: '${vids.length} video apps at once',
        detail: '${Money.inr(total)} a month in total',
        action: 'Keep ${top.$1}, pause the rest',
        monthlyPaise: total - top.$2,
      ),
    );
  }

  // Late-night food delivery.
  bool isLate(Txn t) => t.spentAt.hour >= 22 || t.spentAt.hour < 4;
  final lateFood = prev.where((t) => key(t) == 'delivery' && isLate(t)).toList();
  if (lateFood.length >= 4) {
    final avg = _sum(lateFood) / lateFood.length;
    final cut = (lateFood.length / 2).ceil();
    leaks.add(
      Leak(
        id: 'late-food',
        kind: LeakKind.habit,
        title: 'Late-night food orders',
        detail: '${lateFood.length} after 10 PM last month · ${Money.inr(_sum(lateFood))}',
        action: 'Eat at home on $cut of those nights',
        monthlyPaise: math.max(0, (cut * (avg - 9000)).round()),
      ),
    );
  }

  // Café runs.
  final cafe = prev.where((t) => key(t) == 'dining').toList();
  final cafeSum = _sum(cafe);
  if (cafeSum >= 150000) {
    leaks.add(
      Leak(
        id: 'cafe',
        kind: LeakKind.habit,
        title: 'Café runs',
        detail: '${cafe.length} visits last month · ${Money.inr(cafeSum)}',
        action: 'Make coffee at home 2 days a week',
        monthlyPaise: (cafeSum * 0.35).round(),
      ),
    );
  }

  // Late-night shopping.
  final lateShop = prev.where((t) => key(t) == 'shopping' && t.spentAt.hour >= 21).toList();
  final lateShopSum = _sum(lateShop);
  if (lateShopSum >= 150000) {
    leaks.add(
      Leak(
        id: 'late-shop',
        kind: LeakKind.habit,
        title: 'Late-night shopping',
        detail: '${lateShop.length} orders after 9 PM · ${Money.inr(lateShopSum)}',
        action: 'Wait 24 hours before you buy',
        monthlyPaise: (lateShopSum * 0.4).round(),
      ),
    );
  }

  // Avoidable fees.
  final fees = [...prev, ...cur].where((t) => key(t) == 'fees').toList();
  if (fees.isNotEmpty) {
    leaks.add(
      Leak(
        id: 'fees',
        kind: LeakKind.alert,
        title: 'Late fee paid',
        detail: '${Money.inr(_sum(fees))} in late fees',
        action: 'Turn on auto-pay',
        oneTimePaise: _sum(fees),
      ),
    );
  }

  double weight(Leak l) => l.monthlyPaise > 0 ? l.monthlyPaise.toDouble() : l.oneTimePaise / 3;
  leaks.sort((a, b) => weight(b).compareTo(weight(a)));
  return leaks;
}

/// Suggested budgets: fixed costs as they are, day-to-day 10% below last month.
Map<String, int> suggestBudgets(MonthSummary s) {
  int round100(num paise) => ((paise / 10000).round() * 10000);
  return {
    for (final c in s.cats.values)
      if (c.category.key != 'fees')
        c.category.id: c.category.isFixed
            ? round100(math.max(c.prev, c.recExpected))
            : (c.prev == 0 && c.category.isCustom ? 0 : math.max(50000, round100(c.prev * 0.9))),
  };
}

/// Plain-text snapshot of the month for the AI coach. Sent to the server,
/// never stored.
String aiSummary(MonthSummary s, AppData data, {int maxRows = 220}) {
  final b = StringBuffer()
    ..writeln('Today: ${s.now.toIso8601String().substring(0, 10)}. Monthly take-home income: ${s.income > 0 ? Money.inr(s.income) : 'not set'}. Currency: INR.')
    ..writeln(
      'This month (${s.monthName}, day ${s.day} of ${s.daysInMonth}): spent ${Money.inr(s.spent)}; same date last month ${Money.inr(s.prevSameTotal)}; projected month end ${Money.inr(s.projected)}; total budget ${Money.inr(s.totalBudget)}. Last month total: ${Money.inr(s.prevTotal)}.',
    )
    ..writeln('By category (this month so far | same date last month | last month total | projected | budget):');
  for (final c in s.cats.values) {
    if (c.spent == 0 && c.prev == 0 && c.budget == 0) continue;
    b.writeln(
      '- ${c.category.name}: ${Money.inr(c.spent)} | ${Money.inr(c.prevSame)} | ${Money.inr(c.prev)} | ${Money.inr(c.projected)} | ${c.budget > 0 ? Money.inr(c.budget) : 'none'}',
    );
  }
  b
    ..writeln(
      'Patterns: weekend day avg ${Money.inr(s.weekendAvg)}, weekday avg ${Money.inr(s.weekdayAvg)}; ${(s.lateShare * 100).round()}% of last month day-to-day spend after 9 PM.',
    )
    ..writeln('Rule-based findings:');
  for (final l in s.leaks) {
    b.writeln('- ${l.title}: ${l.detail}');
  }
  b.writeln('Expenses (newest first; date time | description | category | rupees | paid by | recurring?):');
  for (final t in data.txns.take(maxRows)) {
    final c = data.cat(t.categoryId);
    b.writeln(
      '${t.spentAt.toIso8601String().substring(0, 16).replaceFirst('T', ' ')} | ${t.titleOr(c.name)} | ${c.name} | ${(t.amountPaise / 100).round()} | ${t.pay.label}${t.isRecurring ? ' | recurring' : ''}',
    );
  }
  return b.toString();
}
