import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Talks to the Homzy FastAPI backend (backend/app.py).
///
/// The base URL is configurable at runtime (stored on device) so the same
/// build works against an emulator, a LAN PC, or a hosted server. Defaults:
///   * Android emulator reaches the host machine at 10.0.2.2
///   * override at build time with: --dart-define=HOMZY_API=http://192.168.1.5:8000
class HomzyApi {
  HomzyApi._();
  static final HomzyApi instance = HomzyApi._();

  // Defaults to the live cloud backend so a fresh install just works.
  // Override at build time with --dart-define=HOMZY_API=... or in-app (⚙).
  static const _defaultBase = String.fromEnvironment(
    'HOMZY_API',
    defaultValue: 'https://homzy-jet.vercel.app',
  );
  static const _prefsKey = 'homzy_api_base';

  String _base = _defaultBase;
  String get baseUrl => _base;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && saved.isNotEmpty) _base = saved;
  }

  Future<void> setBaseUrl(String url) async {
    _base = url.trim().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _base);
  }

  Uri _u(String path) => Uri.parse('$_base$path');

  /// Engine/brand status. Returns null if the server can't be reached.
  Future<HealthInfo?> health() async {
    try {
      final r = await http
          .get(_u('/api/health'))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      return HealthInfo.fromJson(jsonDecode(utf8.decode(r.bodyBytes)));
    } catch (_) {
      return null;
    }
  }

  /// Send one client turn; throws [ApiException] on failure.
  Future<ChatReply> chat({
    required String sessionId,
    required String message,
    List<Map<String, String>> history = const [],
  }) async {
    try {
      final r = await http
          .post(
            _u('/api/chat'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'session_id': sessionId,
              'message': message,
              'history': history,
            }),
          )
          .timeout(const Duration(seconds: 300));
      if (r.statusCode != 200) {
        throw ApiException('Server returned ${r.statusCode}');
      }
      return ChatReply.fromJson(jsonDecode(utf8.decode(r.bodyBytes)));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Connection error — is the server running?');
    }
  }

  Future<void> reset(String sessionId) async {
    try {
      await http.post(
        _u('/api/reset'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({'session_id': sessionId}),
      );
    } catch (_) {/* best effort */}
  }
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class HealthInfo {
  HealthInfo({
    required this.provider,
    required this.mode,
    required this.brand,
    required this.broker,
    required this.listings,
    required this.detail,
  });

  final String provider;
  final String mode; // "ai" | "template"
  final String brand;
  final String broker;
  final int listings;
  final String detail;

  bool get isAi => mode == 'ai';

  factory HealthInfo.fromJson(Map<String, dynamic> j) => HealthInfo(
        provider: (j['provider'] ?? '').toString(),
        mode: (j['mode'] ?? 'template').toString(),
        brand: (j['brand'] ?? 'Homzy').toString(),
        broker: (j['broker'] ?? 'Nour').toString(),
        listings: (j['listings'] ?? 0) is int
            ? j['listings'] as int
            : int.tryParse('${j['listings']}') ?? 0,
        detail: (j['detail'] ?? '').toString(),
      );
}

class ChatReply {
  ChatReply({
    required this.reply,
    required this.language,
    required this.mode,
    required this.matches,
    this.recommendation,
  });

  final String reply;
  final String language; // "ar" | "en"
  final String mode;
  final List<Listing> matches;

  /// The single unit the broker recommended this turn (with photos + brochure),
  /// or null while still gathering the client's needs.
  final Listing? recommendation;

  factory ChatReply.fromJson(Map<String, dynamic> j) => ChatReply(
        reply: (j['reply'] ?? '').toString(),
        language: (j['language'] ?? 'en').toString(),
        mode: (j['mode'] ?? 'template').toString(),
        matches: ((j['matches'] as List?) ?? [])
            .map((m) => Listing.fromJson(m as Map<String, dynamic>))
            .toList(),
        recommendation: j['recommendation'] is Map<String, dynamic>
            ? Listing.fromJson(j['recommendation'] as Map<String, dynamic>)
            : null,
      );
}

/// Trimmed listing as returned by listings.public() on the backend.
class Listing {
  Listing({
    required this.id,
    required this.compound,
    required this.compoundAr,
    required this.area,
    required this.areaAr,
    required this.purpose,
    required this.type,
    required this.bedrooms,
    required this.sizeSqm,
    required this.priceEn,
    required this.priceAr,
    this.developer,
    this.downPayment,
    this.delivery,
    this.paymentPlan,
    this.brochureUrl,
    this.images = const [],
    this.coverImage,
  });

  final String id;
  final String compound;
  final String compoundAr;
  final String area;
  final String areaAr;
  final String purpose;
  final String type;
  final int bedrooms;
  final int sizeSqm;
  final String priceEn;
  final String priceAr;
  final String? developer;
  final String? downPayment;
  final String? delivery;
  final String? paymentPlan;
  final String? brochureUrl;
  final List<String> images;
  final String? coverImage;

  String? get cover => coverImage ?? (images.isNotEmpty ? images.first : null);

  factory Listing.fromJson(Map<String, dynamic> j) => Listing(
        id: '${j['id'] ?? ''}',
        compound: '${j['compound'] ?? ''}',
        compoundAr: '${j['compound_ar'] ?? ''}',
        area: '${j['area'] ?? ''}',
        areaAr: '${j['area_ar'] ?? ''}',
        purpose: '${j['purpose'] ?? ''}',
        type: '${j['type'] ?? ''}',
        bedrooms: (j['bedrooms'] is int)
            ? j['bedrooms'] as int
            : int.tryParse('${j['bedrooms']}') ?? 0,
        sizeSqm: (j['size_sqm'] is int)
            ? j['size_sqm'] as int
            : int.tryParse('${j['size_sqm']}') ?? 0,
        priceEn: '${j['price_en'] ?? ''}',
        priceAr: '${j['price_ar'] ?? ''}',
        developer: (j['developer'])?.toString(),
        downPayment: (j['down_payment'])?.toString(),
        delivery: (j['delivery'])?.toString(),
        paymentPlan: (j['payment_plan'])?.toString(),
        brochureUrl: (j['brochure_url'])?.toString(),
        images: ((j['images'] as List?) ?? [])
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList(),
        coverImage: (j['cover_image'])?.toString(),
      );
}
