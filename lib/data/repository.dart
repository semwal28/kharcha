import 'models.dart';

/// Everything the app reads and writes. Two implementations:
/// [LocalRepository] (saved on this phone) and [SupabaseRepository] (cloud account).
abstract class ExpenseRepository {
  /// True when data lives only on this phone (no account, no server).
  bool get isLocal;

  /// True while the example data is loaded, so the app can label it.
  bool get hasExampleData;

  /// Categories, the last two months of expenses, budgets and profile.
  Future<AppData> load();

  Future<Txn> addTxn(NewTxn t);

  /// Saves changes to an existing expense (amount, category, note, date, payment).
  Future<Txn> updateTxn(Txn t);
  Future<void> updateTxnCategory(String txnId, String categoryId);
  Future<void> deleteTxn(String txnId);

  /// Creates a custom category, or returns the existing one with that name.
  Future<Category> addCustomCategory(String name);

  Future<void> setBudget(String categoryId, int limitPaise);
  Future<void> setBudgets(Map<String, int> limitsPaise);
  Future<void> setIncome(int paise);

  Future<Goal> addGoal(String name, int targetPaise);
  Future<Goal> updateGoal(Goal goal);
  Future<void> deleteGoal(String id);

  /// Records what each person owes you for a bill you paid.
  Future<List<Split>> addSplits(List<({String person, int amountPaise})> shares, {String? note});
  Future<void> settleSplit(String id, bool settled);
  Future<void> deleteSplit(String id);

  /// Permanently deletes the account (or, on a phone-only setup, all data).
  Future<void> deleteAccount();

  Future<void> signOut();
}

class RepoException implements Exception {
  RepoException(this.message);
  final String message;
  @override
  String toString() => message;
}
