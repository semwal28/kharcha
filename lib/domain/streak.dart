import '../data/models.dart';

/// Days in a row with at least one expense logged, counting back from today.
/// Not having logged anything yet today doesn't break the streak.
int loggingStreak(List<Txn> txns, DateTime now) {
  final days = {for (final t in txns) DateTime(t.spentAt.year, t.spentAt.month, t.spentAt.day)};
  var d = DateTime(now.year, now.month, now.day);
  if (!days.contains(d)) d = DateTime(d.year, d.month, d.day - 1);
  var n = 0;
  while (days.contains(d)) {
    n++;
    d = DateTime(d.year, d.month, d.day - 1);
  }
  return n;
}

/// "Good morning" and friends.
String greeting(DateTime now) => switch (now.hour) {
  < 5 => 'Good night',
  < 12 => 'Good morning',
  < 17 => 'Good afternoon',
  _ => 'Good evening',
};
