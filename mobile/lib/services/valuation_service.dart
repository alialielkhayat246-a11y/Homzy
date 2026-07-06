import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api.dart';

class Comp {
  Comp({this.name, this.area, this.type, this.price, this.size, this.ppsqm});
  final String? name;
  final String? area;
  final String? type;
  final num? price;
  final num? size;
  final num? ppsqm;

  factory Comp.fromJson(Map<String, dynamic> j) => Comp(
        name: j['name']?.toString(),
        area: j['area']?.toString(),
        type: j['type']?.toString(),
        price: j['price'] as num?,
        size: j['size'] as num?,
        ppsqm: j['ppsqm'] as num?,
      );
}

class Estimate {
  Estimate({
    required this.ok,
    this.estimate,
    this.low,
    this.high,
    this.ppsqm,
    this.nComps,
    this.scope,
    this.source,
    this.relaxed = false,
    this.comps = const [],
    this.error,
  });

  final bool ok;
  final num? estimate;
  final num? low;
  final num? high;
  final num? ppsqm;
  final int? nComps;
  final String? scope;
  final String? source; // resale | catalog
  final bool relaxed;
  final List<Comp> comps;
  final String? error;

  factory Estimate.fromJson(Map<String, dynamic> j) => Estimate(
        ok: j['ok'] == true,
        estimate: j['estimate'] as num?,
        low: j['low'] as num?,
        high: j['high'] as num?,
        ppsqm: j['ppsqm'] as num?,
        nComps: j['n_comps'] as int?,
        scope: j['scope']?.toString(),
        source: j['source']?.toString(),
        relaxed: j['relaxed'] == true,
        comps: ((j['comps'] as List?) ?? [])
            .map((c) => Comp.fromJson(c as Map<String, dynamic>))
            .toList(),
        error: j['error']?.toString(),
      );
}

/// Calls the backend resale price estimator (/api/estimate).
class ValuationService {
  ValuationService._();
  static final ValuationService instance = ValuationService._();

  Future<Estimate> estimate({
    String? area,
    String? type,
    required num size,
    String? finishing,
  }) async {
    final r = await http
        .post(
          Uri.parse('${HomzyApi.instance.baseUrl}/api/estimate'),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({
            'area': area,
            'type': type,
            'size': size,
            'finishing': finishing,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) {
      throw Exception('Server error ${r.statusCode}');
    }
    return Estimate.fromJson(jsonDecode(utf8.decode(r.bodyBytes)));
  }
}
