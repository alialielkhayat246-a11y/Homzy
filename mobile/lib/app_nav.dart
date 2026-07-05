import 'package:flutter/material.dart';

/// App-wide navigation helper. The bottom-nav index lives here so any screen
/// (even a pushed detail route) can jump back to Home by tapping the logo.
class AppNav {
  AppNav._();

  /// Selected bottom-nav tab (0 = Home / chat). RootNav binds to this.
  static final ValueNotifier<int> tab = ValueNotifier<int>(0);

  /// Pop any pushed routes and switch to the Home tab.
  static void goHome(BuildContext context) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    tab.value = 0;
  }
}
