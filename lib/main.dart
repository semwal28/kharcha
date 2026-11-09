import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/demo_repository.dart';
import 'data/supabase_repository.dart';
import 'services/ai_coach.dart';
import 'state/app_state.dart';
import 'ui/auth/sign_in_screen.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

/// Pass these at build time to connect the live backend:
///   flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
/// Without them the app runs in demo mode with example data.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    runApp(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(DemoRepository())],
        child: const KharchaApp(home: AppShell()),
      ),
    );
    return;
  }
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  runApp(const KharchaApp(home: AuthGate()));
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
/// for that user.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final db = Supabase.instance.client;
    return StreamBuilder<AuthState>(
      stream: db.auth.onAuthStateChange,
      builder: (context, _) {
        final session = db.auth.currentSession;
        if (session == null) return SignInScreen(db: db);
        return ProviderScope(
          key: ValueKey(session.user.id),
          overrides: [repositoryProvider.overrideWithValue(SupabaseRepository(db)), aiCoachProvider.overrideWithValue(SupabaseAiCoach(db))],
          child: const AppShell(),
        );
      },
    );
  }
}
