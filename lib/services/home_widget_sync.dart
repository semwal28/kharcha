import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../core/money.dart';
import '../domain/analysis.dart';

/// Keeps the Android home screen widget ("Safe to spend today") up to date.
abstract final class HomeWidgetSync {
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static String? _last;

  static Future<void> push(MonthSummary? s) async {
    if (!supported || s == null) return;
    final safe = s.totalBudget > 0 ? Money.fmt(s.safeToday) : 'Set a budget';
    final spent = 'Spent in ${s.monthName}: ${Money.fmt(s.spent)}';
    final pct = s.totalBudget > 0 ? '${(s.budgetUsed * 100).round()}% of budget used' : '';
    final key = '$safe|$spent|$pct';
    if (key == _last) return;
    _last = key;
    try {
      await HomeWidget.saveWidgetData<String>('safe_today', safe);
      await HomeWidget.saveWidgetData<String>('spent', spent);
      await HomeWidget.saveWidgetData<String>('budget_pct', pct);
      await HomeWidget.updateWidget(qualifiedAndroidName: 'app.kharcha.kharcha.SpendwellWidgetProvider');
    } catch (_) {
      _last = null; // No widget placed yet, or the platform refused: try next time.
    }
  }
}
