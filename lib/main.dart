import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_prefs.dart';
import 'core/brand.dart';
import 'data/local_repository.dart';
import 'data/supabase_repository.dart';
import 'services/ai_coach.dart';
import 'state/app_state.dart';
import 'ui/app_lock.dart';
import 'ui/auth/sign_in_screen.dart';
import 'ui/currency_controller.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'ui/theme_controller.dart';
import 'ui/widgets/intro.dart';

/// Pass these at build time to connect the live backend:
///   flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
/// Without them the app saves everything on the phone (starting empty).
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

/// Build with --dart-define=AI_ENABLED=false to skip the server AI and answer
/// on the device only. With it on, the app still answers on the device until
/// the server's ai-coach function has a free AI key (or a Claude key).
const aiEnabled = bool.fromEnvironment('AI_ENABLED', defaultValue: true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPrefs.init();
  final theme = await ThemeController.load();
  final currency = await CurrencyController.load();
  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    runApp(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(LocalRepository(store: PrefsStore()))],
        child: SpendwellApp(home: const AppShell(), theme: theme, currency: currency),
      ),
    );
    return;
  }
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  runApp(AuthGate(theme: theme, currency: currency));
}

class SpendwellApp extends StatelessWidget {
  const SpendwellApp({super.key, required this.home, this.theme, this.currency});
  final Widget home;

  /// Light / Dark / Auto and the money currency. Tests may leave them out.
  final ThemeController? theme;
  final CurrencyController? currency;
  static final _fallbackTheme = ThemeController();
  static final _fallbackCurrency = CurrencyController();

  static final _light = buildTheme(Brightness.light);
  static final _dark = buildTheme(Brightness.dark);

  @override
  Widget build(BuildContext context) {
    final themes = theme ?? _fallbackTheme;
    final money = currency ?? _fallbackCurrency;
    return ThemeScope(
      controller: themes,
      child: CurrencyScope(
        controller: money,
        child: ListenableBuilder(
          listenable: Listenable.merge([themes, money]),
          builder: (context, _) => MaterialApp(
            title: kAppName,
            debugShowCheckedModeBanner: false,
            theme: _light,
            darkTheme: _dark,
            themeMode: themes.value,
            themeAnimationDuration: themes.revealing ? Duration.zero : const Duration(milliseconds: 400),
            themeAnimationCurve: Curves.easeInOutCubic,
            builder: (context, child) => IntroOverlay(
              child: AppLockGate(
                child: ThemeReveal(key: themes.revealKey, child: child!),
              ),
            ),
            // A new currency rebuilds every screen so all amounts reformat.
            home: KeyedSubtree(key: ValueKey(money.value.code), child: home),
          ),
        ),
      ),
    );
  }
}

/// Shows sign-in until there is a session (or the person chose to use the app
/// without an account), then the app with a fresh state for that user.
/// The ProviderScope sits above MaterialApp so sheets and dialogs (which open
/// on the app's navigator) can read the same state.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.theme, required this.currency});
  final ThemeController theme;
  final CurrencyController currency;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _guest = AppPrefs.getBool(AppPrefs.guest);

  void _setGuest(bool v) {
    AppPrefs.setBool(AppPrefs.guest, v);
    setState(() => _guest = v);
  }

  @override
  Widget build(BuildContext context) {
    final db = Supabase.instance.client;
    if (_guest && db.auth.currentSession == null) {
      return ProviderScope(
        key: const ValueKey('guest'),
        overrides: [
          repositoryProvider.overrideWithValue(LocalRepository(store: PrefsStore())),
          exitGuestProvider.overrideWithValue(() => _setGuest(false)),
        ],
        child: SpendwellApp(home: const AppShell(), theme: widget.theme, currency: widget.currency),
      );
    }
    return StreamBuilder<AuthState>(
      stream: db.auth.onAuthStateChange,
      builder: (context, _) {
        final session = db.auth.currentSession;
        if (session == null) {
          return SpendwellApp(
            home: SignInScreen(db: db, onUseWithoutAccount: () => _setGuest(true)),
            theme: widget.theme,
            currency: widget.currency,
          );
        }
        return ProviderScope(
          key: ValueKey(session.user.id),
          overrides: [
            repositoryProvider.overrideWithValue(SupabaseRepository(db)),
            aiCoachProvider.overrideWithValue(aiEnabled ? SupabaseAiCoach(db) : OfflineAiCoach()),
          ],
          child: SpendwellApp(home: const AppShell(), theme: widget.theme, currency: widget.currency),
        );
      },
    );
  }
}
