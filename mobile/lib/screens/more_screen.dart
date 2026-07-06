import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import '../widgets/house_logo.dart';
import '../widgets/lang_toggle.dart';
import 'messages_screen.dart';
import 'profile_screen.dart';
import 'projects_screen.dart';
import 'valuation_screen.dart';

/// "More" tab — the profile hub from the design (navy header + menu).
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    ProfileService.instance.get().then((p) {
      if (mounted) setState(() => _profile = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = (_profile?['full_name'] ??
            AuthService.instance.displayName ??
            '')
        .toString();
    final phone = (_profile?['phone'] ?? '').toString();
    final avatar = _profile?['avatar_url'] as String?;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
            decoration: const BoxDecoration(
              color: Brand.navy,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration:
                      const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  child: avatar != null
                      ? Image.network(avatar,
                          fit: BoxFit.cover,
                          width: 60,
                          height: 60,
                          errorBuilder: (_, __, ___) => const HouseLogo(size: 34))
                      : const HouseLogo(size: 34),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isEmpty ? 'Homzy' : name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(phone,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _modeTile(),
          _tile(Icons.person_outline, tr('menu_profile'),
              () => _push(const ProfileScreen())),
          _tile(Icons.chat_bubble_outline, tr('menu_messages'),
              () => _push(const MessagesScreen())),
          _tile(Icons.apartment_outlined, tr('menu_projects'),
              () => _push(const ProjectsScreen())),
          _tile(Icons.calculate_outlined, tr('menu_valuation'),
              () => _push(const ValuationScreen())),
          _languageTile(),
          _tile(Icons.description_outlined, tr('menu_terms'), () {}),
          _tile(Icons.privacy_tip_outlined, tr('menu_privacy'), () {}),
          _tile(Icons.logout, tr('sign_out'),
              () => AuthService.instance.signOut(),
              danger: true),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  void _push(Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => screen));

  Widget _modeTile() {
    final isBroker = ProfileService.instance.isBroker;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
          color: Brand.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Brand.line)),
      child: SwitchListTile(
        secondary: const Icon(Icons.badge_outlined, color: Brand.navy),
        title: Text(tr('broker_mode'),
            style: const TextStyle(color: Brand.navy)),
        subtitle: Text(tr('broker_mode_sub'),
            style: const TextStyle(color: Brand.muted, fontSize: 12)),
        activeThumbColor: Brand.coral,
        value: isBroker,
        onChanged: (on) async {
          try {
            await ProfileService.instance.setMode(on ? 'broker' : 'user');
            if (!mounted) return;
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(tr(on
                    ? 'mode_switched_broker'
                    : 'mode_switched_user'))));
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('$e')));
            }
          }
        },
      ),
    );
  }

  Widget _languageTile() => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        decoration: BoxDecoration(
            color: Brand.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Brand.line)),
        child: ListTile(
          leading: const Icon(Icons.language, color: Brand.navy),
          title: Text(tr('language'),
              style: const TextStyle(color: Brand.navy)),
          trailing: const LangToggle(),
          onTap: () => Lang.instance.toggle(),
        ),
      );

  Widget _tile(IconData icon, String title, VoidCallback onTap,
      {bool danger = false}) {
    final color = danger ? Brand.red : Brand.navy;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
          color: Brand.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Brand.line)),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(color: color)),
        trailing: Icon(Icons.chevron_right, color: color.withValues(alpha: .5)),
        onTap: onTap,
      ),
    );
  }
}
