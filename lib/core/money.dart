import 'package:intl/intl.dart';

/// Money is stored as whole paise (1 rupee = 100 paise) so sums never drift.
abstract final class Money {
  static final NumberFormat _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final NumberFormat _grouped = NumberFormat.decimalPattern('en_IN');

  /// ₹1,25,000 from paise.
  static String inr(num paise) => _inr.format((paise / 100).round());

  /// ₹1,25,000 from rupees.
  static String rupees(num rupees) => _inr.format(rupees.round());

  /// 1,25,000 (Indian digit grouping, no symbol).
  static String grouped(int value) => _grouped.format(value);

  /// Compact axis label: ₹2.5k, ₹800.
  static String short(num paise) {
    final r = paise / 100;
    if (r.abs() >= 1000) {
      final k = (r / 1000);
      final s = k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
      return '₹${s}k';
    }
    return '₹${r.round()}';
  }

  static int fromRupees(num rupees) => (rupees * 100).round();
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
