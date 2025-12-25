// lib/services/geo_resolver_mobile.dart
// Full mobile GeoResolver using Google Geocoding HTTP API (no dart:html/js).
//
// This mirrors the behavior of the web version:
//  - geocodeText() -> LatLngSimple (lat, lng, countryCode)
//  - nearMatch()   -> distance-based check with kmSameCountry / kmDifferentCountry
//  - corridorMatch() -> origin/destination vs from/to using distances
//
// IMPORTANT: you must put your Google Geocoding API key below.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

class LatLngSimple {
  final double lat;
  final double lng;
  final String? countryCode; // ISO-2 if available
  const LatLngSimple(this.lat, this.lng, {this.countryCode});

  @override
  String toString() =>
      '($lat,$lng)${countryCode == null ? '' : ' [$countryCode]'}';
}

class GeoResolver {
  GeoResolver._();
  static final GeoResolver instance = GeoResolver._();

  // address/text -> geocode result cache
  final Map<String, LatLngSimple> _cache =
      LinkedHashMap<String, LatLngSimple>();

  // TODO: put your real Google Geocoding API key here.
  // It should be the same project you use for Maps,
  // with "Geocoding API" enabled and key restricted.
  static const String _kGeocodingApiKey = 'AIzaSyCDw81VLlIITSG1IOK8G2cTIi5lPY-TeW8';

  Future<LatLngSimple?> geocodeText(String text) async {
    final key = text.trim().toLowerCase();
    if (key.isEmpty) return null;

    final cached = _cache[key];
    if (cached != null) return cached;

    final out = await _callGeocodeApi(text);
    if (out != null) {
      _cache[key] = out;
    }
    return out;
  }

  Future<LatLngSimple?> _callGeocodeApi(String text) async {
    if (_kGeocodingApiKey.isEmpty) {
      // You didn't set the key; fail gracefully.
      return null;
    }

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/geocode/json',
      {
        'address': text,
        'key': _kGeocodingApiKey,
      },
    );

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;

      final data = json.decode(resp.body) as Map<String, dynamic>;
      final status = data['status'] as String? ?? '';
      if (status != 'OK') return null;

      final results = data['results'] as List<dynamic>? ?? const [];
      if (results.isEmpty) return null;

      final r0 = results.first as Map<String, dynamic>;
      final geometry = r0['geometry'] as Map<String, dynamic>? ?? const {};
      final loc = geometry['location'] as Map<String, dynamic>? ?? const {};
      final lat = (loc['lat'] as num?)?.toDouble();
      final lng = (loc['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      String? cc;
      final comps = r0['address_components'] as List<dynamic>? ?? const [];
      for (final c in comps) {
        final comp = c as Map<String, dynamic>;
        final types = (comp['types'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList();
        if (types.contains('country')) {
          cc = (comp['short_name'] as String?)?.toUpperCase();
          break;
        }
      }

      return LatLngSimple(lat, lng, countryCode: cc);
    } catch (_) {
      return null;
    }
  }

  // Haversine distance (km) – same logic as your web version
  double distanceKm(LatLngSimple a, LatLngSimple b) {
    const R = 6371.0;
    final dLat = _deg2rad(b.lat - a.lat);
    final dLng = _deg2rad(b.lng - a.lng);
    final aa = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(a.lat)) *
            math.cos(_deg2rad(b.lat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(aa), math.sqrt(1 - aa));
    return R * c;
  }

  double _deg2rad(double d) => d * math.pi / 180.0;

  bool isNearKm(LatLngSimple a, LatLngSimple b, {double km = 40}) {
    return distanceKm(a, b) <= km;
  }

  Future<bool> nearMatch(
    String aText,
    String bText, {
    double kmSameCountry = 60,
    double kmDifferentCountry = 30,
  }) async {
    final a = await geocodeText(aText);
    final b = await geocodeText(bText);
    if (a == null || b == null) return false;

    if (a.countryCode != null &&
        b.countryCode != null &&
        a.countryCode != b.countryCode) {
      return isNearKm(a, b, km: kmDifferentCountry);
    }
    return isNearKm(a, b, km: kmSameCountry);
  }

  Future<bool> corridorMatch({
    required String tripOrigin,
    required String tripDestination,
    required String searchFrom,
    required String searchTo,
    double kmSameCountry = 60,
    double kmDifferentCountry = 30,
  }) async {
    final o = await geocodeText(tripOrigin);
    final d = await geocodeText(tripDestination);
    final sf = await geocodeText(searchFrom);
    final st = await geocodeText(searchTo);
    if (o == null || d == null || sf == null || st == null) return false;

    bool nearA, nearB;

    if (o.countryCode != null &&
        sf.countryCode != null &&
        o.countryCode != sf.countryCode) {
      nearA = isNearKm(o, sf, km: kmDifferentCountry);
    } else {
      nearA = isNearKm(o, sf, km: kmSameCountry);
    }

    if (d.countryCode != null &&
        st.countryCode != null &&
        d.countryCode != st.countryCode) {
      nearB = isNearKm(d, st, km: kmDifferentCountry);
    } else {
      nearB = isNearKm(d, st, km: kmSameCountry);
    }

    return nearA && nearB;
  }
}
