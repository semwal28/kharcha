import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../domain/recurring.dart';
import '../theme.dart';
import 'motion.dart';

/// A banner that drops in from the top when an expense pushes a category past
/// 80% or 100% of its budget. Its bar fills to the new level, then it leaves.
void showBudgetAlert(BuildContext context, BudgetAlert alert) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _BudgetAlertBanner(alert: alert, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _BudgetAlertBanner extends StatefulWidget {
  const _BudgetAlertBanner({required this.alert, required this.onDone});
  final BudgetAlert alert;
  final VoidCallback onDone;

  @override
  State<_BudgetAlertBanner> createState() => _BudgetAlertBannerState();
}

class _BudgetAlertBannerState extends State<_BudgetAlertBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4600));
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _c.animateTo(1, duration: const Duration(milliseconds: 250));
  }

  double _span(double a, double b, Curve curve) => curve.transform(((_c.value - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final a = widget.alert;
    final color = a.over ? k.bad : k.warn;
    final soft = a.over ? k.badSoft : k.warnSoft;
    final still = reduceMotion(context);
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final inT = still ? 1.0 : _span(0, .12, Curves.easeOutBack);
            final outT = still ? 0.0 : _span(.88, 1, Curves.easeInCubic);
            return Opacity(
              opacity: (1 - outT).clamp(0, 1),
              child: Transform.translate(offset: Offset(0, -90 * (1 - inT) - 60 * outT), child: child),
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Material(
              color: k.surface,
              elevation: 8,
              shadowColor: Colors.black26,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: color.withValues(alpha: .5)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _close,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
                        child: Icon(a.over ? Icons.warning_amber_rounded : Icons.notifications_active_outlined, color: color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              a.message,
                              style: TextStyle(fontWeight: FontWeight.w700, color: k.ink, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text('${Money.fmt(a.spentPaise)} of ${Money.fmt(a.budgetPaise)} this month', style: context.text.bodySmall),
                            const SizedBox(height: 6),
                            GrowBar(fraction: a.spentPaise / a.budgetPaise, color: color, track: k.surface2, delay: const Duration(milliseconds: 350)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
