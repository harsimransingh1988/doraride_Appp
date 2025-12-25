// lib/services/get_place_details_cached.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// ⚠️ If you want mobile devices to talk to Google Places HTTP,
/// put a real restricted API key here (NOT needed for web).
const String _kGooglePlacesApiKey = 'YOUR_API_KEY';

const String _kCollection = 'locations_cache';

class PlaceDetails {
  final double lat;
  final double lng;
  final String countryCode;
  final String currencyCode;
  final String currencySymbol;

  PlaceDetails({
    required this.lat,
    required this.lng,
    required this.countryCode,
    required this.currencyCode,
    required this.currencySymbol,
  });

  Map<String, dynamic> toMap() => {
        'lat': lat,
        'lng': lng,
        'countryCode': countryCode,
        'currencyCode': currencyCode,
        'currencySymbol': currencySymbol,
      };

  factory PlaceDetails.fromMap(Map<String, dynamic> map) {
    return PlaceDetails(
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      countryCode: (map['countryCode'] ?? '') as String,
      currencyCode: (map['currencyCode'] ?? '') as String,
      currencySymbol: (map['currencySymbol'] ?? '') as String,
    );
  }
}

/// Public entry.
/// - Web: tries Firestore cache only. **No HTTP call → no CORS.**
/// - Mobile/desktop: cache → Places HTTP → write cache.
Future<PlaceDetails?> getPlaceDetailsCached(String placeId) async {
  try {
    // 1) Try cache
    final cached = await _getFromCache(placeId);
    if (cached != null) {
      print('📍 LocationCache HIT for $placeId');
      return cached;
    }
    print('📍 LocationCache MISS for $placeId');

    // 2) Web → skip HTTP (would be blocked by CORS)
    if (kIsWeb) {
      print(
          '🌐 Web build: skipping Google Places HTTP (CORS). Using fallbacks only.');
      return null;
    }

    // 3) Mobile/desktop → go to Places HTTP if key is configured
    if (_kGooglePlacesApiKey == 'YOUR_API_KEY') {
      print(
          '⚠️ _kGooglePlacesApiKey is still "YOUR_API_KEY". Add a real key for mobile HTTP lookups.');
      return null;
    }

    final fresh = await _fetchFromGoogleAndCache(placeId);
    return fresh;
  } catch (e) {
    print('getPlaceDetailsCached error: $e');
    return null;
  }
}

// -------------------------------------------------------------
// Cache helpers
// -------------------------------------------------------------

Future<PlaceDetails?> _getFromCache(String placeId) async {
  final doc = await FirebaseFirestore.instance
      .collection(_kCollection)
      .doc(placeId)
      .get();

  if (!doc.exists) return null;
  final data = doc.data();
  if (data == null) return null;

  try {
    return PlaceDetails.fromMap(data);
  } catch (e) {
    print('LocationCache decode error for $placeId: $e');
    return null;
  }
}

Future<PlaceDetails?> _fetchFromGoogleAndCache(String placeId) async {
  final uri = Uri.https(
    'maps.googleapis.com',
    '/maps/api/place/details/json',
    {
      'place_id': placeId,
      'fields': 'geometry,address_component',
      'key': _kGooglePlacesApiKey,
    },
  );

  print('🌍 Fetching Place details from Google HTTP for $placeId');
  final resp = await http.get(uri);

  if (resp.statusCode != 200) {
    print('Google Places HTTP failed: ${resp.statusCode} ${resp.body}');
    return null;
  }

  final body = jsonDecode(resp.body) as Map<String, dynamic>;
  if ((body['status'] ?? '') != 'OK') {
    print('Google Places returned non-OK status: ${body['status']}');
    return null;
  }

  final result = body['result'] as Map<String, dynamic>;
  final geometry = result['geometry'] as Map<String, dynamic>;
  final loc = geometry['location'] as Map<String, dynamic>;

  final lat = (loc['lat'] as num).toDouble();
  final lng = (loc['lng'] as num).toDouble();

  String countryCode = '';
  final components =
      (result['address_components'] as List<dynamic>? ?? const []);
  for (final c in components) {
    final comp = c as Map<String, dynamic>;
    final types =
        (comp['types'] as List<dynamic>? ?? const []).cast<String>();
    if (types.contains('country')) {
      countryCode = (comp['short_name'] ?? '') as String;
      break;
    }
  }

  final currency = _currencyForCountry(countryCode);

  final details = PlaceDetails(
    lat: lat,
    lng: lng,
    countryCode: countryCode,
    currencyCode: currency.code,
    currencySymbol: currency.symbol,
  );

  // Save to Firestore for future web/mobile reads.
  await FirebaseFirestore.instance
      .collection(_kCollection)
      .doc(placeId)
      .set({
    'lat': details.lat,
    'lng': details.lng,
    'countryCode': details.countryCode,
    'currencyCode': details.currencyCode,
    'currencySymbol': details.currencySymbol,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  print('📍 Cached Place details for $placeId in $_kCollection');

  return details;
}

// -------------------------------------------------------------
// Very small currency mapping (extend if you like)
// -------------------------------------------------------------

class _CurrencyInfo {
  final String code;
  final String symbol;
  const _CurrencyInfo(this.code, this.symbol);
}

_CurrencyInfo _currencyForCountry(String countryCode) {
  switch (countryCode.toUpperCase()) {
    case 'CA':
      return const _CurrencyInfo('CAD', 'C\$');
    case 'US':
      return const _CurrencyInfo('USD', '\$');
    case 'IN':
      return const _CurrencyInfo('INR', '₹');
    default:
      // fallback – you can tweak this
      return const _CurrencyInfo('USD', '\$');
  }
}
