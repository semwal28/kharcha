import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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

/// Phone-only store: works with no account and no internet. Starts with two
/// months of example data, which the user can clear ("Start fresh").
class LocalRepository implements ExpenseRepository {
  LocalRepository({KeyValueStore? store, DateTime Function()? clock}) : _store = store ?? MemoryStore(), _clock = clock ?? DateTime.now;

  final KeyValueStore _store;
  final DateTime Function() _clock;
  List<Category> _cats = List.of(builtinCategories);
  List<Txn> _txns = [];
  Map<String, int> _budgets = {};
  Profile _profile = const Profile();
  bool _example = false;
  bool _loaded = false;

  @override
  bool get isLocal => true;

  @override
  bool get hasExampleData => _example;

  Map<String, int> get _starterBudgets => {for (final e in demoBudgetsRupees.entries) e.key: e.value * 100};

  /// Two months of example spending (the state a new user sees first).
  Future<void> loadExampleData() async {
    _cats = List.of(builtinCategories);
    _txns = generateSampleTxns(_clock());
    _budgets = _starterBudgets;
    _profile = const Profile(monthlyIncomePaise: 6500000, displayName: 'Demo');
    _example = true;
    await _save();
  }

  /// Clears expenses and custom categories. Keeps starter budgets to edit.
  Future<void> startFresh() async {
    _cats = List.of(builtinCategories);
    _txns = [];
    _budgets = _starterBudgets;
    _profile = const Profile();
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
    }),
  );

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await _store.read();
    if (raw == null) {
      await loadExampleData();
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
    } catch (_) {
      // Unreadable data (e.g. an older format): start again with examples
      // rather than crash.
      await loadExampleData();
    }
  }

  String _newId() => 'u${_clock().microsecondsSinceEpoch}-${_txns.length}';

  @override
  Future<AppData> load() async {
    await _ensureLoaded();
    return AppData(categories: List.of(_cats), txns: List.of(_txns), budgets: Map.of(_budgets), profile: _profile);
  }

  @override
  Future<Txn> addTxn(NewTxn t) async {
    await _ensureLoaded();
    final txn = Txn(id: _newId(), amountPaise: t.amountPaise, categoryId: t.categoryId, spentAt: t.spentAt, note: t.note, merchant: t.note, pay: t.pay);
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
  Future<void> deleteAccount() => startFresh();

  @override
  Future<void> signOut() async {}
}
