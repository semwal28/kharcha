import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/data/local_repository.dart';
import 'package:kharcha/data/models.dart';

DateTime _clock() => DateTime(2026, 11, 9, 19, 30);

void main() {
  test('first run starts empty, with every budget at 0', () async {
    final store = MemoryStore();
    final repo = LocalRepository(store: store, clock: _clock);
    final data = await repo.load();
    expect(repo.hasExampleData, isFalse);
    expect(data.txns, isEmpty);
    expect(data.budgets, isEmpty);
    expect(data.goals, isEmpty);
    expect(data.profile.monthlyIncomePaise, 0);
    expect(store.value, isNotNull);
  });

  test('first run can load example data instead', () async {
    final repo = LocalRepository(clock: _clock, exampleOnFirstRun: true);
    final data = await repo.load();
    expect(repo.hasExampleData, isTrue);
    expect(data.txns, isNotEmpty);
    expect(data.budgets, isNotEmpty);
  });

  test('expenses, custom categories, budgets and income survive a restart', () async {
    final store = MemoryStore();
    final repo = LocalRepository(store: store, clock: _clock);
    await repo.startFresh();
    final gifts = await repo.addCustomCategory('Gifts');
    final t = await repo.addTxn(
      NewTxn(amountPaise: 99900, categoryId: gifts.id, spentAt: DateTime(2026, 11, 9, 10), note: 'Gift for mom', pay: PayMethod.card),
    );
    await repo.updateTxn(t.withNote('Gift for Maa').copyWith(amountPaise: 120000));
    await repo.setBudget(gifts.id, 200000);
    await repo.setIncome(6500000);

    final again = LocalRepository(store: store, clock: _clock);
    final data = await again.load();
    expect(again.hasExampleData, isFalse);
    expect(data.categories.where((c) => c.name == 'Gifts'), hasLength(1));
    expect(data.txns, hasLength(1));
    expect(data.txns.single.amountPaise, 120000);
    expect(data.txns.single.titleOr(''), 'Gift for Maa');
    expect(data.txns.single.pay, PayMethod.card);
    expect(data.budgets[gifts.id], 200000);
    expect(data.profile.monthlyIncomePaise, 6500000);
  });

  test('start fresh clears expenses, categories and budgets', () async {
    final repo = LocalRepository(clock: _clock);
    await repo.loadExampleData();
    await repo.addCustomCategory('Pets');
    await repo.startFresh();
    final data = await repo.load();
    expect(data.txns, isEmpty);
    expect(data.categories.any((c) => c.isCustom), isFalse);
    expect(data.budgets, isEmpty);
    expect(data.goals, isEmpty);
    expect(data.splits, isEmpty);
  });

  test('unreadable saved data starts again, empty', () async {
    final store = MemoryStore()..value = '{not json';
    final repo = LocalRepository(store: store, clock: _clock);
    final data = await repo.load();
    expect(repo.hasExampleData, isFalse);
    expect(data.txns, isEmpty);
    expect(data.budgets, isEmpty);
  });
}
