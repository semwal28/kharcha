import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../theme.dart';
import 'motion.dart';

/// Full-screen "Added!" moment: a tick draws itself and ₹ coins burst out.
Future<void> showSuccessBurst(BuildContext context, {required String amount, required String subtitle}) async {
  final still = reduceMotion(context);
  final theme = Theme.of(context);
  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (_) => Theme(
      data: theme,
      child: _SuccessOverlay(amount: amount, subtitle: subtitle, still: still),
    ),
  );
  overlay.insert(entry);
  await Future.delayed(Duration(milliseconds: still ? 600 : 1250));
  entry.remove();
}

class _SuccessOverlay extends StatefulWidget {
  const _SuccessOverlay({required this.amount, required this.subtitle, required this.still});
  final String amount;
  final String subtitle;
  final bool still;

  @override
  State<_SuccessOverlay> createState() => _SuccessOverlayState();
}

class _Particle {
  _Particle(math.Random r, this.coin)
    : angle = r.nextDouble() * 2 * math.pi,
      dist = 80 + r.nextDouble() * 130,
      spin = (r.nextDouble() - .5) * 9,
      delay = r.nextDouble() * .08,
      colorIndex = r.nextInt(4);
  final bool coin;
  final double angle, dist, spin, delay;
  final int colorIndex;
}

class _SuccessOverlayState extends State<_SuccessOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1250));
  final _particles = () {
    final r = math.Random();
    return [for (var i = 0; i < 28; i++) _Particle(r, i % 3 == 0)];
  }();

  @override
  void initState() {
    super.initState();
    if (widget.still) {
      _c.value = .7;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final veil = t < .12 ? t / .12 : (t > .88 ? (1 - t) / .12 : 1.0);
          final pop = Curves.elasticOut.transform(((t - .2) / .5).clamp(0, 1));
          return Opacity(
            opacity: veil.clamp(0, 1),
            child: Container(
              color: k.bg.withValues(alpha: .95),
              child: Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: _BurstPainter(t, _particles, [k.pop, k.accent, k.good, k.bar], k.popInk))),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(dimension: 96, child: CustomPaint(painter: _CheckPainter(t, k.good))),
                        const SizedBox(height: 10),
                        Transform.scale(
                          scale: .6 + .4 * pop,
                          child: Text(widget.amount, style: context.text.displayMedium?.copyWith(fontFeatures: kTabular)),
                        ),
                        const SizedBox(height: 4),
                        Text(widget.subtitle, style: context.text.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final ring = Curves.easeOutCubic.transform((t / .4).clamp(0, 1));
    final tick = Curves.easeOutCubic.transform(((t - .3) / .3).clamp(0, 1));
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final c = s.center(Offset.zero);
    canvas.drawArc(Rect.fromCircle(center: c, radius: s.width * .44), -math.pi / 2, 2 * math.pi * ring, false, p..strokeWidth = 4);
    final path = Path()
      ..moveTo(s.width * .30, s.height * .52)
      ..lineTo(s.width * .44, s.height * .65)
      ..lineTo(s.width * .70, s.height * .38);
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * tick), p..strokeWidth = 5.5);
    }
  }

  @override
  bool shouldRepaint(_CheckPainter o) => o.t != t;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, this.particles, this.colors, this.coinInk);
  final double t;
  final List<_Particle> particles;
  final List<Color> colors;
  final Color coinInk;

  @override
  void paint(Canvas canvas, Size s) {
    final origin = Offset(s.width / 2, s.height / 2 - 40);
    final rupee = TextPainter(
      text: TextSpan(
        text: Money.symbol.characters.first,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: coinInk),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    for (final p in particles) {
      final local = ((t - .12 - p.delay) / .75).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final e = Curves.easeOutCubic.transform(local);
      final pos = origin + Offset(math.cos(p.angle), math.sin(p.angle)) * p.dist * e + Offset(0, 60 * local * local);
      final alpha = (1 - math.pow(local, 3)).toDouble();
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.spin * e);
      if (p.coin) {
        canvas.drawCircle(Offset.zero, 9, Paint()..color = colors[0].withValues(alpha: alpha));
        rupee.paint(canvas, Offset(-rupee.width / 2, -rupee.height / 2));
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(-3.5, -6, 7, 12), const Radius.circular(2)),
          Paint()..color = colors[p.colorIndex].withValues(alpha: alpha),
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter o) => o.t != t;
}
