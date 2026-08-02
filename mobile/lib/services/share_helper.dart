import 'package:url_launcher/url_launcher.dart';

import '../i18n.dart';
import 'profile_service.dart';

/// Share a property on WhatsApp, branded with the current broker's name/phone,
/// so every forward markets the broker (not a competitor).
Future<void> shareOnWhatsApp({
  required String title,
  String? price,
  String? area,
  String? extra,
  String? brochureUrl,
}) async {
  final p = ProfileService.instance;
  if (p.cachedName == null && p.cachedPhone == null) {
    await p.get();
  }
  final ar = Lang.instance.isAr;
  final contact = [p.cachedName, p.cachedPhone]
      .where((e) => e != null && e.isNotEmpty)
      .join(' · ');
  final lines = <String>[
    '🏠 $title',
    if (area != null && area.isNotEmpty) '📍 $area',
    if (price != null && price.isNotEmpty) '💰 $price',
    if (extra != null && extra.isNotEmpty) extra,
    if (brochureUrl != null && brochureUrl.isNotEmpty) '📄 $brochureUrl',
    if (contact.isNotEmpty) '',
    if (contact.isNotEmpty) '${ar ? 'للتواصل' : 'Contact'}: $contact',
  ];
  final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(lines.join('\n'))}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
