import 'package:flutter/material.dart';

/// Spendwell colour tokens, matching the approved prototype.
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
    bg: Color(0xFFF6F3FF),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEFEAFE),
    ink: Color(0xFF16112B),
    ink2: Color(0xFF4A4366),
    muted: Color(0xFF6E6888),
    line: Color(0xFFE3DDF7),
    accent: Color(0xFF6A3DF0),
    accentInk: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFECE6FF),
    bar: Color(0xFF9C83F7),
    barStrong: Color(0xFF6A3DF0),
    hero: Color(0xFF5B2EE6),
    hero2: Color(0xFFB02ACB),
    heroInk: Color(0xFFFFFFFF),
    aurora1: Color(0x8CFFB627),
    aurora2: Color(0x7327E0D0),
    pop: Color(0xFFFFB627),
    popInk: Color(0xFF2A1A00),
    popSoft: Color(0xFFFFF1D1),
    good: Color(0xFF0B8F63),
    goodSoft: Color(0xFFD8F5EA),
    warn: Color(0xFFAD6500),
    warnSoft: Color(0xFFFFEFD0),
    bad: Color(0xFFDC3D43),
    badSoft: Color(0xFFFDE3E4),
  );

  static const dark = KColors(
    bg: Color(0xFF0E0A1A),
    surface: Color(0xFF17122A),
    surface2: Color(0xFF221B39),
    ink: Color(0xFFEEEAFB),
    ink2: Color(0xFFBDB5D9),
    muted: Color(0xFF8F87AE),
    line: Color(0xFF2E2649),
    accent: Color(0xFFA68CFF),
    accentInk: Color(0xFF1A0E3D),
    accentSoft: Color(0xFF2A2050),
    bar: Color(0xFF6E57C9),
    barStrong: Color(0xFFB9A6FF),
    hero: Color(0xFF4A22C9),
    hero2: Color(0xFF8E1FA8),
    heroInk: Color(0xFFFFFFFF),
    aurora1: Color(0x66FFB627),
    aurora2: Color(0x5527E0D0),
    pop: Color(0xFFFFC043),
    popInk: Color(0xFF2A1A00),
    popSoft: Color(0xFF3A2C10),
    good: Color(0xFF3DD39B),
    goodSoft: Color(0xFF12332A),
    warn: Color(0xFFFFC15E),
    warnSoft: Color(0xFF3A2C10),
    bad: Color(0xFFFF7A7F),
    badSoft: Color(0xFF3D1A20),
  );

  @override
  KColors copyWith() => this;

  @override
  KColors lerp(ThemeExtension<KColors>? other, double t) {
    if (other is! KColors) return this;
    final o = other;
    return KColors(
      bg: Color.lerp(bg, o.bg, t)!,
      surface: Color.lerp(surface, o.surface, t)!,
      surface2: Color.lerp(surface2, o.surface2, t)!,
      ink: Color.lerp(ink, o.ink, t)!,
      ink2: Color.lerp(ink2, o.ink2, t)!,
      muted: Color.lerp(muted, o.muted, t)!,
      line: Color.lerp(line, o.line, t)!,
      accent: Color.lerp(accent, o.accent, t)!,
      accentInk: Color.lerp(accentInk, o.accentInk, t)!,
      accentSoft: Color.lerp(accentSoft, o.accentSoft, t)!,
      bar: Color.lerp(bar, o.bar, t)!,
      barStrong: Color.lerp(barStrong, o.barStrong, t)!,
      hero: Color.lerp(hero, o.hero, t)!,
      hero2: Color.lerp(hero2, o.hero2, t)!,
      heroInk: Color.lerp(heroInk, o.heroInk, t)!,
      aurora1: Color.lerp(aurora1, o.aurora1, t)!,
      aurora2: Color.lerp(aurora2, o.aurora2, t)!,
      pop: Color.lerp(pop, o.pop, t)!,
      popInk: Color.lerp(popInk, o.popInk, t)!,
      popSoft: Color.lerp(popSoft, o.popSoft, t)!,
      good: Color.lerp(good, o.good, t)!,
      goodSoft: Color.lerp(goodSoft, o.goodSoft, t)!,
      warn: Color.lerp(warn, o.warn, t)!,
      warnSoft: Color.lerp(warnSoft, o.warnSoft, t)!,
      bad: Color.lerp(bad, o.bad, t)!,
      badSoft: Color.lerp(badSoft, o.badSoft, t)!,
    );
  }
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
