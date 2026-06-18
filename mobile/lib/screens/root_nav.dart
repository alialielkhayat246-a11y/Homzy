import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'placeholder_screen.dart';

/// App shell with the bottom navigation from the identity sheet:
/// Home / Projects / Chat / Saved / Profile.
class RootNav extends StatefulWidget {
  const RootNav({super.key, this.initialHealth});
  final HealthInfo? initialHealth;

  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> {
  int _index = 0;

  void _goToChat() => setState(() => _index = 2);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(initialHealth: widget.initialHealth, onStartChat: _goToChat),
      const PlaceholderScreen(
        title: 'Projects',
        icon: Icons.apartment_outlined,
        message: 'Browse compounds and projects — coming soon.',
      ),
      const ChatScreen(),
      const PlaceholderScreen(
        title: 'Saved',
        icon: Icons.bookmark_border,
        message: 'Your saved properties will appear here.',
      ),
      const PlaceholderScreen(
        title: 'Profile',
        icon: Icons.person_outline,
        message: 'Sign in and manage your preferences — coming soon.',
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: Brand.blueLight,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? Brand.blue
                  : Brand.muted,
            ),
          ),
        ),
        child: NavigationBar(
          height: 64,
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home, color: Brand.blue),
                label: 'Home'),
            NavigationDestination(
                icon: Icon(Icons.apartment_outlined),
                selectedIcon: Icon(Icons.apartment, color: Brand.blue),
                label: 'Projects'),
            NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble, color: Brand.blue),
                label: 'Chat'),
            NavigationDestination(
                icon: Icon(Icons.bookmark_border),
                selectedIcon: Icon(Icons.bookmark, color: Brand.blue),
                label: 'Saved'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person, color: Brand.blue),
                label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
