import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/brand.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';

/// Email sign-in with a 6-digit code. No passwords to remember.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.db, this.onUseWithoutAccount});
  final SupabaseClient db;

  /// Lets people try the app with data saved only on this device.
  final VoidCallback? onUseWithoutAccount;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _emailOk => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim());

  Future<void> _sendCode() async {
    if (!_emailOk) {
      setState(() => _error = 'Enter a valid email, like name@gmail.com');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.db.auth.signInWithOtp(email: _email.text.trim());
      setState(() => _codeSent = true);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server. Check your internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from the email');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.db.auth.verifyOTP(type: OtpType.email, email: _email.text.trim(), token: code);
      // AuthGate switches to the app when the session arrives.
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server. Check your internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final still = reduceMotion(context);
    Widget logo = const BrandMark(size: 64);
    if (!still) {
      logo = logo
          .animate()
          .scaleXY(begin: .3, end: 1, duration: 800.ms, curve: Curves.elasticOut)
          .rotate(begin: -.1, end: 0, duration: 800.ms, curve: Curves.elasticOut);
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  logo,
                  const SizedBox(height: 20),
                  Enter(index: 1, child: Text(kTagline, style: context.text.displayMedium?.copyWith(fontSize: 30))),
                  const SizedBox(height: 8),
                  Enter(
                    index: 2,
                    child: Text(
                      _codeSent ? 'We sent a 6-digit code to ${_email.text.trim()}.' : 'Sign in with your email. We’ll send you a 6-digit code.',
                      style: context.text.bodyLarge?.copyWith(color: k.ink2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _codeSent
                        ? TextField(
                            key: const ValueKey('code'),
                            controller: _code,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                            style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w600),
                            decoration: const InputDecoration(hintText: '000000'),
                            onSubmitted: (_) => _verify(),
                          )
                        : TextField(
                            key: const ValueKey('email'),
                            controller: _email,
                            autofocus: true,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(hintText: 'you@example.com'),
                            onSubmitted: (_) => _sendCode(),
                          ),
                  ),
                  if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: TextStyle(color: k.bad, fontSize: 13))],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _busy ? null : (_codeSent ? _verify : _sendCode),
                      style: FilledButton.styleFrom(
                        backgroundColor: k.pop,
                        foregroundColor: k.popInk,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _busy
                          ? SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: k.popInk))
                          : Text(_codeSent ? 'Sign in' : 'Send code', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  if (_codeSent)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: LinkButton(
                        'Use a different email',
                        onTap: () => setState(() {
                          _codeSent = false;
                          _code.clear();
                          _error = null;
                        }),
                      ),
                    ),
                  if (!_codeSent && widget.onUseWithoutAccount != null) ...[
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(child: Divider(color: k.line)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text('or', style: context.text.bodySmall),
                        ),
                        Expanded(child: Divider(color: k.line)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton(
                        onPressed: widget.onUseWithoutAccount,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: k.ink,
                          side: BorderSide(color: k.line),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Use without an account', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Everything stays on this device. You can sign in later.', textAlign: TextAlign.center, style: context.text.bodySmall),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
