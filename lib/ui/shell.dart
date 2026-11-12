import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/brand.dart';
import '../services/export.dart';
import '../services/home_widget_sync.dart';
import 'app_lock.dart';
import 'currency_controller.dart';
import '../core/money.dart';
import '../data/local_repository.dart';
import '../state/app_state.dart';
import 'add/add_expense_sheet.dart';
import 'ask/ask_screen.dart';
import 'budgets/budgets_screen.dart';
import 'home/home_screen.dart';
import 'insights/insights_screen.dart';
import 'theme.dart';
import 'theme_controller.dart';
import 'tx/tx_sheet.dart';
import '../domain/recurring.dart';
import '../domain/streak.dart';
import 'widgets/budget_alert.dart';
import 'widgets/common.dart';
import 'widgets/motion.dart';
import 'widgets/success_burst.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _tab = 0;

  /// Bumped on each visit so a screen replays its entrance.
  final _visits = [0, 0, 0, 0];

  void _setTab(int i) {
    if (i == _tab) return;
    HapticFeedback.selectionClick();
    setState(() {
      _tab = i;
      _visits[i]++;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) HomeWidgetSync.push(ref.read(summaryProvider));
    });
  }

  Future<void> _add([AddPrefill? prefill]) async {
    final before = ref.read(summaryProvider);
    final result = await openAddSheet(context, prefill: prefill);
    if (result == null || !mounted) return;
    await showSuccessBurst(
      context,
      amount: Money.fmt(result.amountPaise),
      subtitle: '${result.categoryName}${result.newCategory ? ' (new category)' : ''} · ${result.when}',
    );
    if (!mounted) return;
    ref.read(justAddedProvider.notifier).mark(result.txnId);
    setState(() {
      _tab = 0;
      _visits[0]++;
    });
    toast(context, 'Added ${Money.fmt(result.amountPaise)} · ${result.categoryName}');
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) ref.read(justAddedProvider.notifier).mark(null);
    });
    final stat = ref.read(summaryProvider)?.cats[result.categoryId];
    if (stat != null) {
      final alert = budgetAlertFor(
        category: stat.category,
        beforePaise: before?.cats[result.categoryId]?.spent ?? 0,
        afterPaise: stat.spent,
        budgetPaise: stat.budget,
      );
      if (alert != null) showBudgetAlert(context, alert);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(appDataProvider);
    ref.listen(summaryProvider, (_, next) => HomeWidgetSync.push(next));
    ref.listen(appDataProvider, (prev, next) {
      if (prev?.value != null || next.value == null) return;
      final added = ref.read(appDataProvider.notifier).autoAdded;
      if (added.isNotEmpty) {
        toast(context, 'Added this month\'s ${added.length == 1 ? 'repeat expense' : '${added.length} repeat expenses'}: ${added.take(3).join(', ')}');
      }
    });
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TopBar(onSettings: () => _openSettings(context)),
            Expanded(
              child: switch (async) {
                AsyncData() => IndexedStack(
                  index: _tab,
                  children: [
                    HomeScreen(key: ValueKey('home${_visits[0]}'), onAdd: _add, onSeeTips: () => _setTab(1)),
                    InsightsScreen(key: ValueKey('insights${_visits[1]}')),
                    BudgetsScreen(key: ValueKey('budgets${_visits[2]}')),
                    const AskScreen(),
                  ],
                ),
                AsyncError(:final error) => _ErrorView(message: error.toString(), onRetry: () => ref.read(appDataProvider.notifier).refresh()),
                _ => const _LoadingSkeleton(),
              },
            ),
          ],
        ),
      ),
      floatingActionButton: _AddButton(onTap: () => _add()),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _TabBar(index: _tab, onTab: _setTab, onAdd: () => _add()),
    );
  }

  void _openSettings(BuildContext context) =>
      showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const _SettingsSheet());
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.onSettings});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final now = ref.watch(clockProvider)();
    final txns = ref.watch(appDataProvider).value?.txns ?? const [];
    final streak = loggingStreak(txns, now);
    Widget mark = const BrandMark(size: 34);
    if (!reduceMotion(context)) {
      mark = mark
          .animate()
          .rotate(begin: -.08, end: 0, duration: 700.ms, curve: Curves.elasticOut)
          .scaleXY(begin: .4, end: 1, duration: 700.ms, curve: Curves.elasticOut);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
      child: Row(
        children: [
          mark,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting(now),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: kDisplay, fontWeight: FontWeight.w700, fontSize: 20, letterSpacing: -.4, color: k.ink, height: 1.1),
                ),
                Text('$kAppName · ${monthNames[now.month - 1]} ${now.year}', style: context.text.bodySmall),
              ],
            ),
          ),
          if (streak >= 2) _StreakChip(days: streak),
          IconButton(
            onPressed: onSettings,
            icon: Icon(Icons.tune_rounded, color: k.ink2),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}

