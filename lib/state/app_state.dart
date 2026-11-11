import 'dart:ui' show VoidCallback;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_prefs.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../domain/analysis.dart';
import '../domain/recurring.dart';
import '../services/ai_coach.dart';

/// Overridden in main() with the demo or Supabase implementation.
final repositoryProvider = Provider<ExpenseRepository>((ref) => throw UnimplementedError('repositoryProvider'));
final aiCoachProvider = Provider<AiCoach>((ref) => OfflineAiCoach());

/// Set in "use without an account" mode: leaves it, back to sign-in.
final exitGuestProvider = Provider<VoidCallback?>((ref) => null);

/// Injectable clock so tests and screenshots are stable.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final appDataProvider = AsyncNotifierProvider<AppDataNotifier, AppData>(AppDataNotifier.new);

/// This month's numbers, tips and forecast. Recomputed when data changes.
final summaryProvider = Provider<MonthSummary?>((ref) {
  final data = ref.watch(appDataProvider).value;
  if (data == null) return null;
  return analyze(data, ref.watch(clockProvider)());
});

/// Holds all user data. Writes update the screen at once, then save in the
/// background; on failure the change is rolled back and the error rethrown.
class AppDataNotifier extends AsyncNotifier<AppData> {
  ExpenseRepository get _repo => ref.read(repositoryProvider);

  /// Names of monthly expenses added automatically on the last load, so the
  /// app can say so once.
  List<String> autoAdded = const [];

  @override
  Future<AppData> build() => _loadWithRecurring();

  /// Loads data, then adds any "repeats monthly" expenses that are due.
  /// Each one is added at most once per month, even if the copy is deleted.
  Future<AppData> _loadWithRecurring() async {
    var data = await _repo.load();
    final ledger = AppPrefs.getList(AppPrefs.recurringAdded).toSet();
    final due = dueRecurring(data, ref.read(clockProvider)(), ledger);
    if (due.isEmpty) return data;
    final added = <String>[];
    for (final d in due) {
      try {
        await _repo.addTxn(d.txn);
        added.add(d.label);
        ledger.add(d.ledgerKey);
      } catch (_) {
        // Try again on the next launch.
      }
    }
    final keep = ledger.toList();
    await AppPrefs.setList(AppPrefs.recurringAdded, keep.length > 300 ? keep.sublist(keep.length - 300) : keep);
    autoAdded = added;
    return added.isEmpty ? data : await _repo.load();
  }

  AppData get _data => state.requireValue;

  Future<void> refresh() async {
    state = await AsyncValue.guard(_loadWithRecurring);
  }

