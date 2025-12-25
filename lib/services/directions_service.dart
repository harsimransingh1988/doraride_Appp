import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show
  PolylinePoints, PointLatLng; // ensure you have polyline_points dep OR use google_maps_flutter's decode

class DirectionsService {
  DirectionsService(this.apiKey);
  final String apiKey;

  Future<List<LatLng>> getSampledRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${origin.latitude},${origin.longitude}'
      '&destination=${destination.latitude},${destination.longitude}'
      '&mode=driving&alternatives=false&units=metric&key=$apiKey',
    );

    final res = await http.get(url);
    if (res.statusCode != 200) {
      throw Exception('Directions failed: ${res.body}');
    }
    final data = json.decode(res.body);
    final routes = data['routes'] as List?;
    if (routes == null || routes.isEmpty) {
      throw Exception('No routes returned');
    }
    final poly = routes.first['overview_polyline']['points'] as String;

    // Decode
    final decoded = _decodePolyline(poly);

    // Downsample to ~100 points so filters are fast
    final target = 100;
    if (decoded.length <= target) return decoded;
    final step = decoded.length / target;
    final result = <LatLng>[];
    for (double i = 0; i < decoded.length; i += step) {
      result.add(decoded[i.toInt()]);
    }
    // Always include last point
    if (result.last != decoded.last) result.add(decoded.last);
    return result;
  }

  List<LatLng> _decodePolyline(String poly) {
    // Minimal polyline decoder (or use polyline_points package)
    final List<PointLatLng> pts = PolylinePoints().decodePolyline(poly);
    return pts.map((p) => LatLng(p.latitude, p.longitude)).toList();
  }
}
