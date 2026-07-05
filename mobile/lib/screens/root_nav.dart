import 'package:flutter/material.dart';

import '../api.dart';
import '../i18n.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import 'chat_screen.dart';
import 'favorites_screen.dart';
import 'more_screen.dart';
import 'my_listings_screen.dart';
import 'projects_browse_screen.dart';

/// App shell. The home tab is the Homzy AI chat; "Projects" holds the search.
/// Broker mode adds the "My listings" tab.
///   user:   Home(chat) / Projects / Favorites / More
///   broker: Home(chat) / Projects / Favorites / My listings / More
class RootNav extends StatefulWidget {
  const RootNav({super.key, this.initialHealth});
  final HealthInfo? initialHealth;

  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    ProfileService.instance.role(); // warm the cached role / notifier
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: ProfileService.instance.roleNotifier,
      builder: (context, role, _) {
        final isBroker = role == 'broker';
        final pages = <Widget>[
          const ChatScreen(),
          const ProjectsBrowseScreen(),
          const FavoritesScreen(),
          if (isBroker) const MyListingsScreen(),
          const MoreScreen(),
        ];
        final destinations = <NavigationDestination>[
          NavigationDestination(
              icon: const Icon(Icons.forum_outlined),
              selectedIcon: const Icon(Icons.forum, color: Brand.navy),
              label: tr('nav_home')),
          NavigationDestination(
              icon: const Icon(Icons.apartment_outlined),
              selectedIcon: const Icon(Icons.apartment, color: Brand.navy),
              label: tr('nav_projects')),
          NavigationDestination(
              icon: const Icon(Icons.favorite_border),
              selectedIcon: const Icon(Icons.favorite, color: Brand.coral),
              label: tr('nav_favorites')),
          if (isBroker)
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
      },
    );
  }
}
