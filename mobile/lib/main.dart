import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api.dart';
import 'supabase_config.dart';
import 'theme.dart';
import 'screens/auth_screen.dart';
import 'screens/root_nav.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  await HomzyApi.instance.load();
  runApp(const HomzyApp());
}

class HomzyApp extends StatelessWidget {
  const HomzyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Homzy',
      debugShowCheckedModeBanner: false,
      theme: buildHomzyTheme(),
      home: const AuthGate(),
    );
  }
}

/// Shows the splash briefly, then routes to the app (if logged in) or the
/// auth screen — and reacts to login/logout in real time.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // Brief splash so the brand shows and any session restores.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SplashScreen();
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) return const RootNav();
        return const AuthScreen();
      },
    );
  }
}
