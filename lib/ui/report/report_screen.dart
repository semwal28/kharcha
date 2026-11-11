import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand.dart';
import '../../core/money.dart';
import '../../domain/report.dart';
import '../../services/export.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';

void openMonthReport(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportScreen()));

/// A one-card summary of a month that can be shared as a picture.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  final _card = GlobalKey();
  bool _lastMonth = false;
  bool _sharing = false;

  Future<void> _share(MonthReport r) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await Exporter.shareFile(
        png!.buffer.asUint8List(),
        name: '${kAppName.toLowerCase()}-${r.title.toLowerCase().replaceAll(' ', '-')}.png',
        mimeType: 'image/png',
        text: 'My ${r.title} spending, from $kAppName',
      );
    } catch (_) {
      if (mounted) toast(context, 'Couldn\'t share the report.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final data = ref.watch(appDataProvider).requireValue;
    final r = buildMonthReport(data, ref.watch(clockProvider)(), lastMonth: _lastMonth);
    return Scaffold(
      backgroundColor: k.bg,
      appBar: AppBar(backgroundColor: k.bg, surfaceTintColor: Colors.transparent, title: const Text('Monthly report')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          Center(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('This month')),
                ButtonSegment(value: true, label: Text('Last month')),
              ],
              selected: {_lastMonth},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _lastMonth = v.first),
            ),
          ),
          const SizedBox(height: 16),
          RepaintBoundary(
            key: _card,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, .04), end: Offset.zero).animate(a),
                  child: child,
                ),
              ),
              child: _ReportCard(key: ValueKey(_lastMonth), report: r),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: r.count == 0 || _sharing ? null : () => _share(r),
            icon: _sharing
                ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: k.accentInk))
                : const Icon(Icons.ios_share_rounded),
            label: const Text('Share as picture'),
            style: FilledButton.styleFrom(
              backgroundColor: k.accent,
              foregroundColor: k.accentInk,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 8),
          Text('Shows totals by category and your biggest spend.', textAlign: TextAlign.center, style: context.text.bodySmall),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({super.key, required this.report});
  final MonthReport report;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final r = report;
    final ink = k.heroInk;
    final soft = ink.withValues(alpha: .72);
    final top = r.categories.isEmpty ? 1 : r.categories.first.$2;
    final change = r.change;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [k.hero, k.hero2]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.title.toUpperCase(),
                  style: TextStyle(color: soft, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontSize: 12),
                ),
              ),
              if (change != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: ink.withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(change <= 0 ? Icons.south_east_rounded : Icons.north_east_rounded, size: 14, color: change <= 0 ? k.pop : ink),
                      const SizedBox(width: 3),
                      Text(
                        '${(change.abs() * 100).round()}% ${change <= 0 ? 'less' : 'more'}',
                        style: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('You spent', style: TextStyle(color: soft, fontSize: 14)),
          CountUp(
            value: r.total.toDouble(),
            format: Money.fmt,
            style: TextStyle(fontFamily: kDisplay, color: ink, fontSize: 40, fontWeight: FontWeight.w700, height: 1.1),
          ),
          const SizedBox(height: 4),
          Text(
            '${r.count} expenses · ${Money.fmt(r.dailyAverage)} a day'
            '${r.compareTo != null ? ' · vs ${Money.fmt(r.compareTo!)} ${r.compareLabel}' : ''}',
            style: TextStyle(color: soft, fontSize: 13),
          ),
          const SizedBox(height: 18),
          if (r.categories.isEmpty)
            Text('No expenses this month yet.', style: TextStyle(color: ink))
          else
            for (final (i, (c, amount)) in r.categories.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Enter(
                  index: i + 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(categoryIcon(c.isCustom ? 'tag' : c.icon), size: 16, color: soft),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              c.name,
                              style: TextStyle(color: ink, fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                          Text(
                            Money.fmt(amount),
                            style: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 13, fontFeatures: kTabular),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      GrowBar(
                        fraction: amount / top,
                        color: i == 0 ? k.pop : ink.withValues(alpha: .8),
                        track: ink.withValues(alpha: .14),
                        delay: Duration(milliseconds: 250 + 90 * i),
                      ),
                    ],
                  ),
                ),
              ),
          if (r.biggest != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: ink.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Icon(Icons.bolt_rounded, color: k.pop, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Biggest spend: ${r.biggest!.titleOr('one expense')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: ink, fontSize: 13),
                    ),
                  ),
                  Text(
                    Money.fmt(r.biggest!.amountPaise),
                    style: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 13, fontFeatures: kTabular),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              const BrandMark(size: 22),
              const SizedBox(width: 8),
              Text(
                kAppName,
                style: TextStyle(fontFamily: kDisplay, color: ink, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  kTagline,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: soft, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
