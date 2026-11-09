import '../data/models.dart';

/// Keywords people type in a note, mapped to built-in category keys.
/// Checked in order, so brand names win over generic words.
const _keywords = <(String, List<String>)>[
  ('delivery', ['swiggy', 'zomato', 'food delivery', 'ordered food']),
  ('subs', ['netflix', 'spotify', 'prime video', 'amazon prime', 'hotstar', 'youtube premium', 'subscription', 'sonyliv', 'zee5']),
  (
    'groceries',
    [
      'grocery',
      'groceries',
      'vegetable',
      'veggies',
      'sabzi',
      'sabji',
      'milk',
      'doodh',
      'fruit',
      'blinkit',
      'zepto',
      'bigbasket',
      'dmart',
      'kirana',
      'eggs',
      'bread',
      'atta',
      'rice',
    ],
  ),
  (
    'transport',
    ['petrol', 'diesel', 'fuel', 'uber', 'ola', 'rapido', 'auto', 'rickshaw', 'cab', 'taxi', 'metro', 'bus', 'parking', 'toll', 'train', 'fastag', 'car wash'],
  ),
  (
    'bills',
    [
      'electricity',
      'light bill',
      'bijli',
      'recharge',
      'wifi',
      'internet',
      'broadband',
      'gas',
      'cylinder',
      'water bill',
      'phone bill',
      'dth',
      'postpaid',
      'maintenance',
    ],
  ),
  ('rent', ['rent', 'kiraya', 'pg']),
  ('health', ['medicine', 'dawai', 'pharmacy', 'chemist', 'doctor', 'hospital', 'clinic', 'gym', 'apollo', 'lab test', 'dentist']),
  ('care', ['salon', 'haircut', 'parlour', 'parlor', 'spa', 'grooming']),
  ('fun', ['movie', 'cinema', 'pvr', 'inox', 'bookmyshow', 'concert', 'game', 'party', 'outing']),
  (
    'shopping',
    [
      'amazon',
      'flipkart',
      'myntra',
      'ajio',
      'meesho',
      'nykaa',
      'clothes',
      'shirt',
      'jeans',
      'shoe',
      'kurta',
      'saree',
      'dress',
      'bag',
      'watch',
      'headphone',
      'gift',
      'shopping',
    ],
  ),
  (
    'dining',
    [
      'chai',
      'tea',
      'coffee',
      'samosa',
      'lunch',
      'dinner',
      'breakfast',
      'snack',
      'restaurant',
      'cafe',
      'café',
      'starbucks',
      'pizza',
      'burger',
      'biryani',
      'dosa',
      'momos',
      'juice',
      'canteen',
      'dhaba',
      'sweets',
      'ice cream',
      'vada pav',
      'pani puri',
      'thali',
      'meal',
    ],
  ),
  ('other', ['donation', 'tip', 'laundry', 'xerox', 'courier', 'stationery', 'tuition', 'books']),
];

final _patterns = [
  for (final (key, words) in _keywords) (key, [for (final w in words) RegExp('(^|[^a-z])${RegExp.escape(w)}(?:s|es)?([^a-z]|\$)')]),
];

/// Picks a category for a free-text note, or null if nothing matches.
/// The user's own categories ("Gifts") are checked first.
Category? guessCategory(String text, AppData data) {
  final t = ' ${text.toLowerCase()} ';
  if (t.trim().isEmpty) return null;
  for (final c in data.categories.where((c) => c.isCustom)) {
    var n = c.name.toLowerCase();
    if (n.endsWith('s')) n = n.substring(0, n.length - 1);
    if (n.length > 2 && t.contains(n)) return c;
  }
  for (final (key, patterns) in _patterns) {
    if (patterns.any((p) => p.hasMatch(t))) return data.byKey(key);
  }
  return null;
}
