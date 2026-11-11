import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/data/local_repository.dart';
import 'package:kharcha/main.dart';
import 'package:kharcha/state/app_state.dart';
import 'package:kharcha/ui/budgets/budgets_screen.dart';
import 'package:kharcha/ui/shell.dart';
import 'package:kharcha/ui/tx/tx_sheet.dart';

DateTime _clock() => DateTime(2026, 11, 9, 19, 30);

Future<LocalRepository> _start(WidgetTester tester, {bool example = true}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = LocalRepository(clock: _clock, exampleOnFirstRun: example);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo), clockProvider.overrideWithValue(_clock)],
      child: const SpendwellApp(home: AppShell()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  return repo;
}

/// Lets entrance animations, the success burst and the highlight timer finish.
Future<void> _settle(WidgetTester tester, [int seconds = 4]) async {
  for (var i = 0; i < seconds * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _type(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.byKey(ValueKey('key-$d')));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('home shows the month, tips and recent spends', (tester) async {
    await _start(tester);
    expect(find.text('SPENT IN NOVEMBER'), findsOneWidget);
    expect(find.text('Quick add'), findsOneWidget);
    expect(find.text('Smart tip'), findsOneWidget);
    expect(find.text('Where it went'), findsOneWidget);
    await _settle(tester, 2);
  });

  testWidgets('a new install starts at 0 with no budget', (tester) async {
    await _start(tester, example: false);
    expect(find.text('No budget yet · set one in Plan'), findsOneWidget);
    expect(find.text('Set a budget'), findsOneWidget);
    expect(find.text('No expenses yet'), findsOneWidget);
    await tester.tap(find.text('Plan'));
    await _settle(tester, 2);
    expect(find.text('Suggested budgets'), findsNothing);
    expect(find.text('No budget'), findsWidgets);
  });

  testWidgets('add an expense: note auto-picks the category', (tester) async {
    final repo = await _start(tester);
    await tester.tap(find.text('Add'));
    await _settle(tester, 1);

    await tester.enterText(find.byType(TextField).first, 'Petrol for bike');
    await tester.pump();
    await _type(tester, '250');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Add ₹250 · Transport'), findsOneWidget);
    expect(find.text('Auto-picked'), findsOneWidget);

    await tester.tap(find.text('Add ₹250 · Transport'));
    await _settle(tester);

    final data = await repo.load();
    final added = data.txns.firstWhere((t) => t.note == 'Petrol for bike');
    expect(added.amountPaise, 25000);
    expect(data.cat(added.categoryId).key, 'transport');
    // Shown at the top of Recent on Home.
    await tester.dragUntilVisible(find.text('Petrol for bike'), find.byKey(const ValueKey('home-list')), const Offset(0, -300));
    expect(find.text('Petrol for bike'), findsWidgets);
    await _settle(tester, 2);
  });

  testWidgets('Other with a name creates a new category', (tester) async {
    final repo = await _start(tester);
    await tester.tap(find.text('Add'));
    await _settle(tester, 1);

    await tester.tap(find.byKey(const ValueKey('cat-other')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField).at(1), 'gifts');
    await _type(tester, '999');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Add ₹999 · Gifts'), findsOneWidget);

    await tester.tap(find.text('Add ₹999 · Gifts'));
    await _settle(tester);

    final data = await repo.load();
    final gifts = data.categories.where((c) => c.name == 'Gifts');
    expect(gifts, hasLength(1));
    expect(gifts.single.isCustom, isTrue);
    expect(data.txns.any((t) => t.categoryId == gifts.single.id && t.amountPaise == 99900), isTrue);
  });

  testWidgets('tabs open Insights, Plan and Ask AI', (tester) async {
    await _start(tester);
    await tester.tap(find.text('Insights'));
    await _settle(tester, 2);
    expect(find.text('YOU COULD SAVE'), findsOneWidget);
    expect(find.text('Where to save'), findsOneWidget);

    await tester.tap(find.text('Plan'));
    await _settle(tester, 2);
    expect(find.text('Savings goals'), findsOneWidget);
    expect(find.text('Goa trip'), findsOneWidget);
    expect(find.text('Owed to you'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Suggested budgets'),
      300,
      scrollable: find.descendant(of: find.byType(BudgetsScreen), matching: find.byType(Scrollable)).first,
    );
    expect(find.text('Suggested budgets'), findsOneWidget);

    await tester.tap(find.text('Ask AI'));
    await _settle(tester, 1);
    await tester.tap(find.text('Food delivery spend?'));
    await _settle(tester, 1);
    expect(find.textContaining('Food delivery: ₹'), findsOneWidget); // offline answer in demo mode
  });

  testWidgets('edit an expense from its detail sheet', (tester) async {
    final repo = await _start(tester);
    await tester.tap(find.text('Add'));
    await _settle(tester, 1);
    await tester.enterText(find.byType(TextField).first, 'Team lunch');
    await _type(tester, '400');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Add ₹400 · Dining & cafés'));
    await _settle(tester);

    final row = find.descendant(of: find.byType(TxTile), matching: find.text('Team lunch'));
    await tester.dragUntilVisible(row, find.byKey(const ValueKey('home-list')), const Offset(0, -300));
    await tester.ensureVisible(row);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(row);
    await _settle(tester, 1);
    await tester.tap(find.text('Edit'));
    await _settle(tester, 1);
    expect(find.text('Edit expense'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('key-del')));
    await tester.tap(find.byKey(const ValueKey('key-del')));
    await _type(tester, '50'); // 400 -> 4 -> 450
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Save ₹450 · Dining & cafés'));
    await _settle(tester, 2);

    final data = await repo.load();
    final t = data.txns.where((t) => t.note == 'Team lunch').toList();
    expect(t, hasLength(1));
    expect(t.single.amountPaise, 45000);
  });

  testWidgets('theme switch: Dark, then Light, then Auto', (tester) async {
    await _start(tester);
    await tester.tap(find.byTooltip('Settings'));
    await _settle(tester, 1);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);

    for (final (label, mode, brightness) in [('Dark', ThemeMode.dark, Brightness.dark), ('Light', ThemeMode.light, Brightness.light)]) {
      await tester.tap(find.text(label));
      await _settle(tester, 1);
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, mode);
      expect(Theme.of(tester.element(find.text('Settings'))).brightness, brightness);
    }
    await tester.tap(find.text('Auto'));
    await _settle(tester, 1);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.system);
  });

  testWidgets('swipe an expense away, then undo', (tester) async {
    final repo = await _start(tester);
    await tester.tap(find.text('Add'));
    await _settle(tester, 1);
    await tester.enterText(find.byType(TextField).first, 'Movie night');
    await _type(tester, '600');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Add ₹600 · Entertainment'));
    await _settle(tester);

    final row = find.descendant(of: find.byType(TxTile), matching: find.text('Movie night'));
    await tester.dragUntilVisible(row, find.byKey(const ValueKey('home-list')), const Offset(0, -300));
    await tester.ensureVisible(row);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(row, const Offset(-500, 0));
    await _settle(tester, 1);
    expect((await repo.load()).txns.any((t) => t.note == 'Movie night'), isFalse);

    await tester.tap(find.text('Undo'));
    await _settle(tester, 1);
    expect((await repo.load()).txns.where((t) => t.note == 'Movie night'), hasLength(1));
    await _settle(tester, 3);
  });

  testWidgets('split a bill: you keep your share, friends owe the rest', (tester) async {
    final repo = await _start(tester);
    await tester.tap(find.text('Add'));
    await _settle(tester, 1);
    await tester.enterText(find.byType(TextField).first, 'Pizza with friends');
    await _type(tester, '900');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('Split this bill'));
    await tester.tap(find.text('Split this bill'));
    await _settle(tester, 1);
    await tester.enterText(find.widgetWithText(TextField, 'Split with, e.g. Rahul, Priya'), 'Asha, Ben');
    await tester.pump();
    expect(find.text('You pay ₹300 · each owes you ₹300'), findsOneWidget);
    final add = find.textContaining('Add ₹900');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await _settle(tester);
    final data = await repo.load();
    expect(data.txns.any((t) => t.amountPaise == 30000 && t.note == 'Pizza with friends'), isTrue);
    expect(data.splits.where((s) => s.note == 'Pizza with friends').map((s) => (s.person, s.amountPaise)), unorderedEquals([('Asha', 30000), ('Ben', 30000)]));
  });

  testWidgets('add money to a goal', (tester) async {
    final repo = await _start(tester);
    await tester.tap(find.text('Plan'));
    await _settle(tester, 2);
    await tester.tap(find.text('Goa trip'));
    await _settle(tester, 1);
    expect(find.text('₹11,500 to go'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '1500');
    await tester.tap(find.text('Add money'));
    await _settle(tester, 2);
    expect(find.text('₹10,000 to go'), findsOneWidget);
    expect((await repo.load()).goals.single.savedPaise, 1000000);
  });

  testWidgets('monthly report opens from Insights', (tester) async {
    await _start(tester);
    await tester.tap(find.text('Insights'));
    await _settle(tester, 2);
    await tester.tap(find.text('Monthly report'));
    await _settle(tester, 2);
    expect(find.text('NOVEMBER 2026'), findsOneWidget);
    expect(find.text('Share as picture'), findsOneWidget);
    await tester.tap(find.text('Last month'));
    await _settle(tester, 2);
    expect(find.text('OCTOBER 2026'), findsOneWidget);
  });
}
