// lib/services/geo_resolver.dart
// Worldwide dynamic resolver using the Google Maps JavaScript SDK (Flutter Web).

import 'dart:async';
import 'dart:collection';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:math' as math;
import 'package:js/js.dart';

class LatLngSimple {
  final double lat;
  final double lng;
  final String? countryCode; // ISO-2 if available
  const LatLngSimple(this.lat, this.lng, {this.countryCode});

  @override
  String toString() => '($lat,$lng)${countryCode == null ? '' : ' [$countryCode]'}';
}

class GeoResolver {
  GeoResolver._();
  static final GeoResolver instance = GeoResolver._();

  // address/text -> geocode result cache
  final Map<String, LatLngSimple> _cache =
      LinkedHashMap<String, LatLngSimple>();

  Future<bool> _waitMapsLoaded({
    Duration timeout = const Duration(seconds: 15),
    bool acceptLegacy = true,
  }) async {
    final sw = Stopwatch()..start();
    while (sw.elapsed < timeout) {
      try {
        final google = js_util.getProperty(html.window, 'google');
        if (google != null) {
          final maps = js_util.getProperty(google, 'maps');
          if (maps != null) {
            // new API (importLibrary) or legacy Geocoder
            final importLibrary = js_util.getProperty(maps, 'importLibrary');
            if (importLibrary != null) return true;
            if (acceptLegacy &&
                js_util.getProperty(maps, 'Geocoder') != null) return true;
          }
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return false;
  }

  /// Geocode any free-text place. Returns null on failure.
  Future<LatLngSimple?> geocodeText(String text) async {
    final key = text.trim().toLowerCase();
    if (key.isEmpty) return null;

    final cached = _cache[key];
    if (cached != null) return cached;

    final ok = await _waitMapsLoaded();
    if (!ok) return null;

    // Try new geocoding library first
    try {
      final google = js_util.getProperty(html.window, 'google');
      final maps = js_util.getProperty(google, 'maps');
      final importPromise =
          js_util.callMethod(maps, 'importLibrary', ['geocoding']);
      final geocodingLib = await js_util.promiseToFuture(importPromise);

      final geocoderCtor = js_util.getProperty(geocodingLib, 'Geocoder');
      if (geocoderCtor != null) {
        final geocoder = js_util.callConstructor(geocoderCtor, const []);
        final req = js_util.jsify({'address': text});
        final resp = await js_util
            .promiseToFuture(js_util.callMethod(geocoder, 'geocode', [req]));
        final results = js_util.getProperty(resp, 'results');
        final len = (js_util.getProperty(results, 'length') as int?) ?? 0;
        if (len > 0) {
          final r0 = js_util.getProperty(results, 0);
          final geometry = js_util.getProperty(r0, 'geometry');
          final loc = js_util.getProperty(geometry, 'location');

          // supports LatLng or LatLngLiteral
          final lat = (js_util.getProperty(loc, 'lat') is num)
              ? (js_util.getProperty(loc, 'lat') as num).toDouble()
              : (await js_util
                      .promiseToFuture(js_util.callMethod(loc, 'lat', const []))
                  as num)
                  .toDouble();
          final lng = (js_util.getProperty(loc, 'lng') is num)
              ? (js_util.getProperty(loc, 'lng') as num).toDouble()
              : (await js_util
                      .promiseToFuture(js_util.callMethod(loc, 'lng', const []))
                  as num)
                  .toDouble();

          String? cc;
          final comps = js_util.getProperty(r0, 'address_components');
          final clen = (js_util.getProperty(comps, 'length') as int?) ?? 0;
          for (int i = 0; i < clen; i++) {
            final comp = js_util.getProperty(comps, i);
            final types = js_util.getProperty(comp, 'types');
            final tlen = (js_util.getProperty(types, 'length') as int?) ?? 0;
            for (int j = 0; j < tlen; j++) {
              if ((js_util.getProperty(types, j) as String?) == 'country') {
                cc = (js_util.getProperty(comp, 'short_name') as String?)
                    ?.toUpperCase();
                break;
              }
            }
            if (cc != null) break;
          }

          final out = LatLngSimple(lat, lng, countryCode: cc);
          _cache[key] = out;
          return out;
        }
      }
    } catch (_) {
      // fall through to legacy
    }

    // Legacy Geocoder
    try {
      final google = js_util.getProperty(html.window, 'google');
      final maps = js_util.getProperty(google, 'maps');
      final geocoderCtor = js_util.getProperty(maps, 'Geocoder');
      if (geocoderCtor == null) return null;

      final geocoder = js_util.callConstructor(geocoderCtor, const []);
      final req = js_util.jsify({'address': text});

      final completer = Completer<LatLngSimple?>();
      final cb = allowInterop((results, status) {
        if (status == 'OK' && results != null) {
          final len = (js_util.getProperty(results, 'length') as int?) ?? 0;
          if (len == 0) return completer.complete(null);
          final r0 = js_util.getProperty(results, 0);
          final geometry = js_util.getProperty(r0, 'geometry');
          final loc = js_util.getProperty(geometry, 'location');
          final lat = (js_util.callMethod(loc, 'lat', const []) as num).toDouble();
          final lng = (js_util.callMethod(loc, 'lng', const []) as num).toDouble();

          String? cc;
          final comps = js_util.getProperty(r0, 'address_components');
          final clen = (js_util.getProperty(comps, 'length') as int?) ?? 0;
          for (int i = 0; i < clen; i++) {
            final comp = js_util.getProperty(comps, i);
            final types = js_util.getProperty(comp, 'types');
            final tlen = (js_util.getProperty(types, 'length') as int?) ?? 0;
            for (int j = 0; j < tlen; j++) {
              if ((js_util.getProperty(types, j) as String?) == 'country') {
                cc = (js_util.getProperty(comp, 'short_name') as String?)
                    ?.toUpperCase();
                break;
              }
            }
            if (cc != null) break;
          }

          completer.complete(LatLngSimple(lat, lng, countryCode: cc));
        } else {
          completer.complete(null);
        }
      });

      js_util.callMethod(geocoder, 'geocode', [req, cb]);
      final out = await completer.future
          .timeout(const Duration(seconds: 8), onTimeout: () => null);
      if (out != null) _cache[key] = out;
      return out;
    } catch (_) {
      return null;
    }
  }

  // Haversine distance (km)
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

  Future<bool> nearMatch(String aText, String bText,
      {double kmSameCountry = 60, double kmDifferentCountry = 30}) async {
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
