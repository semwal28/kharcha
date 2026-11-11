enum PayMethod {
  upi('UPI'),
  card('Card'),
  cash('Cash'),
  other('Other');

  const PayMethod(this.label);
  final String label;

  static PayMethod parse(String? s) => values.firstWhere((p) => p.label == s, orElse: () => PayMethod.upi);
}

/// Short labels for the category picker tiles.
const kShortNames = <String, String>{
  'dining': 'Dining',
  'delivery': 'Delivery',
  'groceries': 'Groceries',
  'transport': 'Transport',
  'shopping': 'Shopping',
  'bills': 'Bills',
  'fun': 'Fun',
  'health': 'Health',
  'care': 'Self-care',
  'subs': 'Subscriptions',
  'rent': 'Rent',
  'fees': 'Fees',
  'other': 'Other',
};

/// Order of built-in tiles in the picker. Custom categories go before "Other".
const kPickOrder = ['dining', 'delivery', 'groceries', 'transport', 'shopping', 'bills', 'fun', 'health', 'care', 'subs', 'rent'];

class Category {
  const Category({required this.id, required this.name, this.key, this.icon = 'tag', this.isFixed = false, this.sortOrder = 100});

  /// Database id (uuid) or, in demo mode, the key itself.
  final String id;

  /// Stable key for built-in categories ('dining', 'rent'...). Null for custom ones.
  final String? key;
  final String name;
  final String icon;

  /// Rent, bills and subscriptions: expected every month.
  final bool isFixed;
  final int sortOrder;

  bool get isCustom => key == null;
  String get shortName => kShortNames[key] ?? name;

  @override
  bool operator ==(Object other) => other is Category && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class Txn {
  const Txn({
    required this.id,
    required this.amountPaise,
    required this.categoryId,
    required this.spentAt,
    this.note,
    this.merchant,
    this.pay = PayMethod.upi,
    this.isRecurring = false,
  });

  final String id;
  final int amountPaise;
  final String categoryId;
  final DateTime spentAt;
  final String? note;
  final String? merchant;
  final PayMethod pay;
  final bool isRecurring;

  /// What the list shows: the note if there is one, else the merchant.
  String titleOr(String fallback) {
    if (note != null && note!.trim().isNotEmpty) return note!.trim();
    if (merchant != null && merchant!.trim().isNotEmpty) return merchant!.trim();
    return fallback;
  }

  /// Used to spot double charges and repeat spends.
  String get matchKey => (merchant?.trim().isNotEmpty ?? false) ? merchant!.trim().toLowerCase() : (note ?? '').trim().toLowerCase();

  Txn copyWith({String? id, String? categoryId, int? amountPaise, DateTime? spentAt, PayMethod? pay, bool? isRecurring}) => Txn(
    id: id ?? this.id,
    amountPaise: amountPaise ?? this.amountPaise,
    categoryId: categoryId ?? this.categoryId,
    spentAt: spentAt ?? this.spentAt,
    note: note,
    merchant: merchant,
    pay: pay ?? this.pay,
    isRecurring: isRecurring ?? this.isRecurring,
  );

  /// Same expense with a new note (null clears it). The note also becomes the
  /// merchant label for expenses typed by hand.
  Txn withNote(String? newNote) => Txn(
    id: id,
    amountPaise: amountPaise,
    categoryId: categoryId,
    spentAt: spentAt,
    note: newNote,
    // Hand-typed expenses use the note as the merchant label too.
    merchant: merchant == note ? newNote : merchant,
    pay: pay,
    isRecurring: isRecurring,
  );
}

/// What the add-expense sheet submits.
class NewTxn {
  const NewTxn({required this.amountPaise, required this.categoryId, required this.spentAt, this.note, this.pay = PayMethod.upi, this.isRecurring = false});

  final int amountPaise;
  final String categoryId;
  final DateTime spentAt;
  final String? note;
  final PayMethod pay;

  /// "Repeats monthly": added again automatically each month.
  final bool isRecurring;
}

/// Money put aside for something, e.g. "Goa trip".
class Goal {
  const Goal({required this.id, required this.name, required this.targetPaise, this.savedPaise = 0});
  final String id;
  final String name;
  final int targetPaise;
  final int savedPaise;

  double get progress => targetPaise <= 0 ? 0 : (savedPaise / targetPaise).clamp(0, 1).toDouble();
  bool get reached => savedPaise >= targetPaise;
  int get leftPaise => (targetPaise - savedPaise).clamp(0, targetPaise);

  Goal copyWith({String? name, int? targetPaise, int? savedPaise}) =>
      Goal(id: id, name: name ?? this.name, targetPaise: targetPaise ?? this.targetPaise, savedPaise: savedPaise ?? this.savedPaise);
}

/// Someone's share of a bill you paid: they owe you this.
class Split {
  const Split({required this.id, required this.person, required this.amountPaise, required this.createdAt, this.note, this.settled = false});
  final String id;
  final String person;
  final int amountPaise;
  final DateTime createdAt;
  final String? note;
  final bool settled;

  Split copyWith({bool? settled}) =>
      Split(id: id, person: person, amountPaise: amountPaise, createdAt: createdAt, note: note, settled: settled ?? this.settled);
}

class Profile {
  const Profile({this.monthlyIncomePaise = 0, this.displayName, this.plan = 'free', this.email});
  final int monthlyIncomePaise;
  final String? displayName;
  final String plan;
  final String? email;

  Profile copyWith({int? monthlyIncomePaise}) =>
      Profile(monthlyIncomePaise: monthlyIncomePaise ?? this.monthlyIncomePaise, displayName: displayName, plan: plan, email: email);
}

class AppData {
  AppData({
    required this.categories,
    required this.txns,
    required this.budgets,
    required this.profile,
    this.goals = const [],
    this.splits = const [],
    this.extrasAvailable = true,
  }) : _byId = {for (final c in categories) c.id: c},
       _byKey = {
         for (final c in categories)
           if (c.key != null) c.key!: c,
       };

  final List<Category> categories;

  /// Newest first.
  final List<Txn> txns;

  /// category id -> monthly limit in paise
  final Map<String, int> budgets;
  final Profile profile;
  final List<Goal> goals;

  /// Newest first.
  final List<Split> splits;

  /// False when the server is missing the goals/splits tables (the newer
  /// database update has not been run yet). Those features hide until it is.
  final bool extrasAvailable;

  final Map<String, Category> _byId;
  final Map<String, Category> _byKey;

  Category get other => _byKey['other']!;
  Category cat(String id) => _byId[id] ?? other;
  Category? byKey(String key) => _byKey[key];
  String? keyOf(String categoryId) => _byId[categoryId]?.key;

  /// Built-ins in picker order, then custom categories, then Other.
  List<Category> get pickerCategories => [
    for (final k in kPickOrder)
      if (_byKey[k] != null) _byKey[k]!,
    ...categories.where((c) => c.isCustom),
    other,
  ];

  AppData copyWith({List<Category>? categories, List<Txn>? txns, Map<String, int>? budgets, Profile? profile, List<Goal>? goals, List<Split>? splits}) {
    final list = txns ?? this.txns;
    return AppData(
      categories: categories ?? this.categories,
      txns: txns == null ? list : (List.of(list)..sort((a, b) => b.spentAt.compareTo(a.spentAt))),
      budgets: budgets ?? this.budgets,
      profile: profile ?? this.profile,
      goals: goals ?? this.goals,
      splits: splits ?? this.splits,
      extrasAvailable: extrasAvailable,
    );
  }
}
