import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../../domain/category_guess.dart';
import '../../domain/recurring.dart';
import '../../domain/text_parsers.dart';
import '../../services/receipt/receipt_scanner.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';

class AddPrefill {
  const AddPrefill({this.amountPaise, this.categoryId, this.note, this.pay});
  final int? amountPaise;
  final String? categoryId;
  final String? note;
  final PayMethod? pay;
}

class AddResult {
  const AddResult({
    required this.txnId,
    required this.categoryId,
    required this.amountPaise,
    required this.categoryName,
    required this.newCategory,
    required this.when,
    this.edited = false,
  });
  final String txnId;
  final String categoryId;
  final bool edited;
  final int amountPaise;
  final String categoryName;
  final bool newCategory;
  final String when;
}

Future<AddResult?> openAddSheet(BuildContext context, {AddPrefill? prefill}) => showModalBottomSheet<AddResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => AddExpenseSheet(prefill: prefill),
);

/// Opens the same sheet to change an existing expense.
Future<AddResult?> openEditSheet(BuildContext context, Txn txn) => showModalBottomSheet<AddResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => AddExpenseSheet(editing: txn),
);

class AddExpenseSheet extends ConsumerStatefulWidget {
  const AddExpenseSheet({super.key, this.prefill, this.editing});
  final AddPrefill? prefill;

  /// When set, the sheet edits this expense instead of adding a new one.
  final Txn? editing;

