import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../theme.dart';

/// A short launch animation: the logo springs in, the name types itself
/// letter by letter, then the whole card lifts away to reveal the app.
/// Plays once per launch and is skipped when "reduce motion" is on.
class IntroOverlay extends StatefulWidget {
  const IntroOverlay({super.key, required this.child});
  final Widget child;

  static bool _played = false;

  @override
  State<IntroOverlay> createState() => _IntroOverlayState();
}

class _IntroOverlayState extends State<IntroOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  bool _done = IntroOverlay._played;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_done || _c.isAnimating) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      IntroOverlay._played = true;
      _done = true;
      return;
    }
    IntroOverlay._played = true;
    _c.forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _span(double a, double b, [Curve curve = Curves.easeOutCubic]) => curve.transform(((_c.value - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    final k = context.k;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: AbsorbPointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final out = _span(.74, 1, Curves.easeInCubic);
                final logo = _span(0, .42, Curves.elasticOut);
                const letters = kAppName;
                return Opacity(
                  opacity: 1 - out,
                  child: Transform.translate(
                    offset: Offset(0, -40 * out),
                    child: Material(
                      color: k.bg,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Transform.rotate(
                              angle: (1 - logo) * -.5,
                              child: Transform.scale(scale: .3 + .7 * logo, child: const BrandMark(size: 76)),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < letters.length; i++)
                                  Builder(
                                    builder: (context) {
                                      final a = _span(.2 + i * .035, .45 + i * .035, Curves.easeOutBack);
                                      return Opacity(
                                        opacity: a.clamp(0, 1),
                                        child: Transform.translate(
                                          offset: Offset(0, 14 * (1 - a)),
                                          child: Text(
                                            letters[i],
                                            style: TextStyle(fontFamily: kDisplay, fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -.6, color: k.ink),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Opacity(
                              opacity: _span(.5, .7),
                              child: Text(
                                kTagline,
                                style: TextStyle(fontFamily: kBody, fontSize: 14, color: k.muted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
