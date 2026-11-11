import '../data/models.dart';

const _months = {'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12};

int _year(String y) => y.length == 2 ? 2000 + int.parse(y) : int.parse(y);

DateTime? _safeDate(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, m, d);
  return dt.month == m ? dt : null;
}

/// Finds a date like 06-11-26, 06/11/2026, 2026-11-07, 06Nov26 or 06-Nov-2026.
/// Day-first, as Indian banks and shops write it.
DateTime? findDate(String text) {
  final iso = RegExp(r'\b(20\d\d)-(\d{1,2})-(\d{1,2})').firstMatch(text);
  if (iso != null) return _safeDate(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
  final dmy = RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})\b').firstMatch(text);
  if (dmy != null) return _safeDate(_year(dmy[3]!), int.parse(dmy[2]!), int.parse(dmy[1]!));
  final named = RegExp(r'\b(\d{1,2})[- ]?([A-Za-z]{3})[a-z]*[- ,]?(\d{4}|\d{2})\b').firstMatch(text);
  if (named != null) {
    final m = _months[named[2]!.toLowerCase()];
    if (m != null) return _safeDate(_year(named[3]!), m, int.parse(named[1]!));
  }
  return null;
}

int? _toPaise(String raw) {
  final v = double.tryParse(raw.replaceAll(',', ''));
  if (v == null || v <= 0 || v >= 100000000) return null;
  return (v * 100).round();
}

String _title(String s) => s
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w.length <= 2 && w == w.toUpperCase() && w.length > 1 ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

class ParsedSms {
  const ParsedSms({required this.amountPaise, this.merchant, this.isCredit = false, this.pay, this.date});
  final int amountPaise;
  final String? merchant;

  /// Money coming in (salary, refund), not an expense.
  final bool isCredit;
  final PayMethod? pay;
  final DateTime? date;
}

/// Reads a bank or card SMS that was copied and pasted into the app.
/// Returns null when no amount can be found.
ParsedSms? parseBankSms(String raw) {
  final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  final lower = text.toLowerCase();
  final amount = RegExp(r'(?:rs\.?|inr|₹|usd|\$|eur|€|gbp|£|aed)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)', caseSensitive: false).firstMatch(text);
  final paise = amount == null ? null : _toPaise(amount[1]!);
  if (paise == null) return null;

  final debit = RegExp(r'debited|spent|paid|sent|withdrawn|purchase|deducted|transferred to|payment of').hasMatch(lower);
  final credit = RegExp(r'credited|received|refund|deposited').hasMatch(lower);

  String? merchant;
  final info = RegExp(r'info:?\s*([A-Za-z0-9 .*/&\-]+)', caseSensitive: false).firstMatch(text);
  final vpa = RegExp(r'vpa\s+([A-Za-z0-9.\-_]+)@', caseSensitive: false).firstMatch(text);
  final atTo = RegExp(
    r"\b(?:at|to)\s+(?!a/c|ac\b|your\b|vpa\b)([A-Za-z0-9&.'\- ]{2,40}?)(?=\s+on\s|\s+via\b|\s+ref\b|\s+using\b|\s+upi\b|\s*\(|\.\s|\.$|,|$)",
    caseSensitive: false,
  ).firstMatch(text);
  if (info != null) {
    final parts = info[1]!.split('/').map((p) => p.trim()).where((p) => RegExp('[A-Za-z]{3,}').hasMatch(p)).toList();
    final label = parts.isEmpty ? null : parts.last.split(RegExp(r'\.\s|\. ')).first;
    if (label != null && !RegExp(r'^(upi|p2m|p2a|imps|neft)$', caseSensitive: false).hasMatch(label)) merchant = label;
  }
  if (merchant == null && vpa != null) merchant = vpa[1]!.split(RegExp('[._-]')).first;
  if (merchant == null && atTo != null) merchant = atTo[1];
  merchant = merchant?.replaceAll(RegExp(r'[.\s]+$'), '');

  final pay = RegExp(r'\bupi\b|\bvpa\b').hasMatch(lower)
      ? PayMethod.upi
      : RegExp(r'\bcard\b').hasMatch(lower)
      ? PayMethod.card
      : RegExp(r'\batm\b|withdrawn').hasMatch(lower)
      ? PayMethod.cash
      : null;

  return ParsedSms(
    amountPaise: paise,
    merchant: merchant == null || merchant.isEmpty ? null : _title(merchant),
    isCredit: credit && !debit,
    pay: pay,
    date: findDate(text),
  );
}

class ParsedReceipt {
  const ParsedReceipt({this.totalPaise, this.merchant, this.date});
  final int? totalPaise;
  final String? merchant;
  final DateTime? date;
}

const _totalWords = ['grand total', 'net amount', 'amount payable', 'net payable', 'total amount', 'amount due', 'to pay', 'bill amount', 'total'];
final _notTotal = RegExp(r'sub\s?total|total\s+(qty|quantity|items?|savings?|discount|tax|gst)|items?\s+total', caseSensitive: false);
final _number = RegExp(r'([0-9][0-9,]*\.[0-9]{2}|[0-9][0-9,]*)');

/// Reads the total, shop name and date from a receipt photo's text.
ParsedReceipt parseReceiptText(String raw) {
  final lines = raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  int? total;
  for (final word in _totalWords) {
    for (var i = lines.length - 1; i >= 0 && total == null; i--) {
      final l = lines[i].toLowerCase();
      if (!l.contains(word) || _notTotal.hasMatch(l)) continue;
      final here = _number.allMatches(lines[i]).map((m) => _toPaise(m[1]!)).whereType<int>().toList();
      if (here.isNotEmpty) {
        total = here.last;
      } else if (i + 1 < lines.length) {
        final next = _number.allMatches(lines[i + 1]).map((m) => _toPaise(m[1]!)).whereType<int>().toList();
        if (next.isNotEmpty) total = next.last;
      }
    }
    if (total != null) break;
  }
  // No "total" line: take the largest amount written with paise (e.g. 1,234.50).
  total ??= RegExp(r'[0-9][0-9,]*\.[0-9]{2}')
      .allMatches(raw)
      .map((m) => _toPaise(m[0]!))
      .whereType<int>()
      .fold<int?>(null, (a, b) => a == null || b > a ? b : a);

  String? merchant;
  for (final l in lines.take(5)) {
    final letters = RegExp('[A-Za-z]').allMatches(l).length;
    if (letters < 3 || letters < l.length * .5) continue;
    if (RegExp(r'^(tax\s+)?invoice|^receipt|^bill\b|^cash\s*memo|^welcome|^gstin', caseSensitive: false).hasMatch(l)) continue;
    merchant = _title(l);
    break;
  }
  return ParsedReceipt(totalPaise: total, merchant: merchant, date: findDate(raw));
}