  @override
  ConsumerState<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends ConsumerState<AddExpenseSheet> {
  static const _maxDigits = 8;

  late final Txn? _editing = widget.editing;
  late final int? _startPaise = _editing?.amountPaise ?? widget.prefill?.amountPaise;
  late String _amt = _startPaise != null ? '${(_startPaise / 100).round()}' : '';
  late String? _catId = _editing?.categoryId ?? widget.prefill?.categoryId;
  late bool _catTouched = _catId != null;
  bool _autoPicked = false;
  late final _note = TextEditingController(text: _editing != null ? (_editing.note ?? _editing.merchant ?? '') : (widget.prefill?.note ?? ''));
  final _otherName = TextEditingController();
  late DateTime _date = dateOnly(_editing?.spentAt ?? ref.read(clockProvider)());
  late PayMethod _pay = _editing?.pay ?? widget.prefill?.pay ?? PayMethod.upi;
  late bool _repeat = _editing?.isRecurring ?? false;
  bool _splitOn = false;
  final _people = TextEditingController();

  /// "Filled from SMS" / "Read from receipt", shown briefly after auto-fill.
  String? _filledFrom;
  int _popTick = 0;
  int _shakeTick = 0;
  bool _saving = false;
  final _keys = FocusNode(debugLabel: 'keypad');

  List<String> get _names => _people.text.split(',').map((n) => n.trim()).where((n) => n.isNotEmpty).toList();

  void _fill({int? amountPaise, String? note, DateTime? date, PayMethod? pay, required String source}) {
    final today = dateOnly(ref.read(clockProvider)());
    setState(() {
      if (amountPaise != null) {
        _amt = '${(amountPaise / 100).round()}';
        _popTick++;
      }
      if (note != null && note.isNotEmpty) _note.text = note;
      if (date != null && !date.isAfter(today) && today.difference(date).inDays <= 365) _date = dateOnly(date);
      if (pay != null) _pay = pay;
      _filledFrom = source;
    });
    if (note != null) _onNote(note);
    HapticFeedback.mediumImpact();
  }

  Future<void> _pasteSms() async {
    String text = '';
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
    } catch (_) {}
    if (parseBankSms(text) == null && mounted) {
      // Nothing usable on the clipboard: let them paste it by hand.
      final ctl = TextEditingController(text: text);
      final typed = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Paste a bank SMS'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(hintText: 'e.g. Rs.450 debited from A/c XX1234 to VPA swiggy@icici…'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Read it')),
          ],
        ),
      );
      ctl.dispose();
      if (typed == null) return;
      text = typed;
    }
    final sms = parseBankSms(text);
    if (!mounted) return;
    if (sms == null) {
      toast(context, 'Couldn\'t find an amount in that message.');
    } else if (sms.isCredit) {
      toast(context, 'That message is money coming in, not an expense.');
    } else {
      _fill(amountPaise: sms.amountPaise, note: sms.merchant, date: sms.date, pay: sms.pay, source: 'Filled from SMS');
    }
  }

  Future<void> _scanReceipt() async {
    final camera = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, true)),
            ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, false)),
          ],
        ),
      ),
    );
    if (camera == null) return;
    try {
      final r = await ReceiptScanner.scan(camera: camera);
      if (r == null || !mounted) return;
      if (r.totalPaise == null) toast(context, 'Couldn\'t read a total. Type the amount instead.');
      _fill(amountPaise: r.totalPaise, note: r.merchant, date: r.date, source: 'Read from receipt');
    } catch (_) {
      if (mounted) toast(context, 'Couldn\'t read the receipt. Try a sharper photo.');
    }
  }

  @override
  void dispose() {
    _people.dispose();
    _note.dispose();
    _otherName.dispose();
    _keys.dispose();
    super.dispose();
  }

  AppData get _data => ref.read(appDataProvider).requireValue;

  void _press(String k) {
    setState(() {
      if (k == 'del') {
        if (_amt.isNotEmpty) _amt = _amt.substring(0, _amt.length - 1);
        return;
      }
      final next = (_amt + k).replaceFirst(RegExp(r'^0+'), '');
      if (next.isEmpty || next.length > _maxDigits) {
        _shakeTick++;
        return;
      }
      _amt = next;
      _popTick++;
    });
    HapticFeedback.selectionClick();
  }

  void _onNote(String text) {
    if (_catTouched) return;
    final g = guessCategory(text, _data);
    if (g != null && g.id != _catId) {
      setState(() {
        _catId = g.id;
        _autoPicked = true;
      });
    }
  }

  void _pick(String id) {
    setState(() {
      _catId = id;
      _catTouched = true;
      _autoPicked = false;
    });
    HapticFeedback.selectionClick();
  }

  String _catLabel(AppData d) {
    if (_catId == null) return '';
    if (_catId == d.other.id && _otherName.text.trim().isNotEmpty) return _cleanName(_otherName.text);
    return d.cat(_catId!).name;
  }

  static String _cleanName(String s) {
    final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
  }

  Future<void> _save() async {
    final rupees = int.tryParse(_amt) ?? 0;
    if (rupees <= 0) {
      setState(() => _shakeTick++);
      return;
    }
    if (_catId == null || _saving) return;
    final d = _data;
    final now = ref.read(clockProvider)();
    final isOther = _catId == d.other.id;
    final newName = isOther && _otherName.text.trim().isNotEmpty ? _cleanName(_otherName.text) : null;
    final hadCategory =
        newName != null && d.categories.any((c) => c.name.toLowerCase() == newName.toLowerCase() || c.shortName.toLowerCase() == newName.toLowerCase());
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final editing = _editing;
    if (editing != null) {
      try {
        final at = editing.spentAt;
        final saved = await ref
            .read(appDataProvider.notifier)
            .updateTxn(
              editing
                  .withNote(note)
                  .copyWith(
                    amountPaise: rupees * 100,
                    categoryId: _catId,
                    spentAt: DateTime(_date.year, _date.month, _date.day, at.hour, at.minute),
                    pay: _pay,
                    isRecurring: _repeat,
                  ),
              newCategoryName: newName,
            );
        final cat = ref.read(appDataProvider).requireValue.cat(saved.categoryId);
        navigator.pop(
          AddResult(
            txnId: saved.id,
            categoryId: saved.categoryId,
            amountPaise: saved.amountPaise,
            categoryName: cat.name,
            newCategory: newName != null && !hadCategory,
            when: dayLabel(_date, now),
            edited: true,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _saving = false);
        toast(context, e.toString());
      }
      return;
    }
    final split = _splitOn ? splitEqually(rupees * 100, _names) : (yours: rupees * 100, theirs: const <({String person, int amountPaise})>[]);
    try {
      final notifier = ref.read(appDataProvider.notifier);
      final txn = await notifier.addTxn(
        NewTxn(
          amountPaise: split.yours,
          categoryId: _catId!,
          spentAt: DateTime(_date.year, _date.month, _date.day, now.hour, now.minute),
          note: note,
          pay: _pay,
          isRecurring: _repeat,
        ),
        newCategoryName: newName,
      );
      if (split.theirs.isNotEmpty) {
        await notifier.addSplits(split.theirs, note: note ?? ref.read(appDataProvider).requireValue.cat(txn.categoryId).name);
      }
      final cat = ref.read(appDataProvider).requireValue.cat(txn.categoryId);
      navigator.pop(
        AddResult(
          txnId: txn.id,
          categoryId: txn.categoryId,
          amountPaise: txn.amountPaise,
          categoryName: cat.name,
          newCategory: newName != null && !hadCategory,
          when: dayLabel(_date, now),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      toast(context, e.toString());
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = e.character;
    if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
      _press(ch);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _press('del');
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter) {
      _save();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final d = ref.watch(appDataProvider).requireValue;
    final now = ref.read(clockProvider)();
    final today = dateOnly(now);
    final yesterday = today.subtract(const Duration(days: 1));
    final rupees = int.tryParse(_amt) ?? 0;
    final ready = rupees > 0 && _catId != null;
    final label = rupees == 0
        ? 'Enter an amount'
        : _catId == null
        ? 'Pick a category'
        : '${_editing != null ? 'Save' : 'Add'} ${Money.whole(rupees)} · ${_catLabel(d)}';

    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.viewInsetsOf(context).bottom + 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(_editing != null ? 'Edit expense' : 'Add expense', style: context.text.titleLarge)),
                        if (_editing == null) ...[
                          _QuickAction(icon: Icons.sms_outlined, label: 'Paste bank SMS', onTap: _pasteSms),
                          if (ReceiptScanner.supported) ...[
                            const SizedBox(width: 8),
                            _QuickAction(icon: Icons.document_scanner_outlined, label: 'Scan receipt', onTap: _scanReceipt),
                          ],
                        ],
                      ],
                    ),
                    _AmountDisplay(amount: _amt, popTick: _popTick, shakeTick: _shakeTick),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _filledFrom == null
                          ? const SizedBox.shrink()
                          : Center(key: ValueKey(_filledFrom), child: Pill(PillKind.good, '$_filledFrom · check the details')),
                    ),
                    TextField(
                      controller: _note,
                      onChanged: _onNote,
                      maxLength: 60,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(),
                      decoration: const InputDecoration(hintText: 'Note (optional), e.g. Lunch with team', counterText: ''),
                    ),
                    const SizedBox(height: 12),
                    _Label(
                      'Category',
                      trailing: AnimatedOpacity(
                        opacity: _autoPicked ? 1 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          'Auto-picked',
                          style: TextStyle(color: k.good, fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ),
                    ),
                    _CategoryGrid(categories: d.pickerCategories, selected: _catId, onPick: _pick),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      child: _catId == d.other.id
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: TextField(
                                controller: _otherName,
                                maxLength: 20,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(hintText: 'Name it, e.g. Gifts (optional)', counterText: ''),
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    const SizedBox(height: 12),
                    _OptionRow(
                      label: 'When',
                      child: _Segmented<DateTime>(
                        value: _date == today || _date == yesterday ? _date : null,
                        options: {today: 'Today', yesterday: 'Yesterday'},
                        onChanged: (v) => setState(() => _date = v),
                        extra: _DateChip(
                          selected: _date != today && _date != yesterday,
                          label: _date != today && _date != yesterday ? fmtDay(_date) : 'Pick date',
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _date,
                              firstDate: today.subtract(const Duration(days: 365)),
                              lastDate: today,
                            );
                            if (picked != null) setState(() => _date = dateOnly(picked));
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _OptionRow(
                      label: 'Paid by',
                      child: _Segmented<PayMethod>(
                        value: _pay,
                        options: {
                          for (final p in [PayMethod.upi, PayMethod.card, PayMethod.cash]) p: p.label,
                        },
                        onChanged: (v) => setState(() => _pay = v),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _ChipToggle(icon: Icons.event_repeat_rounded, label: 'Repeats monthly', value: _repeat, onChanged: (v) => setState(() => _repeat = v)),
                        if (_editing == null)
                          _ChipToggle(
                            icon: Icons.call_split_rounded,
                            label: 'Split this bill',
                            value: _splitOn,
                            onChanged: (v) => setState(() => _splitOn = v),
                          ),
                      ],
                    ),
                    if (_editing == null) ...[
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        child: !_splitOn
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextField(
                                      controller: _people,
                                      onChanged: (_) => setState(() {}),
                                      decoration: const InputDecoration(hintText: 'Split with, e.g. Rahul, Priya'),
                                    ),
                                    if (rupees > 0 && _names.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Builder(
                                        builder: (context) {
                                          final s = splitEqually(rupees * 100, _names);
                                          return Text(
                                            'You pay ${Money.fmt(s.yours)} · each owes you ${Money.fmt(s.theirs.first.amountPaise)}',
                                            style: context.text.bodySmall?.copyWith(color: k.accent, fontWeight: FontWeight.w600),
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _Keypad(onKey: _press),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: ready && !_saving ? _save : null,
                style: FilledButton.styleFrom(
                  backgroundColor: k.pop,
                  foregroundColor: k.popInk,
                  disabledBackgroundColor: k.pop.withValues(alpha: .4),
                  disabledForegroundColor: k.popInk.withValues(alpha: .6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontFamily: kBody, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                child: _saving
                    ? SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: k.popInk))
                    : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        ),
        ?trailing,
      ],
    ),
  );
}

class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({required this.amount, required this.popTick, required this.shakeTick});
  final String amount;
  final int popTick;
  final int shakeTick;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final text = amount.isEmpty ? '' : Money.grouped(int.parse(amount));
    final size = text.length > 8 ? 36.0 : 44.0;
    final style = TextStyle(fontFamily: kDisplay, fontSize: size, fontWeight: FontWeight.w700, letterSpacing: -.5, color: k.ink, fontFeatures: kTabular);
    final still = reduceMotion(context);
    final chars = text.split('');
    Widget row = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          Money.symbol,
          style: style.copyWith(fontSize: size * .7, color: k.muted),
        ),
        const SizedBox(width: 6),
        if (text.isEmpty) Text('0', style: style.copyWith(color: k.muted.withValues(alpha: .5))),
        for (var i = 0; i < chars.length; i++)
          i == chars.length - 1 && !still
              ? Text(
                  chars[i],
                  style: style,
                ).animate(key: ValueKey(popTick)).scaleXY(begin: .3, end: 1, duration: 320.ms, curve: Curves.elasticOut).fadeIn(duration: 120.ms)
              : Text(chars[i], style: style),
        const SizedBox(width: 3),
        Container(
          width: 2,
          height: size * .8,
          color: k.pop,
        ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 1, end: 0, duration: 500.ms, curve: Curves.easeInOut),
      ],
    );
    if (shakeTick > 0 && !still) {
      row = row.animate(key: ValueKey('shake$shakeTick')).shakeX(hz: 5, amount: 7, duration: 350.ms);
    }
    return Semantics(
      liveRegion: true,
      label: text.isEmpty ? 'Amount, empty' : 'Amount ${Money.symbol}$text',
      child: SizedBox(height: 62, child: ExcludeSemantics(child: row)),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.categories, required this.selected, required this.onPick});
  final List<Category> categories;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final still = reduceMotion(context);
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 1.3,
      children: [
        for (final (i, c) in categories.indexed)
          () {
            final sel = c.id == selected;
            Widget tile = Semantics(
              button: true,
              selected: sel,
              label: c.name,
              child: Material(
                color: sel ? k.accent : k.bg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: sel ? k.accent : k.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('cat-${c.id}'),
                  onTap: () => onPick(c.id),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedScale(
                        scale: sel ? 1.12 : 1,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.elasticOut,
                        child: CatIcon(c.isCustom ? 'tag' : c.icon, size: 28, bg: sel ? k.pop : k.surface, fg: sel ? k.popInk : k.ink2),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Text(
                          c.shortName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sel ? k.accentInk : k.ink2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            if (!still) {
              tile = tile.animate(delay: (120 + i * 30).ms).scaleXY(begin: .5, end: 1, duration: 420.ms, curve: Curves.easeOutBack).fadeIn(duration: 200.ms);
            }
            return tile;
          }(),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(label, style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
      const Spacer(),
      Flexible(
        flex: 6,
        child: Align(alignment: Alignment.centerRight, child: child),
      ),
    ],
  );
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({required this.value, required this.options, required this.onChanged, this.extra});
  final T? value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: k.surface2, borderRadius: BorderRadius.circular(99)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in options.entries) _SegButton(label: e.value, selected: e.key == value, onTap: () => onChanged(e.key)),
            ?extra,
          ],
        ),
      ),
    );
  }
}

