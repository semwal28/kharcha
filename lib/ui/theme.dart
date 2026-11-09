import 'package:flutter/material.dart';

/// Kharcha colour tokens, matching the approved prototype.
@immutable
class KColors extends ThemeExtension<KColors> {
  const KColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.line,
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.bar,
    required this.barStrong,
    required this.hero,
    required this.hero2,
    required this.heroInk,
    required this.aurora1,
    required this.aurora2,
    required this.pop,
    required this.popInk,
    required this.popSoft,
    required this.good,
    required this.goodSoft,
    required this.warn,
    required this.warnSoft,
    required this.bad,
    required this.badSoft,
  });

  final Color bg, surface, surface2, ink, ink2, muted, line;
  final Color accent, accentInk, accentSoft, bar, barStrong;
  final Color hero, hero2, heroInk, aurora1, aurora2;
  final Color pop, popInk, popSoft;
  final Color good, goodSoft, warn, warnSoft, bad, badSoft;

  static const light = KColors(
    bg: Color(0xFFF2F5F3),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFE8EDEA),
    ink: Color(0xFF121A17),
    ink2: Color(0xFF46524D),
    muted: Color(0xFF6B7772),
    line: Color(0xFFD6DDD9),
    accent: Color(0xFF0D5C70),
    accentInk: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFD6E8ED),
    bar: Color(0xFF5E9FB1),
    barStrong: Color(0xFF0D5C70),
    hero: Color(0xFF0D5C70),
    hero2: Color(0xFF09404F),
    heroInk: Color(0xFFFFFFFF),
    aurora1: Color(0x80EDA43A),
    aurora2: Color(0x737DD7E6),
    pop: Color(0xFFEDA43A),
    popInk: Color(0xFF24170A),
    popSoft: Color(0xFFFCEBCF),
    good: Color(0xFF177A3D),
    goodSoft: Color(0xFFDCF0E2),
    warn: Color(0xFF8F5400),
    warnSoft: Color(0xFFFBEACB),
    bad: Color(0xFFB3302D),
    badSoft: Color(0xFFF7DDDB),
  );

  static const dark = KColors(
    bg: Color(0xFF0E1412),
    surface: Color(0xFF161E1B),
    surface2: Color(0xFF1E2825),
    ink: Color(0xFFE6EDE9),
    ink2: Color(0xFFB3BFBA),
    muted: Color(0xFF85928C),
    line: Color(0xFF2A3531),
    accent: Color(0xFF6CBACE),
    accentInk: Color(0xFF06222A),
    accentSoft: Color(0xFF17343C),
    bar: Color(0xFF3F7F90),
    barStrong: Color(0xFF8ED0E1),
    hero: Color(0xFF0F4A5A),
    hero2: Color(0xFF082D37),
    heroInk: Color(0xFFEAF6F9),
    aurora1: Color(0x59F2B14E),
    aurora2: Color(0x596CBACE),
    pop: Color(0xFFF2B14E),
    popInk: Color(0xFF24170A),
    popSoft: Color(0xFF3A2A10),
    good: Color(0xFF58C584),
    goodSoft: Color(0xFF163323),
    warn: Color(0xFFEDB25A),
    warnSoft: Color(0xFF3A2A10),
    bad: Color(0xFFF07C78),
    badSoft: Color(0xFF3D1A19),
  );

  @override
  KColors copyWith() => this;

  @override
  KColors lerp(ThemeExtension<KColors>? other, double t) => t < .5 || other is! KColors ? this : other;
}

const kBody = 'Figtree';
const kDisplay = 'FamiljenGrotesk';
const kTabular = [FontFeature.tabularFigures()];

extension KTheme on BuildContext {
  KColors get k => Theme.of(this).extension<KColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
}

ThemeData buildTheme(Brightness b) {
  final k = b == Brightness.dark ? KColors.dark : KColors.light;
  final base = ThemeData(brightness: b, useMaterial3: true, fontFamily: kBody);
  TextStyle d(double size, FontWeight w, {double ls = -0.3}) =>
      TextStyle(fontFamily: kDisplay, fontSize: size, fontWeight: w, letterSpacing: ls, color: k.ink, height: 1.1);
  final text = base.textTheme
      .apply(bodyColor: k.ink, displayColor: k.ink, fontFamily: kBody)
      .copyWith(
        displayLarge: d(40, FontWeight.w700, ls: -1.2),
        displayMedium: d(34, FontWeight.w700, ls: -0.8),
        headlineSmall: d(22, FontWeight.w700),
        titleLarge: d(20, FontWeight.w700),
        titleMedium: const TextStyle(fontFamily: kBody, fontSize: 16, fontWeight: FontWeight.w600).copyWith(color: k.ink),
        titleSmall: const TextStyle(fontFamily: kBody, fontSize: 15, fontWeight: FontWeight.w600).copyWith(color: k.ink),
        bodyLarge: TextStyle(fontFamily: kBody, fontSize: 15, color: k.ink, height: 1.4),
        bodyMedium: TextStyle(fontFamily: kBody, fontSize: 14, color: k.ink2, height: 1.4),
        bodySmall: TextStyle(fontFamily: kBody, fontSize: 12.5, color: k.muted, height: 1.35),
        labelSmall: TextStyle(fontFamily: kBody, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.9, color: k.muted),
      );
  return base.copyWith(
    scaffoldBackgroundColor: k.bg,
    canvasColor: k.bg,
    textTheme: text,
    extensions: [k],
    colorScheme: ColorScheme.fromSeed(
      seedColor: k.accent,
      brightness: b,
    ).copyWith(primary: k.accent, onPrimary: k.accentInk, surface: k.surface, onSurface: k.ink, error: k.bad),
    splashFactory: InkSparkle.splashFactory,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: k.bg,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: TextStyle(color: k.muted, fontSize: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: k.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: k.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: k.accent, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: k.ink,
      contentTextStyle: TextStyle(fontFamily: kBody, color: k.bg, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: k.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      showDragHandle: true,
      dragHandleColor: k.line,
    ),
    dialogTheme: DialogThemeData(backgroundColor: k.surface, surfaceTintColor: Colors.transparent),
  );
}
