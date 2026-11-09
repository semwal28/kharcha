import 'models.dart';
import 'repository.dart';
import 'sample_data.dart';

/// In-memory store with two months of example spending. Used when the app
/// is started without Supabase keys, and in tests.
class DemoRepository implements ExpenseRepository {
  DemoRepository({DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    reset();
  }

  final DateTime Function() _clock;
  late List<Category> _cats;
  late List<Txn> _txns;
  late Map<String, int> _budgets;
  late Profile _profile;
  var _seq = 0;

  void reset() {
    _cats = List.of(builtinCategories);
    _txns = generateSampleTxns(_clock());
    _budgets = {for (final e in demoBudgetsRupees.entries) e.key: e.value * 100};
    _profile = const Profile(monthlyIncomePaise: 6500000, displayName: 'Demo');
  }

  @override
  bool get isDemo => true;

  @override
  Future<AppData> load() async => AppData(categories: List.of(_cats), txns: List.of(_txns), budgets: Map.of(_budgets), profile: _profile);

  @override
  Future<Txn> addTxn(NewTxn t) async {
    final txn = Txn(
      id: 'u${_seq++}-${_clock().microsecondsSinceEpoch}',
      amountPaise: t.amountPaise,
      categoryId: t.categoryId,
      spentAt: t.spentAt,
      note: t.note,
      merchant: t.note,
      pay: t.pay,
    );
    _txns = [txn, ..._txns]..sort((a, b) => b.spentAt.compareTo(a.spentAt));
    return txn;
  }

  @override
  Future<void> updateTxnCategory(String txnId, String categoryId) async {
    _txns = [for (final t in _txns) t.id == txnId ? t.copyWith(categoryId: categoryId) : t];
  }

  @override
  Future<void> deleteTxn(String txnId) async => _txns.removeWhere((t) => t.id == txnId);

  @override
  Future<Category> addCustomCategory(String name) async {
    final clean = name.trim();
    final existing = _cats.where((c) => c.name.toLowerCase() == clean.toLowerCase() || c.shortName.toLowerCase() == clean.toLowerCase());
    if (existing.isNotEmpty) return existing.first;
    final c = Category(id: 'c${_seq++}', name: clean, icon: 'tag');
    _cats = [..._cats, c];
    return c;
  }

  @override
  Future<void> setBudget(String categoryId, int limitPaise) async => _budgets[categoryId] = limitPaise;

  @override
  Future<void> setBudgets(Map<String, int> limitsPaise) async => _budgets = Map.of(limitsPaise);

  @override
  Future<void> setIncome(int paise) async => _profile = _profile.copyWith(monthlyIncomePaise: paise);

  @override
  Future<void> signOut() async => reset();
}
