import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'repository.dart';

/// Live store backed by Supabase (Postgres + row-level security).
/// See supabase/migrations for the schema.
class SupabaseRepository implements ExpenseRepository {
  SupabaseRepository(this._db);
  final SupabaseClient _db;

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw RepoException('You are signed out. Sign in again.');
    return id;
  }

  @override
  bool get isLocal => false;

  @override
  bool get hasExampleData => false;

  @override
  Future<AppData> load() async {
    final uid = _uid;
    final now = DateTime.now();
    final since = DateTime(now.year, now.month - 1, 1);
    try {
      final results = await Future.wait([
        _db.from('categories').select('id,key,name,icon,is_fixed,sort_order').order('sort_order'),
        _db
            .from('transactions')
            .select('id,amount_paise,category_id,note,merchant,pay_method,spent_at,is_recurring')
            .gte('spent_at', since.toUtc().toIso8601String())
            .order('spent_at', ascending: false)
            .limit(5000),
        _db.from('budgets').select('category_id,limit_paise'),
        _db.from('profiles').select('display_name,monthly_income_paise,plan').eq('id', uid).maybeSingle(),
      ]);
      final cats = [for (final r in results[0] as List) _category(r as Map<String, dynamic>)];
      final txns = [for (final r in results[1] as List) _txn(r as Map<String, dynamic>)];
      final budgets = {for (final r in results[2] as List) (r as Map)['category_id'] as String: (r['limit_paise'] as num).toInt()};
      final p = results[3] as Map<String, dynamic>?;
      final extras = await _loadExtras();
      return AppData(
        categories: cats,
        txns: txns,
        budgets: budgets,
        goals: extras?.goals ?? const [],
        splits: extras?.splits ?? const [],
        extrasAvailable: extras != null,
        profile: Profile(
          displayName: p?['display_name'] as String?,
          monthlyIncomePaise: (p?['monthly_income_paise'] as num?)?.toInt() ?? 0,
          plan: p?['plan'] as String? ?? 'free',
          email: _db.auth.currentUser?.email,
        ),
      );
    } on PostgrestException catch (e) {
      throw RepoException('Could not load your data (${e.message}).');
    }
  }

  /// Goals and splits live in tables added by the second database update.
  /// If it hasn't been run yet, the rest of the app still works.
  Future<({List<Goal> goals, List<Split> splits})?> _loadExtras() async {
    try {
      final r = await Future.wait([
        _db.from('goals').select('id,name,target_paise,saved_paise').order('created_at'),
        _db.from('splits').select('id,person,amount_paise,note,created_at,settled_at').order('created_at', ascending: false).limit(500),
      ]);
      return (
        goals: [for (final g in r[0] as List) _goal(g as Map<String, dynamic>)],
        splits: [for (final s in r[1] as List) _split(s as Map<String, dynamic>)],
      );
    } on PostgrestException {
      return null;
    }
  }

  static Goal _goal(Map<String, dynamic> r) => Goal(
    id: r['id'] as String,
    name: r['name'] as String,
    targetPaise: (r['target_paise'] as num).toInt(),
    savedPaise: (r['saved_paise'] as num?)?.toInt() ?? 0,
  );

  static Split _split(Map<String, dynamic> r) => Split(
    id: r['id'] as String,
    person: r['person'] as String,
    amountPaise: (r['amount_paise'] as num).toInt(),
    note: r['note'] as String?,
    createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
    settled: r['settled_at'] != null,
  );

  static Category _category(Map<String, dynamic> r) => Category(
    id: r['id'] as String,
    key: r['key'] as String?,
    name: r['name'] as String,
    icon: r['icon'] as String? ?? 'tag',
    isFixed: r['is_fixed'] as bool? ?? false,
    sortOrder: (r['sort_order'] as num?)?.toInt() ?? 100,
  );

  static Txn _txn(Map<String, dynamic> r) => Txn(
    id: r['id'] as String,
    amountPaise: (r['amount_paise'] as num).toInt(),
    categoryId: r['category_id'] as String,
    note: r['note'] as String?,
    merchant: r['merchant'] as String?,
    pay: PayMethod.parse(r['pay_method'] as String?),
    spentAt: DateTime.parse(r['spent_at'] as String).toLocal(),
    isRecurring: r['is_recurring'] as bool? ?? false,
  );

  Future<T> _guard<T>(String what, Future<T> Function() run) async {
    try {
      return await run();
    } on PostgrestException catch (e) {
      throw RepoException('Could not $what (${e.message}).');
    }
  }

  @override
  Future<Txn> addTxn(NewTxn t) => _guard('save the expense', () async {
    final row = await _db
        .from('transactions')
        .insert({
          'user_id': _uid,
          'amount_paise': t.amountPaise,
          'category_id': t.categoryId,
          'note': t.note,
          'merchant': t.note,
          'pay_method': t.pay.label,
          'spent_at': t.spentAt.toUtc().toIso8601String(),
          'is_recurring': t.isRecurring,
        })
        .select('id,amount_paise,category_id,note,merchant,pay_method,spent_at,is_recurring')
        .single();
    return _txn(row);
  });

  @override
  Future<Txn> updateTxn(Txn t) => _guard('save the expense', () async {
    final row = await _db
        .from('transactions')
        .update({
          'amount_paise': t.amountPaise,
          'category_id': t.categoryId,
          'note': t.note,
          'merchant': t.merchant,
          'pay_method': t.pay.label,
          'spent_at': t.spentAt.toUtc().toIso8601String(),
          'is_recurring': t.isRecurring,
        })
        .eq('id', t.id)
        .select('id,amount_paise,category_id,note,merchant,pay_method,spent_at,is_recurring')
        .single();
    return _txn(row);
  });

  @override
  Future<Goal> addGoal(String name, int targetPaise) => _guard('create the goal', () async {
    final row = await _db
        .from('goals')
        .insert({'user_id': _uid, 'name': name.trim(), 'target_paise': targetPaise})
        .select('id,name,target_paise,saved_paise')
        .single();
    return _goal(row);
  });

  @override
  Future<Goal> updateGoal(Goal goal) => _guard('save the goal', () async {
    final row = await _db
        .from('goals')
        .update({'name': goal.name, 'target_paise': goal.targetPaise, 'saved_paise': goal.savedPaise})
        .eq('id', goal.id)
        .select('id,name,target_paise,saved_paise')
        .single();
    return _goal(row);
  });

  @override
  Future<void> deleteGoal(String id) => _guard('delete the goal', () => _db.from('goals').delete().eq('id', id));

  @override
  Future<List<Split>> addSplits(List<({String person, int amountPaise})> shares, {String? note}) => _guard('save the split', () async {
    if (shares.isEmpty) return <Split>[];
    final uid = _uid;
    final rows = await _db
        .from('splits')
        .insert([
          for (final s in shares) {'user_id': uid, 'person': s.person, 'amount_paise': s.amountPaise, 'note': note},
        ])
        .select('id,person,amount_paise,note,created_at,settled_at');
    return [for (final r in rows) _split(r)];
  });

  @override
  Future<void> settleSplit(String id, bool settled) =>
      _guard('update the split', () => _db.from('splits').update({'settled_at': settled ? DateTime.now().toUtc().toIso8601String() : null}).eq('id', id));

  @override
  Future<void> deleteSplit(String id) => _guard('delete the split', () => _db.from('splits').delete().eq('id', id));

  @override
  Future<void> deleteAccount() async {
    try {
      await _db.functions.invoke('delete-account');
    } on FunctionException catch (e) {
      final details = e.details;
      throw RepoException(details is Map && details['message'] is String ? details['message'] as String : 'Could not delete your account. Try again.');
    }
    await _db.auth.signOut();
  }

  @override
  Future<void> updateTxnCategory(String txnId, String categoryId) =>
      _guard('change the category', () => _db.from('transactions').update({'category_id': categoryId}).eq('id', txnId));

  @override
  Future<void> deleteTxn(String txnId) => _guard('delete the expense', () => _db.from('transactions').delete().eq('id', txnId));

  @override
  Future<Category> addCustomCategory(String name) => _guard('create the category', () async {
    final clean = name.trim();
    final pattern = clean.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
    final existing = await _db.from('categories').select('id,key,name,icon,is_fixed,sort_order').ilike('name', pattern).limit(1);
    if ((existing as List).isNotEmpty) return _category(existing.first);
    final row = await _db
        .from('categories')
        .insert({'user_id': _uid, 'name': clean, 'icon': 'tag', 'sort_order': 500})
        .select('id,key,name,icon,is_fixed,sort_order')
        .single();
    return _category(row);
  });

  @override
  Future<void> setBudget(String categoryId, int limitPaise) =>
      _guard('save the budget', () => _db.from('budgets').upsert({'user_id': _uid, 'category_id': categoryId, 'limit_paise': limitPaise}));

  @override
  Future<void> setBudgets(Map<String, int> limitsPaise) => _guard('save the budgets', () async {
    final uid = _uid;
    await _db.from('budgets').upsert([
      for (final e in limitsPaise.entries) {'user_id': uid, 'category_id': e.key, 'limit_paise': e.value},
    ]);
  });

  @override
  Future<void> setIncome(int paise) => _guard('save your income', () => _db.from('profiles').update({'monthly_income_paise': paise}).eq('id', _uid));

  @override
  Future<void> signOut() => _db.auth.signOut();
}
