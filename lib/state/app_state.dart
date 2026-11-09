import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../domain/analysis.dart';
import '../services/ai_coach.dart';

/// Overridden in main() with the demo or Supabase implementation.
final repositoryProvider = Provider<ExpenseRepository>((ref) => throw UnimplementedError('repositoryProvider'));
final aiCoachProvider = Provider<AiCoach>((ref) => OfflineAiCoach());

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

  @override
  Future<AppData> build() => _repo.load();

  AppData get _data => state.requireValue;

  Future<void> refresh() async {
    state = await AsyncValue.guard(_repo.load);
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
    final input = NewTxn(amountPaise: t.amountPaise, categoryId: categoryId, spentAt: t.spentAt, note: t.note, pay: t.pay);
    final tempId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    final temp = Txn(
      id: tempId,
      amountPaise: input.amountPaise,
      categoryId: categoryId,
      spentAt: input.spentAt,
      note: input.note,
      merchant: input.note,
      pay: input.pay,
    );
    return _optimistic<Txn>(
      _data.copyWith(txns: [temp, ..._data.txns]),
      () => _repo.addTxn(input),
      apply: (saved) => _data.copyWith(txns: [for (final x in _data.txns) x.id == tempId ? saved : x]),
    );
  }

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
