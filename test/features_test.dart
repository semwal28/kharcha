import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/core/money.dart';
import 'package:kharcha/data/models.dart';
import 'package:kharcha/data/sample_data.dart';
import 'package:kharcha/domain/recurring.dart';
import 'package:kharcha/domain/text_parsers.dart';

AppData _data(List<Txn> txns) => AppData(categories: builtinCategories, txns: txns, budgets: const {}, profile: const Profile());

void main() {
  tearDown(() => Money.setCurrency(kCurrencies.first));

  group('bank SMS', () {
    test('UPI debit to a VPA', () {
      final p = parseBankSms('Rs.450.00 debited from A/c XX1234 on 06-11-26 to VPA swiggy@icici (UPI Ref No 512345678901). Not you? Call 1800');
      expect(p!.amountPaise, 45000);
      expect(p.merchant, 'Swiggy');
      expect(p.pay, PayMethod.upi);
      expect(p.isCredit, isFalse);
      expect(p.date, DateTime(2026, 11, 6));
    });
    test('card spend at a shop', () {
      final p = parseBankSms('INR 1,299.00 spent on HDFC Bank Card XX5678 at AMAZON on 2026-11-07:20:13:44.Avl Lmt: INR 45,000');
      expect(p!.amountPaise, 129900);
      expect(p.merchant, 'Amazon');
      expect(p.pay, PayMethod.card);
      expect(p.date, DateTime(2026, 11, 7));
    });
    test('UPI info line', () {
      final p = parseBankSms('Dear Customer, INR 350.00 debited from your a/c XX4321 on 08Nov26. Info: UPI/P2M/412345/ZOMATO LTD. Avl Bal INR 12,345.67');
      expect(p!.amountPaise, 35000);
      expect(p.merchant, 'Zomato Ltd');
      expect(p.date, DateTime(2026, 11, 8));
    });
    test('debit card at a petrol pump', () {
      final p = parseBankSms('You have spent Rs 2,000 at HP PETROL PUMP on 04/11/2026 using your Debit Card ending 4321');
      expect(p!.amountPaise, 200000);
      expect(p.merchant, 'HP Petrol Pump');
      expect(p.pay, PayMethod.card);
    });
    test('money received is flagged as credit', () {
      final p = parseBankSms('Your A/c XX9012 is credited with Rs.25,000.00 on 05-Nov-26 by NEFT from ACME PVT LTD');
      expect(p!.isCredit, isTrue);
      expect(p.date, DateTime(2026, 11, 5));
    });
    test('no amount, no result', () => expect(parseBankSms('Your OTP is 482913. Do not share it.'), isNull));
  });

  group('receipt text', () {
    test('grand total beats subtotal', () {
      final r = parseReceiptText('''
DMART
Avenue Supermarts Ltd
TAX INVOICE
Date: 15/11/2026
Sub Total 2,840.00
CGST 70.00
SGST 70.00
Total Qty 14
GRAND TOTAL 2,980.00
Thank you''');
      expect(r.totalPaise, 298000);
      expect(r.merchant, 'Dmart');
      expect(r.date, DateTime(2026, 11, 15));
    });
    test('amount on the line after the label', () {
      final r = parseReceiptText('Third Wave Coffee\nCappuccino 240.00\nCookie 120.00\nAmount Payable\n378.00');
      expect(r.totalPaise, 37800);
      expect(r.merchant, 'Third Wave Coffee');
    });
    test('falls back to the largest amount', () {
      final r = parseReceiptText('Corner Store\nMilk 56.00\nBread 45.50\nEggs 84.00');
      expect(r.totalPaise, 8400);
    });
  });

  group('repeats monthly', () {
    final now = DateTime(2026, 11, 9, 10);
    final rent = Txn(id: 'r', amountPaise: 1500000, categoryId: 'rent', spentAt: DateTime(2026, 10, 1, 9), merchant: 'House rent', isRecurring: true);
    final gym = Txn(id: 'g', amountPaise: 149900, categoryId: 'health', spentAt: DateTime(2026, 10, 20, 7), merchant: 'cult.fit', isRecurring: true);

    test('adds what is due and skips what is not', () {
      final due = dueRecurring(_data([rent, gym]), now, {});
      expect(due.map((d) => d.label), ['House rent']);
      expect(due.single.txn.spentAt, DateTime(2026, 11, 1, 9));
      expect(due.single.txn.isRecurring, isTrue);
    });
    test('never adds twice in a month', () {
      final first = dueRecurring(_data([rent]), now, {});
      final again = dueRecurring(_data([rent]), now, {first.single.ledgerKey});
      expect(again, isEmpty);
      final copy = Txn(id: 'r2', amountPaise: 1500000, categoryId: 'rent', spentAt: DateTime(2026, 11, 1, 9), merchant: 'House rent', isRecurring: true);
      expect(dueRecurring(_data([rent, copy]), now, {}), isEmpty);
    });
    test('the 31st becomes the last day of a short month', () {
      final t = Txn(id: 'x', amountPaise: 100, categoryId: 'bills', spentAt: DateTime(2026, 10, 31), merchant: 'Rent', isRecurring: true);
      final due = dueRecurring(_data([t]), DateTime(2026, 11, 30, 12), {});
      expect(due.single.txn.spentAt.day, 30);
    });
  });

  group('split and alerts', () {
    test('equal split, rounding stays with you', () {
      final s = splitEqually(100000, ['Rahul', ' Priya ', '']);
      expect(s.theirs.map((t) => t.person), ['Rahul', 'Priya']);
      expect(s.theirs.first.amountPaise, 33333);
      expect(s.yours + s.theirs.fold(0, (a, t) => a + t.amountPaise), 100000);
    });
    test('alerts at 80% and over 100%, once per crossing', () {
      const c = Category(id: 'delivery', key: 'delivery', name: 'Food delivery');
      expect(budgetAlertFor(category: c, beforePaise: 300000, afterPaise: 420000, budgetPaise: 500000)!.percent, 84);
      expect(budgetAlertFor(category: c, beforePaise: 450000, afterPaise: 520000, budgetPaise: 500000)!.over, isTrue);
      expect(budgetAlertFor(category: c, beforePaise: 420000, afterPaise: 430000, budgetPaise: 500000), isNull);
      expect(budgetAlertFor(category: c, beforePaise: 0, afterPaise: 9000, budgetPaise: 0), isNull);
    });
  });

  group('currency', () {
    test('formats in the chosen currency', () {
      Money.setCurrency(currencyByCode('USD'));
      expect(Money.fmt(125000), r'$1,250');
      expect(Money.short(250000), r'$2.5k');
      Money.setCurrency(currencyByCode('EUR'));
      expect(Money.fmt(99900), '€999');
    });
    test('picks a currency from the region', () {
      expect(currencyForCountry('US').code, 'USD');
      expect(currencyForCountry('de').code, 'EUR');
      expect(currencyForCountry('IN').code, 'INR');
      expect(currencyForCountry(null).code, 'INR');
    });
    test('example data is sized to the currency', () {
      final inr = generateSampleTxns(DateTime(2026, 11, 9, 19));
      final usd = generateSampleTxns(DateTime(2026, 11, 9, 19), scale: .05);
      final rentInr = inr.firstWhere((t) => t.categoryId == 'rent').amountPaise;
      final rentUsd = usd.firstWhere((t) => t.categoryId == 'rent').amountPaise;
      expect(rentInr, 1500000);
      expect(rentUsd, 75000);
    });
  });
}
