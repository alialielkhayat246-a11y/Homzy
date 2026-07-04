import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api.dart';
import 'i18n.dart';
import 'supabase_config.dart';
import 'theme.dart';
import 'screens/auth_screen.dart';
import 'screens/onboarding_role_screen.dart';
import 'screens/root_nav.dart';
import 'screens/splash_screen.dart';
import 'services/profile_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  await Lang.instance.load();
  await HomzyApi.instance.load();
  runApp(const HomzyApp());
}

class HomzyApp extends StatelessWidget {
  const HomzyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Lang.instance,
      builder: (context, _) => MaterialApp(
        // Key changes with the language so the whole tree (incl. const
        // widgets) rebuilds and re-reads translated strings.
        key: ValueKey('lang-${Lang.instance.code}'),
        title: 'Homzy',
        debugShowCheckedModeBanner: false,
        theme: buildHomzyTheme(),
        builder: (context, child) => Directionality(
          textDirection:
              Lang.instance.isAr ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
        home: const AuthGate(),
      ),
    );
  }
}

/// Splash → auth → (first run) role onboarding → app.
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
        if (session == null) return const AuthScreen();
        return const _OnboardingGate();
      },
    );
  }
}

/// After login, send first-time users to role onboarding; everyone else
/// straight into the app.
class _OnboardingGate extends StatefulWidget {
  const _OnboardingGate();

  @override
  State<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<_OnboardingGate> {
  late Future<bool> _needs;

  @override
  void initState() {
    super.initState();
    _needs = ProfileService.instance.needsOnboarding();
  }

  void _reload() {
    setState(() {
      _needs = ProfileService.instance.needsOnboarding();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _needs,
      builder: (context, snap) {
        if (!snap.hasData) return const SplashScreen();
        if (snap.data == true) {
          return OnboardingRoleScreen(onDone: _reload);
        }
        return const RootNav();
      },
    );
  }
}
