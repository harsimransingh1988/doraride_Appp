import 'package:latlong2/latlong.dart';
import 'package:geohash/geohash.dart';
import 'route_matcher.dart';
import 'trip_service.dart';

class SearchService {
  final TripService trips;
  SearchService(this.trips);

  Future<List<Map<String, dynamic>>> search({
    required String fromName,
    required LatLng from,
    required String toName,
    required LatLng to,
    required DateTime dateLocal,
  }) async {
    final fromHash = Geohash.encode(from.latitude, from.longitude, codeLength: 5);
    final toHash   = Geohash.encode(to.latitude,   to.longitude,   codeLength: 5);

    final candidates = await trips.fetchCandidates(
      dateLocal: dateLocal,
      fromGeohash5: fromHash,
      toGeohash5: toHash,
    );

    final results = <Map<String, dynamic>>[];

    for (final doc in candidates) {
      final data = doc.data();
      final routePts = (data['route']?['sampled'] as List<dynamic>? ?? [])
          .map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
          .toList();

      final ok = corridorMatch(
        riderFrom: from,
        riderTo: to,
        route: routePts,
        thresholds: const CorridorThresholds(
          originMeters: 40000,        // 40km tolerance near origin
          destinationMeters: 40000,   // 40km tolerance near later part of route
          forwardWindowSegments: 40,  // allow long routes
        ),
      );

      if (ok) {
        results.add({...data, 'id': doc.id});
      }
    }
    // Sort by earliest departure / nearest to rider origin along the route if you like
    return results;
  }
}
