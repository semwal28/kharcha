import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Auto / Light / Dark, remembered between launches.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController([super.value = ThemeMode.system]);

  static const _key = 'spendwell.theme_mode';

  static Future<ThemeController> load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_key);
      return ThemeController(ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system));
    } catch (_) {
      return ThemeController();
    }
  }

  /// Lets [change] find the reveal layer that sits inside MaterialApp.
  final revealKey = GlobalKey<ThemeRevealState>();

  /// True while a reveal plays. The app skips its own colour blend then,
  /// because the circle already shows the change.
  bool revealing = false;

  /// Switches theme. With [from] (a screen position), the new theme spreads
  /// out from that point in a growing circle.
  Future<void> change(ThemeMode mode, {Offset? from}) async {
    if (mode == value) return;
    final reveal = revealKey.currentState;
    if (from != null && reveal != null && reveal.canAnimate) {
      await reveal.capture();
      revealing = true;
      value = mode;
      reveal.play(from, onDone: () => revealing = false);
    } else {
      value = mode;
    }
    try {
      await (await SharedPreferences.getInstance()).setString(_key, mode.name);
    } catch (_) {
      // Not saved (e.g. storage unavailable): the choice still applies this session.
    }
  }
}

/// Makes the [ThemeController] reachable from anywhere below the app.
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({super.key, required ThemeController controller, required super.child}) : super(notifier: controller);

  static ThemeController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ThemeScope>()!.notifier!;
}

/// Draws the old screen on top of the new theme, then cuts a growing circle
/// out of it so the new theme spreads from where the user tapped.
class ThemeReveal extends StatefulWidget {
  const ThemeReveal({super.key, required this.child});
  final Widget child;

  @override
  State<ThemeReveal> createState() => ThemeRevealState();
}

class ThemeRevealState extends State<ThemeReveal> with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 750))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() {
          _image?.dispose();
          _image = null;
        });
      }
    });
  ui.Image? _image;
  Offset _origin = Offset.zero;

  bool get canAnimate => !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  Future<void> capture() async {
    final box = _boundary.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary) return;
    try {
      _image?.dispose();
      _image = await box.toImage(pixelRatio: MediaQuery.devicePixelRatioOf(context));
    } catch (_) {
      _image = null; // Screenshots unsupported here: switch without the effect.
    }
  }

  void play(Offset from, {VoidCallback? onDone}) {
    if (_image == null || !mounted) {
      onDone?.call();
      return;
    }
    setState(() => _origin = from);
    // The first frame in the new theme rebuilds the whole app and can be slow.
    // Start the circle after it, so that frame doesn't eat the animation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _c.forward(from: 0).whenComplete(() => onDone?.call());
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      RepaintBoundary(key: _boundary, child: widget.child),
      if (_image != null)
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(painter: _RevealPainter(_image!, _origin, Curves.easeInOutCubic.transform(_c.value))),
            ),
          ),
        ),
    ],
  );
}

class _RevealPainter extends CustomPainter {
  _RevealPainter(this.image, this.origin, this.t);
  final ui.Image image;
  final Offset origin;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final corners = [Offset.zero, Offset(size.width, 0), Offset(0, size.height), Offset(size.width, size.height)];
    final maxR = corners.map((c) => (c - origin).distance).reduce(math.max);
    final r = maxR * t;
    final visibleOld = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addOval(Rect.fromCircle(center: origin, radius: r)));
    canvas
      ..save()
      ..clipPath(visibleOld);
    paintImage(canvas: canvas, rect: Offset.zero & size, image: image, fit: BoxFit.fill, filterQuality: FilterQuality.medium);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RevealPainter o) => o.t != t || o.image != image;
}
