import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/money.dart';
import '../data/local_repository.dart';
import '../state/app_state.dart';
import 'add/add_expense_sheet.dart';
import 'ask/ask_screen.dart';
import 'budgets/budgets_screen.dart';
import 'home/home_screen.dart';
import 'insights/insights_screen.dart';
import 'theme.dart';
import 'tx/tx_sheet.dart';
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

  Future<void> _add([AddPrefill? prefill]) async {
    final result = await openAddSheet(context, prefill: prefill);
    if (result == null || !mounted) return;
    await showSuccessBurst(
      context,
      amount: Money.inr(result.amountPaise),
      subtitle: '${result.categoryName}${result.newCategory ? ' (new category)' : ''} · ${result.when}',
    );
    if (!mounted) return;
    ref.read(justAddedProvider.notifier).mark(result.txnId);
    setState(() {
      _tab = 0;
      _visits[0]++;
    });
    toast(context, 'Added ${Money.inr(result.amountPaise)} · ${result.categoryName}');
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) ref.read(justAddedProvider.notifier).mark(null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(appDataProvider);
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
                _ => const Center(child: CircularProgressIndicator()),
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
    Widget mark = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(color: k.accent, borderRadius: BorderRadius.circular(10)),
      alignment: Alignment.center,
      child: Text(
        '₹',
        style: TextStyle(fontFamily: kDisplay, fontWeight: FontWeight.w700, fontSize: 19, color: k.accentInk),
      ),
    );
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kharcha',
                style: TextStyle(fontFamily: kDisplay, fontWeight: FontWeight.w700, fontSize: 20, letterSpacing: -.4, color: k.ink, height: 1.1),
              ),
              Text('${monthNames[now.month - 1]} ${now.year}', style: context.text.bodySmall),
            ],
          ),
          const Spacer(),
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
      (Icons.donut_large_outlined, Icons.donut_large_rounded, 'Budgets'),
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
                    color: k.pop,
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
    return Padding(
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
                  decoration: const InputDecoration(prefixText: '₹ ', hintText: 'e.g. 65000'),
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
          const SizedBox(height: 20),
          if (repo is LocalRepository) ...[
            if (repo.hasExampleData)
              _SettingsButton(
                icon: Icons.cleaning_services_outlined,
                label: 'Start fresh',
                caption: 'Clears the example data so you can add your own.',
                onTap: () => _confirm(
                  title: 'Start fresh?',
                  body: 'This removes all example expenses. Starter budgets stay, and you can change them.',
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
          Text('Kharcha 0.1.0', textAlign: TextAlign.center, style: context.text.bodySmall),
        ],
      ),
    );
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
