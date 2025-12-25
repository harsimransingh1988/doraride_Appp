// lib/common/web/js_geocoder_mobile.dart
// Mobile reverse geocoder using Google Geocoding HTTP API.
// Same feature as the web version: given (lat, lng) -> human-readable address string.
//
// IMPORTANT: set your Google API key below (Geocoding API enabled).

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Reverse geocode using Google Geocoding REST API.
/// Mirrors the behavior of the web version: returns a formatted address string,
/// or a descriptive error string on failure.
Future<String> reverseGeocodeWithJs(double lat, double lng) async {
  print('📍 [MOBILE] Starting reverse geocode for: $lat, $lng');

  // TODO: put your actual API key here.
  const String apiKey = 'YOUR_GEOCODING_API_KEY_HERE';

  if (apiKey.isEmpty) {
    print('❌ [MOBILE] Geocoding API key not set');
    return 'Geocoding API key not set';
  }

  final uri = Uri.https(
    'maps.googleapis.com',
    '/maps/api/geocode/json',
    <String, String>{
      'latlng': '$lat,$lng',
      'key': apiKey,
    },
  );

  try {
    print('🔄 [MOBILE] Calling Geocoding REST API: $uri');
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) {
      print('❌ [MOBILE] HTTP error: ${resp.statusCode}');
      return 'Geocoding HTTP error: ${resp.statusCode}';
    }

    final data = json.decode(resp.body) as Map<String, dynamic>;
    final status = data['status'] as String? ?? '';

    print('📡 [MOBILE] Geocode response status: $status');

    if (status != 'OK') {
      return 'Geocoding failed: $status';
    }

    final results = data['results'] as List<dynamic>? ?? const [];
    print('📊 [MOBILE] Results count: ${results.length}');

    if (results.isEmpty) {
      return 'No results found';
    }

    final first = results.first as Map<String, dynamic>;
    final addr = first['formatted_address'] as String?;

    print('✅ [MOBILE] Address found: ${addr ?? "NULL"}');
    return addr ?? 'Address format error';
  } on TimeoutException {
    print('⏰ [MOBILE] Geocoding timeout');
    return 'Geocoding timeout';
  } catch (e) {
    print('❌ [MOBILE] Geocoding error: $e');
    return 'Geocoding error: $e';
  }
}