/// "🔥 5": days in a row with something logged. Keeps people coming back.
class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    Widget chip = Tooltip(
      message: '$days-day streak: you\'ve logged spending $days days in a row',
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 11, 5),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [k.popSoft, Color.lerp(k.popSoft, k.badSoft, .5)!]),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: k.pop.withValues(alpha: .45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_fire_department_rounded, size: 18, color: Color(0xFFFF6B2C)),
            const SizedBox(width: 3),
            Text(
              '$days',
              style: TextStyle(fontFamily: kDisplay, fontWeight: FontWeight.w700, fontSize: 15, color: k.ink, fontFeatures: kTabular),
            ),
          ],
        ),
      ),
    );
    if (!reduceMotion(context)) {
      chip = chip.animate(key: ValueKey(days)).scaleXY(begin: .5, end: 1, duration: 600.ms, curve: Curves.elasticOut);
    }
    return Semantics(label: '$days-day streak', child: chip);
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onTab, required this.onAdd});
  final int index;
  final ValueChanged<int> onTab;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    const items = [
      (Icons.home_outlined, Icons.home_rounded, 'Home'),
      (Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'Insights'),
      (Icons.flag_outlined, Icons.flag_rounded, 'Plan'),
      (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Ask AI'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: k.surface,
        border: Border(top: BorderSide(color: k.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth / 5;
              final slot = index < 2 ? index : index + 1; // the middle slot is the add button
              Widget tab(int i) {
                final (icon, active, label) = items[i];
                final sel = i == index;
                return Expanded(
                  child: Semantics(
                    selected: sel,
                    button: true,
                    label: label,
                    child: InkWell(
                      onTap: () => onTab(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedScale(
                            scale: sel ? 1.12 : 1,
                            duration: const Duration(milliseconds: 380),
                            curve: Curves.elasticOut,
                            child: Icon(sel ? active : icon, size: 23, color: sel ? k.accent : k.muted),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            label,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sel ? k.accent : k.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutBack,
                    left: slot * w + w / 2 - 28,
                    top: 7,
                    child: Container(
                      width: 56,
                      height: 30,
                      decoration: BoxDecoration(color: k.accentSoft, borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  Row(
                    children: [
                      tab(0),
                      tab(1),
                      Expanded(
                        child: InkWell(
                          onTap: onAdd,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                'Add',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: k.muted),
                              ),
                              const SizedBox(height: 9),
                            ],
                          ),
                        ),
                      ),
                      tab(2),
                      tab(3),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The yellow + in the middle of the tab bar, with a soft pulse.
class _AddButton extends StatefulWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..repeat();
  bool _down = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final still = reduceMotion(context);
    return Semantics(
      button: true,
      label: 'Add expense',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onTap();
        },
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final t = still ? 1.0 : (_pulse.value / .7).clamp(0.0, 1.0);
              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: k.pop.withValues(alpha: .35), blurRadius: 16, offset: const Offset(0, 5)),
                    if (!still)
                      BoxShadow(
                        color: k.pop.withValues(alpha: .4 * (1 - t)),
                        spreadRadius: 14 * t,
                      ),
                  ],
                ),
                child: child,
              );
            },
            child: AnimatedScale(
              scale: _down ? .88 : 1,
              duration: const Duration(milliseconds: 140),
              child: AnimatedRotation(
                turns: _down ? .125 : 0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [k.pop, Color.lerp(k.pop, const Color(0xFFFF5E62), .55)!],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: k.surface, width: 4),
                  ),
                  child: Icon(Icons.add_rounded, size: 30, color: k.popInk),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 40, color: context.k.muted),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center, style: context.text.bodyMedium),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class _SettingsSheet extends ConsumerStatefulWidget {
  const _SettingsSheet();
  @override
  ConsumerState<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends ConsumerState<_SettingsSheet> {
  late final _income = TextEditingController(
    text: () {
      final p = ref.read(appDataProvider).value?.profile.monthlyIncomePaise ?? 0;
      return p > 0 ? '${(p / 100).round()}' : '';
    }(),
  );

  @override
  void dispose() {
    _income.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final profile = ref.watch(appDataProvider).value?.profile;
    final exitGuest = ref.watch(exitGuestProvider);
    final currency = CurrencyScope.of(context).value;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Settings', style: context.text.titleLarge),
          const SizedBox(height: 4),
          Text(
            repo.isLocal ? (repo.hasExampleData ? 'On this phone · example data' : 'Saved on this phone') : (profile?.email ?? 'Signed in'),
            style: context.text.bodySmall,
          ),
          const SizedBox(height: 16),
          Text('Monthly take-home income', style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _income,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                  decoration: InputDecoration(prefixText: '${Money.symbol} ', hintText: 'Monthly amount'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  final rupees = int.tryParse(_income.text) ?? 0;
                  final nav = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref.read(appDataProvider.notifier).setIncome(rupees * 100);
                    nav.pop();
                    messenger.showSnackBar(const SnackBar(content: Text('Income saved')));
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                },
                style: FilledButton.styleFrom(minimumSize: const Size(80, 46)),
                child: const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Appearance', style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const _ThemePicker(),
          const SizedBox(height: 14),
          _SettingsButton(
            icon: Icons.currency_exchange_rounded,
            label: 'Currency',
            caption: '${currency.name} (${currency.symbol.trim()})',
            onTap: _pickCurrency,
          ),
          const SizedBox(height: 8),
          const _AppLockRow(),
          _SettingsButton(
            icon: Icons.table_view_outlined,
            label: 'Export to CSV',
            caption: 'Every expense, for Excel or Google Sheets.',
            onTap: () => _export(pdf: false),
          ),
          const SizedBox(height: 8),
          _SettingsButton(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Export PDF report',
            caption: 'This month: totals, categories, tips, expenses.',
            onTap: () => _export(pdf: true),
          ),
          if (HomeWidgetSync.supported) ...[
            const SizedBox(height: 8),
            const _InfoRow(icon: Icons.widgets_outlined, text: 'Add the Spendwell widget: long-press your home screen, tap Widgets, then Spendwell.'),
          ],
          const SizedBox(height: 20),
          if (exitGuest != null) ...[
            _SettingsButton(
              icon: Icons.cloud_upload_outlined,
              label: 'Sign in to back up and sync',
              caption: 'Use the app on any device. Data on this device stays here.',
              onTap: () {
                Navigator.of(context).pop();
                exitGuest();
              },
            ),
            const SizedBox(height: 8),
          ],
          if (repo is LocalRepository) ...[
            if (repo.hasExampleData)
              _SettingsButton(
                icon: Icons.cleaning_services_outlined,
                label: 'Start fresh',
                caption: 'Clears the example data so you can add your own.',
                onTap: () => _confirm(
                  title: 'Start fresh?',
                  body: 'This removes all example expenses, budgets and goals. Everything starts at 0.',
                  action: 'Start fresh',
                  run: repo.startFresh,
                  done: 'Ready for your own expenses',
                ),
              )
            else
              _SettingsButton(
                icon: Icons.auto_awesome_motion_outlined,
                label: 'Load example data',
                caption: 'Replaces your expenses with two months of examples.',
                onTap: () => _confirm(
                  title: 'Load example data?',
                  body: 'This replaces everything you added with example data.',
                  action: 'Load examples',
                  run: repo.loadExampleData,
                  done: 'Example data loaded',
                ),
              ),
          ] else ...[
            _SettingsButton(
              icon: Icons.logout_rounded,
              label: 'Sign out',
              onTap: () async {
                Navigator.of(context).pop();
                await repo.signOut();
              },
            ),
            const SizedBox(height: 8),
            _SettingsButton(
              icon: Icons.delete_forever_outlined,
              label: 'Delete account',
              danger: true,
              caption: 'Deletes your account and every expense, for good.',
              onTap: () => _confirm(
                title: 'Delete your account?',
                body: 'Your account, expenses, categories and budgets will be deleted for good. This can\'t be undone.',
                action: 'Delete',
                danger: true,
                run: repo.deleteAccount,
                done: 'Account deleted',
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text('$kAppName $kAppVersion', textAlign: TextAlign.center, style: context.text.bodySmall),
        ],
      ),
    );
  }

  Future<void> _pickCurrency() async {
    final ctl = CurrencyScope.of(context);
    final picked = await showModalBottomSheet<Currency>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CurrencySheet(selected: ctl.value),
    );
    if (picked == null || picked.code == ctl.value.code || !mounted) return;
    final repo = ref.read(repositoryProvider);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await ctl.change(picked);
    if (repo is LocalRepository && repo.hasExampleData) await repo.loadExampleData();
    ref.invalidate(summaryProvider);
    await ref.read(appDataProvider.notifier).refresh();
    if (!mounted) return;
    nav.pop();
    messenger.showSnackBar(SnackBar(content: Text('Amounts now shown in ${picked.name}')));
  }

  Future<void> _export({required bool pdf}) async {
    final data = ref.read(appDataProvider).value;
    final s = ref.read(summaryProvider);
    if (data == null || s == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      pdf ? await Exporter.sharePdf(data, s) : await Exporter.shareCsv(data);
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('Couldn\'t share the file on this device.')));
    }
  }

  Future<void> _confirm({
    required String title,
    required String body,
    required String action,
    required Future<void> Function() run,
    required String done,
    bool danger = false,
  }) async {
    final k = context.k;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: danger ? FilledButton.styleFrom(backgroundColor: k.bad, foregroundColor: Colors.white) : null,
            child: Text(action),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await run();
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      return;
    }
    // After deleting an account the app returns to sign-in and this sheet is gone.
    if (!mounted) return;
    if (ref.read(repositoryProvider).isLocal) await ref.read(appDataProvider.notifier).refresh();
    if (!mounted) return;
    nav.pop();
    messenger.showSnackBar(SnackBar(content: Text(done)));
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.icon, required this.label, required this.onTap, this.caption, this.danger = false});
  final IconData icon;
  final String label;
  final String? caption;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final color = danger ? k.bad : k.ink;
    return Material(
      color: k.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: k.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(fontWeight: FontWeight.w600, color: color),
                    ),
                    if (caption != null) Text(caption!, style: context.text.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: k.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Auto / Light / Dark. The new theme spreads from the tapped button.
class _ThemePicker extends StatelessWidget {
  const _ThemePicker();

  static const _options = [
    (ThemeMode.system, Icons.brightness_auto_rounded, 'Auto'),
    (ThemeMode.light, Icons.light_mode_rounded, 'Light'),
    (ThemeMode.dark, Icons.dark_mode_rounded, 'Dark'),
  ];

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final controller = ThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: k.surface2, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          for (final (mode, icon, label) in _options)
            Expanded(
              child: Semantics(
                button: true,
                selected: controller.value == mode,
                label: '$label theme',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    HapticFeedback.selectionClick();
                    controller.change(mode, from: d.globalPosition);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: controller.value == mode ? k.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: controller.value == mode
                          ? [BoxShadow(color: Colors.black.withValues(alpha: .1), blurRadius: 4, offset: const Offset(0, 1))]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedRotation(
                          turns: controller.value == mode ? 0 : -.25,
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeOutBack,
                          child: AnimatedScale(
                            scale: controller.value == mode ? 1.15 : 1,
                            duration: const Duration(milliseconds: 450),
                            curve: Curves.elasticOut,
                            child: Icon(icon, size: 18, color: controller.value == mode ? k.accent : k.muted),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: controller.value == mode ? k.ink : k.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shimmering outline of the Home screen while data loads.
class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
    children: const [
      ShimmerBox(height: 200, radius: 20),
      SizedBox(height: 20),
      ShimmerBox(height: 18, width: 110, radius: 6),
      SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: ShimmerBox(height: 54, radius: 14)),
          SizedBox(width: 8),
          Expanded(child: ShimmerBox(height: 54, radius: 14)),
          SizedBox(width: 8),
          Expanded(child: ShimmerBox(height: 54, radius: 14)),
        ],
      ),
      SizedBox(height: 16),
      ShimmerBox(height: 130),
      SizedBox(height: 16),
      ShimmerBox(height: 220),
    ],
  );
}

class _CurrencySheet extends StatelessWidget {
  const _CurrencySheet({required this.selected});
  final Currency selected;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      children: [
        Text('Currency', style: context.text.titleLarge),
        const SizedBox(height: 4),
        Text('Changes how amounts are shown. Amounts you already added are not converted.', style: context.text.bodySmall),
        const SizedBox(height: 10),
        for (final (i, c) in kCurrencies.indexed)
          Enter(
            index: i,
            child: Squish(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: CircleAvatar(
                  backgroundColor: c.code == selected.code ? k.accent : k.surface2,
                  foregroundColor: c.code == selected.code ? k.accentInk : k.ink,
                  child: Text(c.symbol.trim().length > 2 ? c.code.substring(0, 2) : c.symbol.trim(), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(c.code),
                trailing: c.code == selected.code ? Icon(Icons.check_circle_rounded, color: k.accent) : null,
                onTap: () => Navigator.pop(context, c),
              ),
            ),
          ),
      ],
    );
  }
}

/// Fingerprint / face lock switch. Hidden where the device can't do it.
class _AppLockRow extends StatefulWidget {
  const _AppLockRow();
  @override
  State<_AppLockRow> createState() => _AppLockRowState();
}

class _AppLockRowState extends State<_AppLockRow> {
  late final Future<bool> _available = AppLock.available();
  bool _on = AppLock.enabled;

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _available,
    builder: (context, snap) {
      if (snap.data != true) return const SizedBox.shrink();
      final k = context.k;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: k.bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: k.line),
          ),
          child: SwitchListTile(
            value: _on,
            activeThumbColor: k.accent,
            secondary: Icon(Icons.fingerprint_rounded, color: k.ink),
            title: const Text('App lock', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Ask for fingerprint, face or PIN to open', style: context.text.bodySmall),
            onChanged: (v) async {
              final ok = await AppLock.setEnabled(v);
              if (!mounted) return;
              if (ok) {
                setState(() => _on = v);
              } else if (context.mounted) {
                toast(context, 'App lock was not turned on.');
              }
            },
          ),
        ),
      );
    },
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: context.k.accentSoft, borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        Icon(icon, color: context.k.accent, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: context.text.bodySmall?.copyWith(color: context.k.ink2)),
        ),
      ],
    ),
  );
}