class _SegButton extends StatelessWidget {
  const _SegButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? k.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
            boxShadow: selected ? [BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 3, offset: const Offset(0, 1))] : null,
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? k.ink : k.muted),
          ),
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.selected, required this.label, required this.onTap});
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _SegButton(label: label, selected: selected, onTap: onTap);
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey});
  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0', 'del'];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 8,
      childAspectRatio: 2.9,
      children: [for (final key in keys) _Key(key: ValueKey('key-$key'), label: key, onTap: () => onKey(key))],
    );
  }
}

class _Key extends StatefulWidget {
  const _Key({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final isDel = widget.label == 'del';
    return Semantics(
      button: true,
      label: isDel ? 'Delete last digit' : widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? .9 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(color: _down ? k.accentSoft : k.surface2, borderRadius: BorderRadius.circular(14)),
            alignment: Alignment.center,
            child: isDel
                ? Icon(Icons.backspace_outlined, size: 22, color: k.ink)
                : Text(
                    widget.label,
                    style: TextStyle(fontFamily: kDisplay, fontSize: 22, fontWeight: FontWeight.w600, color: k.ink),
                  ),
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Tooltip(
      message: label,
      child: Squish(
        child: Material(
          color: k.accentSoft,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Semantics(
              button: true,
              label: label,
              child: SizedBox.square(dimension: 38, child: Icon(icon, size: 19, color: k.accent)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small on/off chip, e.g. "Repeats monthly".
class _ChipToggle extends StatelessWidget {
  const _ChipToggle({required this.icon, required this.label, required this.value, required this.onChanged});
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Semantics(
      toggled: value,
      button: true,
      child: Squish(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: value ? k.accent : k.bg,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: value ? k.accent : k.line),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(!value);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                      child: Icon(value ? Icons.check_rounded : icon, key: ValueKey(value), size: 16, color: value ? k.accentInk : k.ink2),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: value ? k.accentInk : k.ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
