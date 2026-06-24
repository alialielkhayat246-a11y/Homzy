import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/house_logo.dart';
import '../widgets/lang_toggle.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialHealth, required this.onStartChat});

  final HealthInfo? initialHealth;
  final VoidCallback onStartChat;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HealthInfo? _health;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _health = widget.initialHealth;
    if (_health == null) _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final h = await HomzyApi.instance.health();
    if (!mounted) return;
    setState(() {
      _health = h;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final brand = _health?.brand ?? 'Homzy';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            children: [
              _Header(brand: brand, health: _health, loading: _loading),
              const SizedBox(height: 20),
              _ContinueCard(onTap: widget.onStartChat),
              const SizedBox(height: 22),
              Text(tr('how_help'),
                  style: GoogleFonts.poppins(
                      fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              _FeatureGrid(onStartChat: widget.onStartChat),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.brand, this.health, required this.loading});
  final String brand;
  final HealthInfo? health;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const HouseLogo(size: 40),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(brand,
                style: GoogleFonts.poppins(
                    fontSize: 20, fontWeight: FontWeight.w700, height: 1.1)),
            Text(tr('home_sub'),
                style: const TextStyle(fontSize: 12, color: Brand.muted)),
          ],
        ),
        const Spacer(),
        const LangToggle(),
        const SizedBox(width: 8),
        _StatusPill(health: health, loading: loading),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({this.health, required this.loading});
  final HealthInfo? health;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final String text;
    if (loading) {
      color = const Color(0xFF9AA1AC);
      text = '…';
    } else if (health == null) {
      color = const Color(0xFF9AA1AC);
      text = 'offline';
    } else if (health!.isAi) {
      color = Brand.green;
      text = 'AI';
    } else {
      color = const Color(0xFFE8A33D);
      text = 'Preview';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Brand.navy, Color(0xFF1B2D45)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('continue_title'),
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                    tr('continue_sub'),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text(tr('start_chatting')),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const BrokerAvatar(size: 56),
          ],
        ),
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({required this.onStartChat});
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    final ar = Lang.instance.isAr;
    final items = <_Feature>[
      _Feature(tr('rent_home'), Icons.vpn_key_outlined,
          ar ? 'أنا بدوّر على إيجار' : "I'm looking to rent"),
      _Feature(tr('buy_property'), Icons.home_work_outlined,
          ar ? 'أنا بدوّر على تمليك' : "I'm looking to buy"),
      _Feature(tr('sheikh_zayed'), Icons.location_on_outlined,
          ar ? 'ورّيني وحدات في الشيخ زايد' : 'Show me options in Sheikh Zayed'),
      _Feature(tr('october'), Icons.location_city_outlined,
          ar
              ? 'ورّيني وحدات في السادس من أكتوبر'
              : 'Show me options in 6th of October'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.45,
      children: items
          .map((f) => _FeatureCard(feature: f, onTap: onStartChat))
          .toList(),
    );
  }
}

class _Feature {
  const _Feature(this.label, this.icon, this.prompt);
  final String label;
  final IconData icon;
  final String prompt;
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature, required this.onTap});
  final _Feature feature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Brand.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: Brand.blueLight,
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(feature.icon, color: Brand.blue, size: 22),
            ),
            Text(feature.label,
                style: GoogleFonts.poppins(
                    fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
