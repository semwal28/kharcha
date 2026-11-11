import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/money.dart';

/// The currency amounts are shown in, saved on this device.
/// First launch picks one from the phone's region.
class CurrencyController extends ValueNotifier<Currency> {
  CurrencyController([Currency? initial]) : super(initial ?? Money.currency) {
    Money.setCurrency(value);
  }

  static const _key = 'spendwell.currency';

  static Future<CurrencyController> load() async {
    String? saved;
    try {
      saved = (await SharedPreferences.getInstance()).getString(_key);
    } catch (_) {}
    final c = saved != null ? currencyByCode(saved) : currencyForCountry(PlatformDispatcher.instance.locale.countryCode);
    return CurrencyController(c);
  }

  Future<void> change(Currency c) async {
    if (c.code == value.code) return;
    Money.setCurrency(c);
    value = c;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, c.code);
    } catch (_) {}
  }
}

class CurrencyScope extends InheritedNotifier<CurrencyController> {
  const CurrencyScope({super.key, required CurrencyController controller, required super.child}) : super(notifier: controller);

  static CurrencyController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<CurrencyScope>()!.notifier!;
}
