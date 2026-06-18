import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/house_logo.dart';
import 'root_nav.dart';

/// Brief branded splash. Loads the saved API base URL, then routes to the app.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await HomzyApi.instance.load();
    // Fire a health check in the background; the home screen reads it again.
    final health = await Future.any([
      HomzyApi.instance.health(),
      Future.delayed(const Duration(milliseconds: 1200), () => null),
    ]);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => RootNav(initialHealth: health)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.navy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HouseLogo(size: 96, outline: Colors.white),
            const SizedBox(height: 20),
            Text(
              'Homzy',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              Brand.tagline,
              style: GoogleFonts.poppins(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation(Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
