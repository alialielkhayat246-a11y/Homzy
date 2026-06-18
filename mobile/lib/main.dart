import 'package:flutter/material.dart';

import 'theme.dart';
import 'screens/splash_screen.dart';

void main() {
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
      home: const SplashScreen(),
    );
  }
}
