import 'models.dart';

/// Everything the app reads and writes. Two implementations:
/// [DemoRepository] (in memory, example data) and [SupabaseRepository] (live).
abstract class ExpenseRepository {
  bool get isDemo;

  /// Categories, the last two months of expenses, budgets and profile.
  Future<AppData> load();

  Future<Txn> addTxn(NewTxn t);
  Future<void> updateTxnCategory(String txnId, String categoryId);
  Future<void> deleteTxn(String txnId);

  /// Creates a custom category, or returns the existing one with that name.
  Future<Category> addCustomCategory(String name);

  Future<void> setBudget(String categoryId, int limitPaise);
  Future<void> setBudgets(Map<String, int> limitsPaise);
  Future<void> setIncome(int paise);

  Future<void> signOut();
}

class RepoException implements Exception {
  RepoException(this.message);
  final String message;
  @override
  String toString() => message;
}
