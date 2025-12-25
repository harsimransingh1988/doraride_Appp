// lib/services/places_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';

class PlaceSuggestion {
  final String description;
  final String placeId;

  const PlaceSuggestion({
    required this.description,
    required this.placeId,
  });
}

class PlacesService {
  /// ✅ Places/Geocoding Web Service key (HTTP key)
  /// IMPORTANT:
  /// - Must have Places API enabled
  /// - Must have billing enabled
  /// - Must NOT be "HTTP referrer only" if you call from mobile
  /// - Best for testing: Application restriction = None
  static const String defaultApiKey = 'AIzaSyCDw81VLlIITSG1IOK8G2cTIi5lPY-TeW8';

  final String apiKey;

  const PlacesService({String? apiKey}) : apiKey = apiKey ?? defaultApiKey;

  Future<List<PlaceSuggestion>> autocomplete(
    String input, {
    String language = 'en',
    String? countryCode, // e.g. "IN"
    LatLng? location, // bias results near user
    int? radiusMeters,
  }) async {
    final q = input.trim();
    if (q.length < 2) return const [];

    final params = <String, String>{
      'input': q,
      'key': apiKey,
      'types': 'geocode',
      'language': language,
    };

    if (countryCode != null && countryCode.isNotEmpty) {
      params['components'] = 'country:$countryCode';
    }

    if (location != null) {
      params['location'] = '${location.latitude},${location.longitude}';
      params['radius'] = (radiusMeters ?? 50000).toString();
    }

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      params,
    );

    try {
      final res = await http.get(uri);

      debugPrint('Places HTTP ${res.statusCode}: $uri');

      if (res.statusCode != 200) {
        debugPrint('Places non-200 body: ${res.body}');
        return const [];
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final status = (data['status'] ?? '').toString();
      final errorMessage = (data['error_message'] ?? '').toString();

      if (status != 'OK' && status != 'ZERO_RESULTS') {
        debugPrint('Places status=$status error=$errorMessage');
        return const [];
      }

      final preds = (data['predictions'] as List?) ?? const [];
      return preds
          .map((p) {
            final m = p as Map<String, dynamic>;
            return PlaceSuggestion(
              description: (m['description'] ?? '') as String,
              placeId: (m['place_id'] ?? '') as String,
            );
          })
          .where((s) => s.placeId.isNotEmpty && s.description.isNotEmpty)
          .toList();
    } catch (e, st) {
      debugPrint('Places exception: $e');
      debugPrint('$st');
      return const [];
    }
  }
}
