import 'dart:math' as math;

import 'models.dart';

/// Built-in categories. In live mode the ids come from the database;
/// in demo mode the key doubles as the id.
const builtinCategories = <Category>[
  Category(id: 'dining', key: 'dining', name: 'Dining & cafés', icon: 'dining', sortOrder: 10),
  Category(id: 'delivery', key: 'delivery', name: 'Food delivery', icon: 'delivery', sortOrder: 20),
  Category(id: 'groceries', key: 'groceries', name: 'Groceries', icon: 'groceries', sortOrder: 30),
  Category(id: 'transport', key: 'transport', name: 'Transport', icon: 'transport', sortOrder: 40),
  Category(id: 'shopping', key: 'shopping', name: 'Shopping', icon: 'shopping', sortOrder: 50),
  Category(id: 'bills', key: 'bills', name: 'Bills & utilities', icon: 'bills', isFixed: true, sortOrder: 60),
  Category(id: 'fun', key: 'fun', name: 'Entertainment', icon: 'fun', sortOrder: 70),
  Category(id: 'health', key: 'health', name: 'Health & fitness', icon: 'health', sortOrder: 80),
  Category(id: 'care', key: 'care', name: 'Personal care', icon: 'care', sortOrder: 90),
  Category(id: 'subs', key: 'subs', name: 'Subscriptions', icon: 'subs', isFixed: true, sortOrder: 100),
  Category(id: 'rent', key: 'rent', name: 'Rent', icon: 'rent', isFixed: true, sortOrder: 110),
  Category(id: 'fees', key: 'fees', name: 'Fees & charges', icon: 'fees', sortOrder: 120),
  Category(id: 'other', key: 'other', name: 'Other', icon: 'other', sortOrder: 999),
];

const demoBudgetsRupees = <String, int>{
  'rent': 15000,
  'bills': 3500,
  'subs': 1600,
  'delivery': 5000,
  'dining': 2000,
  'groceries': 7000,
  'transport': 9000,
  'shopping': 5000,
  'fun': 1500,
  'health': 2000,
  'care': 1000,
  'other': 1000,
};

PayMethod _defaultPay(String cat, int rupees, String merchant) {
  if (const ['subs', 'fees', 'shopping', 'fun'].contains(cat) || merchant == 'HP Petrol' || merchant == 'DMart') {
    return PayMethod.card;
  }
  if (cat == 'care' || (cat == 'dining' && rupees < 100)) return PayMethod.cash;
  return PayMethod.upi;
}

