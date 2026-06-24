import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../i18n.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/house_logo.dart';
import '../widgets/lang_toggle.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    final name = auth.displayName ?? 'Homzy user';
    final email = auth.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('profile')),
        actions: const [
          Padding(
              padding: EdgeInsets.only(right: 12, left: 12),
              child: Center(child: LangToggle())),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 8),
          const Center(child: BrokerAvatar(size: 72)),
          const SizedBox(height: 14),
          Center(
            child: Text(name,
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          Center(
            child: Text(email,
                style: const TextStyle(color: Brand.muted, fontSize: 13)),
          ),
          const SizedBox(height: 28),
          _tile(Icons.bookmark_border, tr('saved_chats'),
              tr('saved_chats_sub')),
          _tile(Icons.cloud_done_outlined, tr('cloud_sync'),
              tr('cloud_sync_sub')),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => auth.signOut(),
            icon: const Icon(Icons.logout, color: Brand.red),
            label: Text(tr('sign_out'),
                style: const TextStyle(color: Brand.red)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: Brand.line),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(IconData icon, String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: Brand.blueLight,
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: Brand.blue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style:
                        const TextStyle(color: Brand.muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
