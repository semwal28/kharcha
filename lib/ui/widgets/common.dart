import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../domain/analysis.dart';
import '../theme.dart';
import 'motion.dart';

const _icons = <String, IconData>{
  'dining': Icons.local_cafe_outlined,
  'delivery': Icons.delivery_dining_outlined,
  'groceries': Icons.shopping_cart_outlined,
  'transport': Icons.directions_car_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'bills': Icons.bolt_outlined,
  'fun': Icons.confirmation_number_outlined,
  'health': Icons.favorite_border,
  'care': Icons.content_cut,
  'subs': Icons.autorenew,
  'rent': Icons.home_outlined,
  'fees': Icons.error_outline,
  'other': Icons.more_horiz,
  'tag': Icons.sell_outlined,
};

IconData categoryIcon(String key) => _icons[key] ?? Icons.sell_outlined;

/// Each category has its own colour, so lists and charts read at a glance.
const _catColors = <String, Color>{
  'dining': Color(0xFFF97316),
  'delivery': Color(0xFFF43F5E),
  'groceries': Color(0xFF16A34A),
  'transport': Color(0xFF2563EB),
  'shopping': Color(0xFF9333EA),
  'bills': Color(0xFFD97706),
  'fun': Color(0xFFDB2777),
  'health': Color(0xFF0D9488),
  'care': Color(0xFFC026D3),
  'subs': Color(0xFF4F46E5),
  'rent': Color(0xFF0284C7),
  'fees': Color(0xFFDC2626),
  'other': Color(0xFF64748B),
  'tag': Color(0xFF7C3AED),
};

/// The category's colour, lightened in dark mode so it stays readable.
Color categoryColor(BuildContext context, String key) {
  final c = _catColors[key] ?? _catColors['tag']!;
  return Theme.of(context).brightness == Brightness.dark ? Color.lerp(c, Colors.white, .32)! : c;
}

class CatIcon extends StatelessWidget {
  const CatIcon(this.icon, {super.key, this.size = 34, this.bg, this.fg});
  final String icon;
  final double size;
  final Color? bg;
  final Color? fg;

  @override
  Widget build(BuildContext context) {
    final c = categoryColor(context, icon);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg ?? c.withValues(alpha: dark ? .2 : .13),
        borderRadius: BorderRadius.circular(size * .3),
      ),
      child: Icon(categoryIcon(icon), size: size * .52, color: fg ?? c),
    );
  }
}

class KCard extends StatelessWidget {
  const KCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? context.k.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.k.line),
      boxShadow: [BoxShadow(color: context.k.accent.withValues(alpha: .07), blurRadius: 18, offset: const Offset(0, 6))],
    ),
    child: child,
  );
}

enum PillKind { good, warn, bad, info }

class Pill extends StatelessWidget {
  const Pill(this.kind, this.text, {super.key});
  final PillKind kind;
  final String text;

  factory Pill.forLeak(LeakKind k) => switch (k) {
    LeakKind.leak => const Pill(PillKind.bad, 'Leak'),
    LeakKind.habit => const Pill(PillKind.warn, 'Habit'),
    LeakKind.alert => const Pill(PillKind.info, 'Check'),
  };

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final (bg, fg, icon) = switch (kind) {
      PillKind.good => (k.goodSoft, k.good, Icons.check_rounded),
      PillKind.warn => (k.warnSoft, k.warn, Icons.schedule_rounded),
      PillKind.bad => (k.badSoft, k.bad, Icons.warning_amber_rounded),
      PillKind.info => (k.accentSoft, k.accent, Icons.info_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: Text(title, style: context.text.titleMedium)),
        ?trailing,
      ],
    ),
  );
}

class LinkButton extends StatelessWidget {
  const LinkButton(this.label, {super.key, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Text(
        label,
        style: TextStyle(color: context.k.accent, fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
  );
}

/// "→ Do this" line used under tips.
class ActionLine extends StatelessWidget {
  const ActionLine(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(Icons.arrow_forward_rounded, size: 15, color: context.k.accent),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.k.accent),
        ),
      ),
    ],
  );
}

class LeakTile extends StatelessWidget {
  const LeakTile(this.leak, {super.key});
  final Leak leak;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(leak.title, style: context.text.titleSmall)),
            const SizedBox(width: 8),
            Text(
              leak.saveText,
              style: TextStyle(fontWeight: FontWeight.w700, color: context.k.good, fontFeatures: kTabular),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Pill.forLeak(leak.kind),
            Text(leak.detail, style: context.text.bodyMedium?.copyWith(fontSize: 13)),
          ],
        ),
        const SizedBox(height: 6),
        ActionLine(leak.action),
      ],
    ),
  );
}

/// Slow-moving colour glow and floating ₹ signs behind the hero card.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, required this.child});
  final Widget child;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final still = reduceMotion(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = still ? 0.0 : _c.value * 2 * math.pi;
          return CustomPaint(
            painter: _AuroraPainter(t, k.hero, k.hero2, k.aurora1, k.aurora2),
            child: Stack(
              children: [
                for (final (i, (x, y, size)) in const [(0.66, 0.70, 64.0), (0.88, 0.48, 34.0), (0.52, 0.06, 24.0)].indexed)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment(x * 2 - 1, y * 2 - 1),
                      child: Transform.translate(
                        offset: Offset(0, math.sin(t * 3 + i * 2) * 7),
                        child: Transform.rotate(
                          angle: math.sin(t * 3 + i) * .14,
                          child: Text(
                            Money.symbol.characters.first,
                            style: TextStyle(fontFamily: kDisplay, fontWeight: FontWeight.w700, fontSize: size, color: k.heroInk.withValues(alpha: .1)),
                          ),
                        ),
                      ),
                    ),
                  ),
                child!,
              ],
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t, this.a, this.b, this.g1, this.g2);
  final double t;
  final Color a, b, g1, g2;

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b]).createShader(rect));
    void blob(Offset c, double r, Color col) {
      canvas.drawCircle(c, r, Paint()..shader = RadialGradient(colors: [col, col.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r)));
    }

    blob(Offset(s.width * (.28 + .08 * math.sin(t)), s.height * (.32 + .1 * math.cos(t))), s.width * .55, g1);
    blob(Offset(s.width * (.75 + .07 * math.cos(t * .8)), s.height * (.65 + .1 * math.sin(t * .8))), s.width * .6, g2);
  }

  @override
  bool shouldRepaint(_AuroraPainter o) => o.t != t || o.a != a;
}

/// Card edge with a slowly turning gradient. Marks AI tips.
class GlowBorderCard extends StatefulWidget {
  const GlowBorderCard({super.key, required this.child});
  final Widget child;

  @override
  State<GlowBorderCard> createState() => _GlowBorderCardState();
}

class _GlowBorderCardState extends State<GlowBorderCard> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final still = reduceMotion(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) =>
          CustomPaint(foregroundPainter: _GlowBorderPainter(still ? 0 : _c.value * 2 * math.pi, [k.accent, k.pop, k.good, k.accent]), child: child),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: k.surface, borderRadius: BorderRadius.circular(18)),
        child: widget.child,
      ),
    );
  }
}

class _GlowBorderPainter extends CustomPainter {
  _GlowBorderPainter(this.angle, this.colors);
  final double angle;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(.75);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(18)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = SweepGradient(colors: colors, transform: GradientRotation(angle)).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlowBorderPainter o) => o.angle != angle;
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(milliseconds: 2400)));
}
