import 'package:flutter/material.dart';

import '../api.dart';
import '../i18n.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import 'chat_screen.dart';
import 'favorites_screen.dart';
import 'home_screen.dart';
import 'more_screen.dart';
import 'my_listings_screen.dart';

/// App shell. Bottom nav adapts to the user's role:
/// - broker: Home / Favorites / Chat / My listings / More
/// - user:   Home / Favorites / Chat / More   (no listing tools)
class RootNav extends StatefulWidget {
  const RootNav({super.key, this.initialHealth});
  final HealthInfo? initialHealth;

  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> {
  int _index = 0;
  bool _isBroker = ProfileService.instance.isBroker;

  @override
  void initState() {
    super.initState();
    // Confirm the role (cachedRole may be null on a cold start).
    ProfileService.instance.role().then((r) {
      if (mounted) setState(() => _isBroker = r == 'broker');
    });
  }

  void _goToChat() => setState(() => _index = _chatIndex);

  int get _chatIndex => 2; // Home, Favorites, Chat, ...

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(initialHealth: widget.initialHealth, onStartChat: _goToChat),
      const FavoritesScreen(),
      const ChatScreen(),
      if (_isBroker) const MyListingsScreen(),
      const MoreScreen(),
    ];
    final destinations = <NavigationDestination>[
      NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home, color: Brand.navy),
          label: tr('nav_home')),
      NavigationDestination(
          icon: const Icon(Icons.favorite_border),
          selectedIcon: const Icon(Icons.favorite, color: Brand.coral),
          label: tr('nav_favorites')),
      NavigationDestination(
          icon: const Icon(Icons.chat_bubble_outline),
          selectedIcon: const Icon(Icons.chat_bubble, color: Brand.navy),
          label: tr('nav_chat')),
      if (_isBroker)
        NavigationDestination(
            icon: const Icon(Icons.assignment_outlined),
            selectedIcon: const Icon(Icons.assignment, color: Brand.navy),
            label: tr('nav_listings')),
      NavigationDestination(
          icon: const Icon(Icons.grid_view_outlined),
          selectedIcon: const Icon(Icons.grid_view, color: Brand.navy),
          label: tr('nav_more')),
    ];
    if (_index >= pages.length) _index = pages.length - 1;

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: Brand.coralLight,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? Brand.navy
                  : Brand.muted,
            ),
          ),
        ),
        child: NavigationBar(
          height: 66,
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: destinations,
        ),
      ),
    );
  }
}
