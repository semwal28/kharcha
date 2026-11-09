import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme.dart';

bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Rises and fades a block in, staggered by [index]. Used for every screen entrance.
class Enter extends StatelessWidget {
  const Enter({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    return child
        .animate(delay: (index * 70).ms)
        .fadeIn(duration: 420.ms, curve: Curves.easeOut)
        .slideY(begin: .08, end: 0, duration: 560.ms, curve: Curves.easeOutCubic)
        .scaleXY(begin: .985, end: 1, duration: 560.ms, curve: Curves.easeOutCubic);
  }
}

/// Animates a number from its old value (0 at first) to [value] after [delay].
class Grow extends StatefulWidget {
  const Grow({
    super.key,
    required this.value,
    required this.builder,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOutCubic,
  });

  final double value;
  final Duration delay;
  final Duration duration;
  final Curve curve;
  final Widget Function(BuildContext context, double value) builder;

  @override
  State<Grow> createState() => _GrowState();
}

class _GrowState extends State<Grow> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  double _from = 0;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void didUpdateWidget(Grow old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _from = lerpDouble(_from, old.value, widget.curve.transform(_c.value))!;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.builder(context, widget.value);
    return AnimatedBuilder(animation: _c, builder: (context, _) => widget.builder(context, lerpDouble(_from, widget.value, widget.curve.transform(_c.value))!));
  }
}

/// Counts a number up, formatted by [format].
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, required this.format, this.style, this.delay = Duration.zero});
  final double value;
  final String Function(double) format;
  final TextStyle? style;
  final Duration delay;

  @override
  Widget build(BuildContext context) => Grow(
    value: value,
    delay: delay,
    duration: const Duration(milliseconds: 1100),
    builder: (context, v) => Text(format(v), style: (style ?? const TextStyle()).copyWith(fontFeatures: kTabular)),
  );
}

/// Rolling digits, like a fuel meter. Rightmost digit settles first.
class Odometer extends StatefulWidget {
  const Odometer({super.key, required this.text, required this.style, this.semanticsLabel});
  final String text;
  final TextStyle style;
  final String? semanticsLabel;

  @override
  State<Odometer> createState() => _OdometerState();
}

class _OdometerState extends State<Odometer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void didUpdateWidget(Odometer old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style.copyWith(fontFeatures: kTabular, height: 1.1);
    final tp = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width, h = tp.height;
    final still = reduceMotion(context);
    final digits = widget.text.runes.where((r) => r >= 48 && r <= 57).length;
    var seen = 0;
    final children = <Widget>[];
    for (final ch in widget.text.split('')) {
      final d = int.tryParse(ch);
      if (d == null) {
        children.add(Text(ch, style: style));
        continue;
      }
      final order = digits - seen++; // 1 = rightmost
      final start = math.min(.35, (order - 1) * .05);
      final anim = CurvedAnimation(
        parent: _c,
        curve: Interval(start, math.min(1, start + .65), curve: Curves.easeOutCubic),
      );
      children.add(
        SizedBox(
          width: w,
          height: h,
          child: ClipRect(
            child: still
                ? Text('$d', style: style)
                : AnimatedBuilder(
                    animation: anim,
                    builder: (context, _) {
                      final pos = anim.value * (10 + d); // spin one full turn, then land
                      final a = pos.floor();
                      final frac = pos - a;
                      return Stack(
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            top: -frac * h,
                            child: Text('${a % 10}', style: style, textAlign: TextAlign.center),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            top: (1 - frac) * h,
                            child: Text('${(a + 1) % 10}', style: style, textAlign: TextAlign.center),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ),
      );
    }
    return Semantics(
      label: widget.semanticsLabel ?? widget.text,
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

/// Circular progress that draws itself.
class Ring extends StatelessWidget {
  const Ring({super.key, required this.fraction, required this.size, required this.stroke, required this.track, required this.color, this.child});
  final double fraction;
  final double size;
  final double stroke;
  final Color track;
  final Color color;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Grow(
      value: fraction.clamp(0, 1).toDouble(),
      delay: const Duration(milliseconds: 250),
      duration: const Duration(milliseconds: 1400),
      builder: (context, v) => CustomPaint(
        painter: _RingPainter(v, stroke, track, color),
        child: Center(child: child),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.stroke, this.track, this.color);
  final double v, stroke;
  final Color track, color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.shortestSide - stroke) / 2;
    final c = size.center(Offset.zero);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, p..color = track);
    if (v > 0) canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * v, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color || o.track != track;
}

/// Thin horizontal bar that grows from the left, with an optional marker
/// (last month, or "today" on the hero card).
class GrowBar extends StatelessWidget {
  const GrowBar({
    super.key,
    required this.fraction,
    required this.color,
    required this.track,
    this.marker,
    this.markerColor,
    this.height = 6,
    this.delay = const Duration(milliseconds: 200),
  });

  final double fraction;
  final Color color;
  final Color track;
  final double? marker;
  final Color? markerColor;
  final double height;
  final Duration delay;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SizedBox(
      height: height + 6,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Container(
            height: height,
            decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(99)),
          ),
          Grow(
            value: fraction.clamp(0, 1).toDouble(),
            delay: delay,
            builder: (context, v) => Container(
              width: box.maxWidth * v,
              height: height,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99)),
            ),
          ),
          if (marker != null)
            Positioned(
              left: (box.maxWidth * marker!.clamp(0, 1)) - 1,
              top: 0,
              bottom: 0,
              child: Container(
                width: 2,
                decoration: BoxDecoration(color: markerColor ?? context.k.ink2, borderRadius: BorderRadius.circular(2)),
              ),
            ),
        ],
      ),
    ),
  );
}