/// Two months of realistic example spending (last month + this month so far),
/// stable for a given month so screenshots and tests are repeatable.
/// [scale] sizes amounts to the chosen currency (1 = Indian rupees).
List<Txn> generateSampleTxns(DateTime now, {double scale = 1}) {
  final out = <Txn>[];
  var n = 0;
  void add(DateTime d, int h, int mi, num rupees, String merchant, String cat, {bool rec = false, String? note, PayMethod? pay}) {
    final at = DateTime(d.year, d.month, d.day, h, mi);
    if (at.isAfter(now)) return;
    final r = math.max(1, (rupees * scale).round());
    out.add(
      Txn(
        id: 's${n++}',
        amountPaise: r * 100,
        categoryId: cat,
        spentAt: at,
        merchant: merchant,
        note: note,
        pay: pay ?? _defaultPay(cat, r, merchant),
        isRecurring: rec,
      ),
    );
  }

  for (final off in [-1, 0]) {
    final m0 = DateTime(now.year, now.month + off, 1);
    final isCur = off == 0;
    final last = isCur ? now.day : DateTime(m0.year, m0.month + 1, 0).day;
    final rnd = math.Random(m0.year * 100 + m0.month + 7);
    double r(num a, num b) => a + rnd.nextDouble() * (b - a);
    bool p(double prob) => rnd.nextDouble() < prob;
    T pick<T>(List<T> l) => l[rnd.nextInt(l.length)];
    int mi() => rnd.nextInt(59);

    for (var dd = 1; dd <= last; dd++) {
      final d = DateTime(m0.year, m0.month, dd);
      final wk = d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
      final fri = d.weekday == DateTime.friday;
      if (dd == 1) add(d, 9, 5, 15000, 'House rent', 'rent', rec: true, note: 'Rent to landlord');
      if (dd == 2) add(d, 7, 30, isCur ? 1499 : 1299, 'cult.fit', 'health', rec: true, note: 'Gym membership');
      if (dd == 3) add(d, 6, 0, 649, 'Netflix', 'subs', rec: true);
      if (dd == 5) add(d, 11, 20, isCur ? 1960 : 1840, 'Electricity bill', 'bills', rec: true);
      if (dd == 7) add(d, 6, 0, 299, 'JioHotstar', 'subs', rec: true);
      if (dd == 8) add(d, 10, 0, 799, 'Airtel Xstream', 'bills', rec: true, note: 'Broadband');
      if (dd == 10) add(d, 6, 0, 149, 'YouTube Premium', 'subs', rec: true);
      if (dd == 12) add(d, 9, 45, 349, 'Jio recharge', 'bills', rec: true, note: 'Mobile recharge');
      if (dd == 14) add(d, 6, 0, 119, 'Spotify', 'subs', rec: true);
      if (dd == 20) add(d, 6, 0, 299, 'Amazon Prime', 'subs', rec: true);
      if (!isCur && dd == 18) add(d, 0, 5, 590, 'Credit card', 'fees', note: 'Late payment fee');
      if (dd == 15) add(d, 18, 40, isCur ? 2980 : 3240, 'DMart', 'groceries', note: 'Monthly groceries');
      if (!isCur && dd == 23) add(d, 17, 0, 850, 'Salon', 'care', note: 'Haircut');
      if (dd == 4 || dd == 13 || dd == 22) add(d, 8, 50, r(1500, 2000), 'HP Petrol', 'transport', note: 'Petrol');
      if (p(wk || fri ? .75 : .45)) {
        final late = p(.45);
        final h = late ? 22 + rnd.nextInt(2) : (p(.5) ? 13 : 20);
        add(d, h, mi(), r(240, 560) + (wk ? 90 : 0), pick(['Swiggy', 'Zomato']), 'delivery');
      }
      if (wk && p(.35)) add(d, 13, mi(), r(280, 520), pick(['Swiggy', 'Zomato']), 'delivery');
      if (p(wk ? .3 : .65)) {
        if (p(.5)) {
          add(d, 9 + rnd.nextInt(3), mi(), r(220, 340), 'Third Wave Coffee', 'dining');
        } else {
          add(d, 16 + rnd.nextInt(2), mi(), r(40, 90), 'Chai Point', 'dining', note: 'Chai & snacks');
        }
      }
      if (p(.22)) add(d, 18 + rnd.nextInt(3), mi(), r(280, 1400), pick(['Blinkit', 'Zepto', 'BigBasket']), 'groceries');
      if (!wk && p(.7)) add(d, pick([9, 19]), mi(), r(90, 380), pick(['Uber', 'Ola', 'Rapido']), 'transport');
      if (p(wk ? .35 : .1)) {
        final late = p(.6);
        add(d, late ? 21 + rnd.nextInt(3) : 12 + rnd.nextInt(6), mi(), r(399, 2199), pick(['Amazon', 'Myntra', 'Flipkart']), 'shopping');
      }
      if (wk && p(.22)) add(d, 19, mi(), r(450, 1200), pick(['BookMyShow', 'PVR Cinemas']), 'fun');
      if (p(.05)) add(d, 10 + rnd.nextInt(10), mi(), r(180, 900), 'Apollo Pharmacy', 'health');
    }
  }
  // A double charge for the leak finder to catch.
  if (now.day >= 2) {
    final d = DateTime(now.year, now.month, math.min(6, now.day - 1));
    add(d, 21, 14, 486, 'Swiggy', 'delivery');
    add(d, 21, 16, 486, 'Swiggy', 'delivery');
  }
  out.sort((a, b) => b.spentAt.compareTo(a.spentAt));
  return out;
}
