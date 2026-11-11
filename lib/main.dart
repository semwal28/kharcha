import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/local_repository.dart';
import 'data/supabase_repository.dart';
import 'services/ai_coach.dart';
import 'state/app_state.dart';
import 'ui/auth/sign_in_screen.dart';
import 'core/brand.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'ui/theme_controller.dart';
import 'ui/widgets/intro.dart';

/// Pass these at build time to connect the live backend:
///   flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
/// Without them the app saves everything on the phone (starting with example data).
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

/// Build with --dart-define=AI_ENABLED=false to hide the AI features until the
/// server has a Claude API key.
const aiEnabled = bool.fromEnvironment('AI_ENABLED', defaultValue: true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final theme = await ThemeController.load();
  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    runApp(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(LocalRepository(store: PrefsStore()))],
        child: SpendwellApp(home: const AppShell(), theme: theme),
      ),
    );
    return;
  }
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  runApp(AuthGate(theme: theme));
}

class SpendwellApp extends StatelessWidget {
  const SpendwellApp({super.key, required this.home, this.theme});
  final Widget home;

  /// Light / Dark / Auto. Tests may leave it out.
  final ThemeController? theme;
  static final _fallbackTheme = ThemeController();

  static final _light = buildTheme(Brightness.light);
  static final _dark = buildTheme(Brightness.dark);

  @override
  Widget build(BuildContext context) {
    final controller = theme ?? _fallbackTheme;
    return ThemeScope(
      controller: controller,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => MaterialApp(
          title: kAppName,
          debugShowCheckedModeBanner: false,
          theme: _light,
          darkTheme: _dark,
          themeMode: controller.value,
          themeAnimationDuration: controller.revealing ? Duration.zero : const Duration(milliseconds: 400),
          themeAnimationCurve: Curves.easeInOutCubic,
          builder: (context, child) => IntroOverlay(
            child: ThemeReveal(key: controller.revealKey, child: child!),
          ),
          home: home,
        ),
      ),
    );
  }
}

/// Shows sign-in until there is a session, then the app with a fresh state
/// for that user. The ProviderScope sits above MaterialApp so sheets and
/// dialogs (which open on the app's navigator) can read the same state.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.theme});
  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    final db = Supabase.instance.client;
    return StreamBuilder<AuthState>(
      stream: db.auth.onAuthStateChange,
      builder: (context, _) {
        final session = db.auth.currentSession;
        if (session == null) {
          return SpendwellApp(
            home: SignInScreen(db: db),
            theme: theme,
          );
        }
        return ProviderScope(
          key: ValueKey(session.user.id),
          overrides: [
            repositoryProvider.overrideWithValue(SupabaseRepository(db)),
            aiCoachProvider.overrideWithValue(aiEnabled ? SupabaseAiCoach(db) : OfflineAiCoach()),
          ],
          child: SpendwellApp(home: const AppShell(), theme: theme),
        );
      },
    );
  }
}
