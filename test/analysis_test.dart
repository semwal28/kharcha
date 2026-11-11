import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/core/money.dart';
import 'package:kharcha/data/models.dart';
import 'package:kharcha/data/sample_data.dart';
import 'package:kharcha/domain/analysis.dart';
import 'package:kharcha/domain/category_guess.dart';

AppData _data(List<Txn> txns, {Map<String, int>? budgets, List<Category> extra = const []}) => AppData(
  categories: [...builtinCategories, ...extra],
  txns: List.of(txns)..sort((a, b) => b.spentAt.compareTo(a.spentAt)),
  budgets: budgets ?? {for (final e in demoBudgetsRupees.entries) e.key: e.value * 100},
  profile: const Profile(monthlyIncomePaise: 6500000),
);

Txn _t(String id, int rupees, String cat, DateTime at, {String? merchant, bool rec = false}) =>
    Txn(id: id, amountPaise: rupees * 100, categoryId: cat, spentAt: at, merchant: merchant, isRecurring: rec);

void main() {
  final now = DateTime(2026, 11, 9, 19, 30);

  group('Money', () {
    test('formats rupees with Indian grouping', () {
      expect(Money.fmt(12500000), '₹1,25,000');
      expect(Money.fmt(25000), '₹250');
      expect(Money.short(250000), '₹2.5k');
      expect(Money.short(80000), '₹800');
    });
    test('day labels', () {
      expect(dayLabel(DateTime(2026, 11, 9, 8), now), 'Today');
      expect(dayLabel(DateTime(2026, 11, 8, 23), now), 'Yesterday');
      expect(dayLabel(DateTime(2026, 11, 6), now), 'Fri, 6 Nov');
    });
  });

  group('analyze', () {
    test('totals, same-day comparison and forecast', () {
      final s = analyze(
        _data([
          _t('a', 1000, 'dining', DateTime(2026, 11, 3)),
          _t('b', 15000, 'rent', DateTime(2026, 11, 1), rec: true),
          _t('c', 500, 'dining', DateTime(2026, 10, 4)),
          _t('d', 700, 'dining', DateTime(2026, 10, 20)),
        ]),
        now,
      );
      expect(s.spent, 1600000);
      expect(s.prevSameTotal, 50000); // only Oct 1-9 counts
      expect(s.prevTotal, 120000);
      // rent is fixed; dining ₹1000 over 9 days -> ₹1000/9*30
      expect(s.projected, closeTo(1500000 + 100000 / 9 * 30, 1));
      expect(s.cats['dining']!.count, 1);
    });

    test('safe to spend uses only the day-to-day budget', () {
      final s = analyze(_data([_t('b', 15000, 'rent', DateTime(2026, 11, 1), rec: true)], budgets: {'rent': 1500000, 'dining': 220000}), now);
      // ₹2,200 day-to-day budget, nothing spent, 22 days left including today
      expect(s.safeToday, closeTo(220000 / 22, 0.01));
    });

    test('finds double charges', () {
      final s = analyze(
        _data([
          _t('a', 486, 'delivery', DateTime(2026, 11, 6, 21, 14), merchant: 'Swiggy'),
          _t('b', 486, 'delivery', DateTime(2026, 11, 6, 21, 16), merchant: 'Swiggy'),
        ]),
        now,
      );
      final dup = s.leaks.firstWhere((l) => l.id.startsWith('dup'));
      expect(dup.oneTimePaise, 48600);
      expect(dup.title, 'Double charge at Swiggy');
    });

    test('finds price rises and overlapping video apps', () {
      final s = analyze(
        _data([
          _t('g1', 1299, 'health', DateTime(2026, 10, 2), merchant: 'cult.fit', rec: true),
          _t('g2', 1499, 'health', DateTime(2026, 11, 2), merchant: 'cult.fit', rec: true),
          _t('n', 649, 'subs', DateTime(2026, 11, 3), merchant: 'Netflix', rec: true),
          _t('h', 299, 'subs', DateTime(2026, 11, 7), merchant: 'JioHotstar', rec: true),
          _t('y', 149, 'subs', DateTime(2026, 10, 10), merchant: 'YouTube Premium', rec: true),
        ]),
        now,
      );
      final hike = s.leaks.firstWhere((l) => l.id == 'hike-cult.fit');
      expect(hike.monthlyPaise, 20000);
      final stream = s.leaks.firstWhere((l) => l.id == 'stream');
      expect(stream.monthlyPaise, 29900 + 14900);
      expect(stream.action, 'Keep Netflix, pause the rest');
    });

    test('sample data produces a useful set of tips', () {
      final s = analyze(_data(generateSampleTxns(now)), now);
      expect(s.leaks.length, greaterThanOrEqualTo(5));
      expect(s.monthlySavings, greaterThan(0));
      expect(s.leaks.map((l) => l.id), containsAll(['stream', 'cafe', 'fees']));
    });

    test('suggested budgets keep fixed costs and trim the rest by 10%', () {
      final s = analyze(_data([_t('r', 15000, 'rent', DateTime(2026, 10, 1), rec: true), _t('d', 3000, 'dining', DateTime(2026, 10, 5))]), now);
      final b = suggestBudgets(s);
      expect(b['rent'], 1500000);
      expect(b['dining'], 270000);
      expect(b.containsKey('fees'), isFalse);
      expect(b.containsKey('shopping'), isFalse); // nothing spent there last month
    });
  });

  group('guessCategory', () {
    final gifts = const Category(id: 'x1', name: 'Gifts');
    final data = _data(const [], extra: [gifts]);
    test('matches common words and brands', () {
      expect(guessCategory('Petrol for bike', data)?.key, 'transport');
      expect(guessCategory('swiggy dinner', data)?.key, 'delivery');
      expect(guessCategory('2 coffees', data)?.key, 'dining');
      expect(guessCategory('electricity bill', data)?.key, 'bills');
    });
    test('prefers the user\'s own categories', () {
      expect(guessCategory('gift for mom', data), gifts);
    });
    test('returns null when unsure', () {
      expect(guessCategory('xyz', data), isNull);
      expect(guessCategory('', data), isNull);
    });
  });
}
