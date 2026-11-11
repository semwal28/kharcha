import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/money.dart';
import 'models.dart';
import 'repository.dart';
import 'sample_data.dart';

/// Where the phone-only store keeps its JSON. Swappable for tests.
abstract class KeyValueStore {
  Future<String?> read();
  Future<void> write(String? value);
}

class PrefsStore implements KeyValueStore {
  static const _key = 'kharcha.local.v1';
  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_key);
  @override
  Future<void> write(String? value) async {
    final p = await SharedPreferences.getInstance();
    value == null ? await p.remove(_key) : await p.setString(_key, value);
  }
}

/// Keeps nothing between runs. Used in tests.
class MemoryStore implements KeyValueStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? v) async => value = v;
}

/// Phone-only store: works with no account and no internet. Starts empty,
/// with no budgets. Settings can load two months of example data.
class LocalRepository implements ExpenseRepository {
  LocalRepository({KeyValueStore? store, DateTime Function()? clock, this.exampleOnFirstRun = false})
    : _store = store ?? MemoryStore(),
      _clock = clock ?? DateTime.now;

  /// Load example data the very first time instead of starting empty.
  final bool exampleOnFirstRun;

  final KeyValueStore _store;
  final DateTime Function() _clock;
  List<Category> _cats = List.of(builtinCategories);
  List<Txn> _txns = [];
  Map<String, int> _budgets = {};
  Profile _profile = const Profile();
  List<Goal> _goals = [];
  List<Split> _splits = [];
  bool _example = false;
  bool _loaded = false;

  @override
  bool get isLocal => true;

  @override
  bool get hasExampleData => _example;

  Map<String, int> get _exampleBudgets => {for (final e in demoBudgetsRupees.entries) e.key: (e.value * Money.currency.scale).round() * 100};

  /// Two months of example spending (the state a new user sees first).
  Future<void> loadExampleData() async {
    _cats = List.of(builtinCategories);
    _txns = generateSampleTxns(_clock(), scale: Money.currency.scale);
    _budgets = _exampleBudgets;
    _profile = Profile(monthlyIncomePaise: Money.scaled(6500000), displayName: 'Demo');
    final now = _clock();
    _goals = [Goal(id: 'g-demo', name: 'Goa trip', targetPaise: Money.scaled(2000000), savedPaise: Money.scaled(850000))];
    _splits = [Split(id: 's-demo-1', person: 'Rahul', amountPaise: Money.scaled(45000), note: 'Pizza night', createdAt: now.subtract(const Duration(days: 2)))];
    _example = true;
    await _save();
  }

  /// Clears everything: expenses, custom categories, budgets, income, goals
  /// and splits. Every budget is back to 0 (not set).
  Future<void> startFresh() async {
    _cats = List.of(builtinCategories);
    _txns = [];
    _budgets = {};
    _profile = const Profile();
    _goals = [];
    _splits = [];
    _example = false;
    await _save();
  }