  Future<T> _optimistic<T>(AppData next, Future<T> Function() save, {AppData Function(T result)? apply}) async {
    final before = _data;
    state = AsyncData(next);
    try {
      final result = await save();
      if (apply != null) state = AsyncData(apply(result));
      return result;
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }

  /// Adds an expense. If [newCategoryName] is set, creates that custom
  /// category first (the "Other → name it" flow).
  Future<Txn> addTxn(NewTxn t, {String? newCategoryName}) async {
    var categoryId = t.categoryId;
    if (newCategoryName != null && newCategoryName.trim().isNotEmpty) {
      final cat = await _repo.addCustomCategory(newCategoryName);
      categoryId = cat.id;
      if (!_data.categories.any((c) => c.id == cat.id)) {
        state = AsyncData(_data.copyWith(categories: [..._data.categories, cat]));
      }
    }
    final input = NewTxn(amountPaise: t.amountPaise, categoryId: categoryId, spentAt: t.spentAt, note: t.note, pay: t.pay, isRecurring: t.isRecurring);
    final tempId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    final temp = Txn(
      id: tempId,
      amountPaise: input.amountPaise,
      categoryId: categoryId,
      spentAt: input.spentAt,
      note: input.note,
      merchant: input.note,
      pay: input.pay,
      isRecurring: input.isRecurring,
    );
    return _optimistic<Txn>(
      _data.copyWith(txns: [temp, ..._data.txns]),
      () => _repo.addTxn(input),
      apply: (saved) => _data.copyWith(txns: [for (final x in _data.txns) x.id == tempId ? saved : x]),
    );
  }

  /// Saves an edited expense. [newCategoryName] works as in [addTxn].
  Future<Txn> updateTxn(Txn updated, {String? newCategoryName}) async {
    var t = updated;
    if (newCategoryName != null && newCategoryName.trim().isNotEmpty) {
      final cat = await _repo.addCustomCategory(newCategoryName);
      t = t.copyWith(categoryId: cat.id);
      if (!_data.categories.any((c) => c.id == cat.id)) {
        state = AsyncData(_data.copyWith(categories: [..._data.categories, cat]));
      }
    }
    return _optimistic<Txn>(
      _data.copyWith(txns: [for (final x in _data.txns) x.id == t.id ? t : x]),
      () => _repo.updateTxn(t),
      apply: (saved) => _data.copyWith(txns: [for (final x in _data.txns) x.id == saved.id ? saved : x]),
    );
  }

  /// Puts back an expense that was just deleted (the Undo button).
  Future<Txn> restoreTxn(Txn t) => addTxn(
    NewTxn(amountPaise: t.amountPaise, categoryId: t.categoryId, spentAt: t.spentAt, note: t.note ?? t.merchant, pay: t.pay, isRecurring: t.isRecurring),
  );

  // ---- Savings goals ----

  Future<Goal> addGoal(String name, int targetPaise) async {
    final g = await _repo.addGoal(name, targetPaise);
    state = AsyncData(_data.copyWith(goals: [..._data.goals, g]));
    return g;
  }

  Future<Goal> updateGoal(Goal goal) =>
      _optimistic<Goal>(_data.copyWith(goals: [for (final g in _data.goals) g.id == goal.id ? goal : g]), () => _repo.updateGoal(goal));

  Future<void> deleteGoal(String id) => _optimistic(_data.copyWith(goals: _data.goals.where((g) => g.id != id).toList()), () => _repo.deleteGoal(id));

  // ---- Bill splits ----

  Future<void> addSplits(List<({String person, int amountPaise})> shares, {String? note}) async {
    if (shares.isEmpty) return;
    final added = await _repo.addSplits(shares, note: note);
    state = AsyncData(_data.copyWith(splits: [...added, ..._data.splits]));
  }

  Future<void> settleSplit(String id, bool settled) =>
      _optimistic(_data.copyWith(splits: [for (final s in _data.splits) s.id == id ? s.copyWith(settled: settled) : s]), () => _repo.settleSplit(id, settled));

  Future<void> deleteSplit(String id) => _optimistic(_data.copyWith(splits: _data.splits.where((s) => s.id != id).toList()), () => _repo.deleteSplit(id));

  Future<void> changeCategory(String txnId, String categoryId) => _optimistic(
    _data.copyWith(txns: [for (final x in _data.txns) x.id == txnId ? x.copyWith(categoryId: categoryId) : x]),
    () => _repo.updateTxnCategory(txnId, categoryId),
  );

  Future<void> deleteTxn(String txnId) => _optimistic(_data.copyWith(txns: _data.txns.where((x) => x.id != txnId).toList()), () => _repo.deleteTxn(txnId));

  Future<void> setBudget(String categoryId, int paise) =>
      _optimistic(_data.copyWith(budgets: {..._data.budgets, categoryId: paise}), () => _repo.setBudget(categoryId, paise));

  Future<void> setBudgets(Map<String, int> budgets) => _optimistic(_data.copyWith(budgets: {..._data.budgets, ...budgets}), () => _repo.setBudgets(budgets));

  Future<void> setIncome(int paise) => _optimistic(_data.copyWith(profile: _data.profile.copyWith(monthlyIncomePaise: paise)), () => _repo.setIncome(paise));
}
