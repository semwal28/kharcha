import 'package:intl/intl.dart';

/// A currency the app can show amounts in.
class Currency {
  const Currency(this.code, this.symbol, this.locale, this.name, this.scale);
  final String code;
  final String symbol;
  final String locale;
  final String name;

  /// Rough price level compared with India (INR = 1). Used only to size
  /// example data and "is this a lot?" thresholds, never to convert real money.
  final double scale;
}

const kCurrencies = <Currency>[
  Currency('INR', '₹', 'en_IN', 'Indian rupee', 1),
  Currency('USD', '\$', 'en_US', 'US dollar', .05),
  Currency('EUR', '€', 'en_IE', 'Euro', .045),
  Currency('GBP', '£', 'en_GB', 'British pound', .04),
  Currency('AED', 'AED ', 'en', 'UAE dirham', .18),
  Currency('SGD', 'S\$', 'en_SG', 'Singapore dollar', .07),
  Currency('CAD', 'C\$', 'en_CA', 'Canadian dollar', .07),
  Currency('AUD', 'A\$', 'en_AU', 'Australian dollar', .075),
  Currency('JPY', '¥', 'ja', 'Japanese yen', 6),
];

Currency currencyByCode(String? code) => kCurrencies.firstWhere((c) => c.code == code, orElse: () => kCurrencies.first);

/// A sensible first choice from the phone's region (falls back to INR).
Currency currencyForCountry(String? country) {
  const euro = {'DE', 'FR', 'IT', 'ES', 'NL', 'IE', 'PT', 'BE', 'AT', 'FI', 'GR', 'LU', 'SK', 'SI', 'EE', 'LV', 'LT', 'MT', 'CY', 'HR'};
  final code = switch (country?.toUpperCase()) {
    'US' => 'USD',
    'GB' => 'GBP',
    'AE' => 'AED',
    'SG' => 'SGD',
    'CA' => 'CAD',
    'AU' => 'AUD',
    'JP' => 'JPY',
    final c? when euro.contains(c) => 'EUR',
    _ => 'INR',
  };
  return currencyByCode(code);
}

/// Amounts are stored as whole minor units (paise, cents) so sums never drift.
abstract final class Money {
  static Currency _currency = kCurrencies.first;
  static NumberFormat _fmt = _make(kCurrencies.first);
  static NumberFormat _grouped = NumberFormat.decimalPattern(kCurrencies.first.locale);

  static NumberFormat _make(Currency c) => NumberFormat.currency(locale: c.locale, symbol: c.symbol, decimalDigits: 0);

  static Currency get currency => _currency;

  /// The symbol on its own, e.g. "₹", "\$", "AED".
  static String get symbol => _currency.symbol.trim();

  static void setCurrency(Currency c) {
    _currency = c;
    _fmt = _make(c);
    _grouped = NumberFormat.decimalPattern(c.locale);
  }

  /// ₹1,25,000 / \$1,250 from minor units.
  static String fmt(num minor) => _fmt.format((minor / 100).round());

  /// ₹1,25,000 / \$1,250 from whole units.
  static String whole(num major) => _fmt.format(major.round());

  /// Digits with the currency's grouping and no symbol.
  static String grouped(int value) => _grouped.format(value);

  /// Compact axis label: ₹2.5k, \$800.
  static String short(num minor) {
    final r = minor / 100;
    if (r.abs() >= 1000) {
      final k = r / 1000;
      final s = k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
      return '$symbol${s}k';
    }
    return '$symbol${r.round()}';
  }

  static int fromMajor(num major) => (major * 100).round();

  /// An amount written for India, sized to the current currency's price level.
  static int scaled(int inrMinor) => (inrMinor * _currency.scale).round();
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// "Fri, 6 Nov"
String fmtDay(DateTime d) => '${_weekdays[d.weekday - 1]}, ${d.day} ${monthNames[d.month - 1].substring(0, 3)}';

/// "Today", "Yesterday" or "Fri, 6 Nov"
String dayLabel(DateTime d, DateTime now) {
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return fmtDay(d);
}

String hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;
