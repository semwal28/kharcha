import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/local_repository.dart';
import 'data/supabase_repository.dart';
import 'services/ai_coach.dart';
import 'state/app_state.dart';
import 'ui/auth/sign_in_screen.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

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
  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    runApp(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(LocalRepository(store: PrefsStore()))],
        child: const KharchaApp(home: AppShell()),
      ),
    );
    return;
  }
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  runApp(const AuthGate());
}

class KharchaApp extends StatelessWidget {
  const KharchaApp({super.key, required this.home});
  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Kharcha',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    themeMode: ThemeMode.system,
    home: home,
  );
}

/// Shows sign-in until there is a session, then the app with a fresh state
/// for that user. The ProviderScope sits above MaterialApp so sheets and
/// dialogs (which open on the app's navigator) can read the same state.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final db = Supabase.instance.client;
    return StreamBuilder<AuthState>(
      stream: db.auth.onAuthStateChange,
      builder: (context, _) {
        final session = db.auth.currentSession;
        if (session == null) return KharchaApp(home: SignInScreen(db: db));
        return ProviderScope(
          key: ValueKey(session.user.id),
          overrides: [
            repositoryProvider.overrideWithValue(SupabaseRepository(db)),
            aiCoachProvider.overrideWithValue(aiEnabled ? SupabaseAiCoach(db) : OfflineAiCoach()),
          ],
          child: const KharchaApp(home: AppShell()),
        );
      },
    );
  }
}
