import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:local_auth/local_auth.dart';

import '../core/app_prefs.dart';
import '../core/brand.dart';
import 'theme.dart';
import 'widgets/motion.dart';

/// Fingerprint / face / device PIN lock. Phones only (not the web app).
abstract final class AppLock {
  static final _auth = LocalAuthentication();

  static bool get enabled => !kIsWeb && AppPrefs.getBool(AppPrefs.appLock);

  /// Whether this device can lock the app at all.
  static Future<bool> available() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } catch (_) {
      return false;
    }
  }

  /// Turns the lock on (after a successful check) or off.
  static Future<bool> setEnabled(bool on) async {
    if (on && !await authenticate('Confirm it\'s you to turn on the app lock')) return false;
    await AppPrefs.setBool(AppPrefs.appLock, on);
    return true;
  }
}

/// Covers the app with a lock screen at launch, and again after it has been
/// in the background for more than 30 seconds.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _locked = AppLock.enabled;
  bool _busy = false;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!AppLock.enabled || _busy) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _leftAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = _leftAt == null ? Duration.zero : DateTime.now().difference(_leftAt!);
      _leftAt = null;
      if (away > const Duration(seconds: 30)) {
        setState(() => _locked = true);
        _unlock();
      }
    }
  }

  Future<void> _unlock() async {
    if (_busy) return;
    _busy = true;
    final ok = await AppLock.authenticate('Unlock $kAppName');
    _busy = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;
    final k = context.k;
    final still = reduceMotion(context);
    Widget mark = const BrandMark(size: 72);
    if (!still) {
      mark = mark.animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1, end: 1.06, duration: 1200.ms, curve: Curves.easeInOut);
    }
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: Material(
            color: k.bg,
            child: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    mark,
                    const SizedBox(height: 18),
                    Text('$kAppName is locked', style: context.text.titleLarge),
                    const SizedBox(height: 6),
                    Text('Use your fingerprint, face or phone PIN.', style: context.text.bodyMedium),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: _unlock,
                      icon: const Icon(Icons.fingerprint_rounded),
                      label: const Text('Unlock'),
                      style: FilledButton.styleFrom(
                        backgroundColor: k.accent,
                        foregroundColor: k.accentInk,
                        minimumSize: const Size(180, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
