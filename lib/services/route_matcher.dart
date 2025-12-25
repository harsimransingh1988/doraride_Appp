import 'dart:math';
import 'package:latlong2/latlong.dart';

/// Haversine distance (meters)
double _haversine(LatLng a, LatLng b) {
  const Distance d = Distance();
  return d(a, b);
}

/// Distance from a point to a polyline (meters).
/// Uses segment-wise point-to-line distance in meters.
double distanceToRouteMeters(LatLng p, List<LatLng> route) {
  if (route.length < 2) return double.infinity;
  double best = double.infinity;
  for (int i = 0; i < route.length - 1; i++) {
    final a = route[i];
    final b = route[i + 1];
    best = min(best, _pointToSegmentMeters(p, a, b));
  }
  return best;
}

double _pointToSegmentMeters(LatLng p, LatLng a, LatLng b) {
  // Convert to meters via equirectangular approximation (good enough for ~500km spans)
  final meterPerDegLat = 111132.0;
  final meterPerDegLon = 111320.0 * cos((a.latitude + b.latitude) * pi / 360.0);

  final ax = (a.longitude) * meterPerDegLon;
  final ay = (a.latitude) * meterPerDegLat;
  final bx = (b.longitude) * meterPerDegLon;
  final by = (b.latitude) * meterPerDegLat;
  final px = (p.longitude) * meterPerDegLon;
  final py = (p.latitude) * meterPerDegLat;

  final abx = bx - ax;
  final aby = by - ay;
  final apx = px - ax;
  final apy = py - ay;
  final ab2 = (abx * abx + aby * aby);
  double t = ab2 == 0 ? 0 : ((apx * abx + apy * aby) / ab2).clamp(0.0, 1.0);
  final cx = ax + t * abx;
  final cy = ay + t * aby;
  final dx = px - cx;
  final dy = py - cy;
  return sqrt(dx * dx + dy * dy);
}

/// Corridor thresholds (tune if needed)
class CorridorThresholds {
  // how close rider's FROM must be to driver route
  final double originMeters;
  // how close rider's TO must be to driver route (near the later portion)
  final double destinationMeters;
  // guard to ensure rider's TO isn’t before rider’s FROM along the route
  final int forwardWindowSegments;

  const CorridorThresholds({
    this.originMeters = 40000,      // 40 km
    this.destinationMeters = 40000, // 40 km
    this.forwardWindowSegments = 15,
  });
}

/// Returns true if rider (from→to) lies along driver’s route (polyline sample).
bool corridorMatch({
  required LatLng riderFrom,
  required LatLng riderTo,
  required List<LatLng> route,
  CorridorThresholds thresholds = const CorridorThresholds(),
}) {
  if (route.length < 2) return false;

  // Find closest segment index for FROM
  int bestFromIdx = _closestIndex(riderFrom, route);
  final fromDist = distanceToRouteMeters(riderFrom, route);

  if (fromDist > thresholds.originMeters) return false;

  // Check TO near the route **after** from index (to preserve direction of travel)
  final int start = bestFromIdx;
  final int end = min(route.length, start + thresholds.forwardWindowSegments);
  final List<LatLng> forwardSlice = route.sublist(start, end);
  final toDist = distanceToRouteMeters(riderTo, forwardSlice);
  return toDist <= thresholds.destinationMeters;
}

int _closestIndex(LatLng p, List<LatLng> route) {
  double best = double.infinity;
  int bestIdx = 0;
  for (int i = 0; i < route.length; i++) {
    final d = _haversine(p, route[i]);
    if (d < best) {
      best = d;
      bestIdx = i;
    }
  }
  return bestIdx;
}