  Future<void> _save() => _store.write(
    jsonEncode({
      'v': 1,
      'example': _example,
      'income': _profile.monthlyIncomePaise,
      'categories': [
        for (final c in _cats.where((c) => c.isCustom)) {'id': c.id, 'name': c.name},
      ],
      'budgets': _budgets,
      'txns': [
        for (final t in _txns)
          {
            'id': t.id,
            'a': t.amountPaise,
            'c': t.categoryId,
            't': t.spentAt.toIso8601String(),
            if (t.note != null) 'n': t.note,
            if (t.merchant != null) 'm': t.merchant,
            'p': t.pay.label,
            if (t.isRecurring) 'r': true,
          },
      ],
      'goals': [
        for (final g in _goals) {'id': g.id, 'name': g.name, 'target': g.targetPaise, 'saved': g.savedPaise},
      ],
      'splits': [
        for (final s in _splits)
          {
            'id': s.id,
            'person': s.person,
            'a': s.amountPaise,
            't': s.createdAt.toIso8601String(),
            if (s.note != null) 'n': s.note,
            if (s.settled) 'done': true,
          },
      ],
    }),
  );

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await _store.read();
    if (raw == null) {
      await (exampleOnFirstRun ? loadExampleData() : startFresh());
      return;
    }
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _example = j['example'] as bool? ?? false;
      _profile = Profile(monthlyIncomePaise: (j['income'] as num?)?.toInt() ?? 0, displayName: _example ? 'Demo' : null);
      _cats = [...builtinCategories, for (final c in (j['categories'] as List? ?? const [])) Category(id: c['id'] as String, name: c['name'] as String)];
      _budgets = {for (final e in (j['budgets'] as Map? ?? const {}).entries) e.key as String: (e.value as num).toInt()};
      _txns = [
        for (final t in (j['txns'] as List? ?? const []))
          Txn(
            id: t['id'] as String,
            amountPaise: (t['a'] as num).toInt(),
            categoryId: t['c'] as String,
            spentAt: DateTime.parse(t['t'] as String),
            note: t['n'] as String?,
            merchant: t['m'] as String?,
            pay: PayMethod.parse(t['p'] as String?),
            isRecurring: t['r'] as bool? ?? false,
          ),
      ]..sort((a, b) => b.spentAt.compareTo(a.spentAt));
      _goals = [
        for (final g in (j['goals'] as List? ?? const []))
          Goal(id: g['id'] as String, name: g['name'] as String, targetPaise: (g['target'] as num).toInt(), savedPaise: (g['saved'] as num).toInt()),
      ];
      _splits = [
        for (final s in (j['splits'] as List? ?? const []))
          Split(
            id: s['id'] as String,
            person: s['person'] as String,
            amountPaise: (s['a'] as num).toInt(),
            createdAt: DateTime.parse(s['t'] as String),
            note: s['n'] as String?,
            settled: s['done'] as bool? ?? false,
          ),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      // Unreadable data (e.g. an older format): start again rather than crash.
      await (exampleOnFirstRun ? loadExampleData() : startFresh());
    }
  }

  String _newId() => 'u${_clock().microsecondsSinceEpoch}-${_txns.length}';

  @override
  Future<AppData> load() async {
    await _ensureLoaded();
    return AppData(
      categories: List.of(_cats),
      txns: List.of(_txns),
      budgets: Map.of(_budgets),
      profile: _profile,
      goals: List.of(_goals),
      splits: List.of(_splits),
    );
  }

  @override
  Future<Txn> addTxn(NewTxn t) async {
    await _ensureLoaded();
    final txn = Txn(
      id: _newId(),
      amountPaise: t.amountPaise,
      categoryId: t.categoryId,
      spentAt: t.spentAt,
      note: t.note,
      merchant: t.note,
      pay: t.pay,
      isRecurring: t.isRecurring,
    );
    _txns = [txn, ..._txns]..sort((a, b) => b.spentAt.compareTo(a.spentAt));
    await _save();
    return txn;
  }

  @override
  Future<Txn> updateTxn(Txn t) async {
    await _ensureLoaded();
    _txns = [for (final x in _txns) x.id == t.id ? t : x]..sort((a, b) => b.spentAt.compareTo(a.spentAt));
    await _save();
    return t;
  }

  @override
  Future<void> updateTxnCategory(String txnId, String categoryId) async {
    await _ensureLoaded();
    _txns = [for (final t in _txns) t.id == txnId ? t.copyWith(categoryId: categoryId) : t];
    await _save();
  }

  @override
  Future<void> deleteTxn(String txnId) async {
    await _ensureLoaded();
    _txns.removeWhere((t) => t.id == txnId);
    await _save();
  }

  @override
  Future<Category> addCustomCategory(String name) async {
    await _ensureLoaded();
    final clean = name.trim();
    final low = clean.toLowerCase();
    final existing = _cats.where((c) => c.name.toLowerCase() == low || c.shortName.toLowerCase() == low);
    if (existing.isNotEmpty) return existing.first;
    final c = Category(id: 'c${_clock().microsecondsSinceEpoch}', name: clean);
    _cats = [..._cats, c];
    await _save();
    return c;
  }

  @override
  Future<void> setBudget(String categoryId, int limitPaise) async {
    await _ensureLoaded();
    _budgets[categoryId] = limitPaise;
    await _save();
  }

  @override
  Future<void> setBudgets(Map<String, int> limitsPaise) async {
    await _ensureLoaded();
    _budgets = {..._budgets, ...limitsPaise};
    await _save();
  }

  @override
  Future<void> setIncome(int paise) async {
    await _ensureLoaded();
    _profile = _profile.copyWith(monthlyIncomePaise: paise);
    await _save();
  }

  @override
  Future<Goal> addGoal(String name, int targetPaise) async {
    await _ensureLoaded();
    final g = Goal(id: 'g${_clock().microsecondsSinceEpoch}', name: name.trim(), targetPaise: targetPaise);
    _goals = [..._goals, g];
    await _save();
    return g;
  }

  @override
  Future<Goal> updateGoal(Goal goal) async {
    await _ensureLoaded();
    _goals = [for (final g in _goals) g.id == goal.id ? goal : g];
    await _save();
    return goal;
  }

  @override
  Future<void> deleteGoal(String id) async {
    await _ensureLoaded();
    _goals = _goals.where((g) => g.id != id).toList();
    await _save();
  }

  @override
  Future<List<Split>> addSplits(List<({String person, int amountPaise})> shares, {String? note}) async {
    await _ensureLoaded();
    final now = _clock();
    final added = [
      for (final (i, s) in shares.indexed)
        Split(id: 'p${now.microsecondsSinceEpoch}-$i', person: s.person, amountPaise: s.amountPaise, note: note, createdAt: now),
    ];
    _splits = [...added, ..._splits];
    await _save();
    return added;
  }

  @override
  Future<void> settleSplit(String id, bool settled) async {
    await _ensureLoaded();
    _splits = [for (final s in _splits) s.id == id ? s.copyWith(settled: settled) : s];
    await _save();
  }

  @override
  Future<void> deleteSplit(String id) async {
    await _ensureLoaded();
    _splits = _splits.where((s) => s.id != id).toList();
    await _save();
  }

  @override
  Future<void> deleteAccount() => startFresh();

  @override
  Future<void> signOut() async {}
}
