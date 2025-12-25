// lib/features/home/pages/map/native_geocoder.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:doraride_appp/common/config/maps_config.dart';

Future<String> reverseGeocodeNative(double lat, double lng) async {
  try {
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json'
      '?latlng=$lat,$lng'
      '&key=$kGoogleMapsApiKey'
      '&language=en',
    );

    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final status = (data['status'] as String?) ?? '';
      final err = data['error_message'] as String? ?? '';
      if (status == 'OK') {
        final results = (data['results'] as List);
        if (results.isNotEmpty) {
          return results.first['formatted_address'] as String? ?? 'Address format error';
        } else {
          return 'No address results';
        }
      } else {
        return 'Geocoding failed: $status${err.isNotEmpty ? ": $err" : ""}';
      }
    } else {
      return 'Network error (${resp.statusCode})';
    }
  } catch (e) {
    return 'Native geocoding error: $e';
  }
}