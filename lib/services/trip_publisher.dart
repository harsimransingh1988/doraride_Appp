// lib/services/trip_publisher.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:doraride_appp/services/geo_resolver.dart';

class TripPublisher {
  TripPublisher._();
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// Simple stop model you can pass in from the Post UI
  /// [label] is what user typed/selected (e.g., "Square One, Mississauga")
  /// Optional lat/lng if you already have it from the map; otherwise we resolve.
  class StopInput {
    final String label;
    final double? lat;
    final double? lng;
    StopInput(this.label, {this.lat, this.lng});
  }

  /// Publishes an outbound trip, and (optionally) a return trip in one call.
  /// Returns the created outbound tripId and (if created) return tripId.
  static Future<({String outId, String? retId})> publishTripWithReturn({
    required String originLabel,
    required String destinationLabel,
    required DateTime outDateTime,
    required int seatsTotal,
    required double pricePerSeat,
    List<StopInput> stops = const [],

    // Optional trip-level flags
    bool allowsPets = false,
    String luggageSize = 'M',
    String carModel = '',
    String carColor = '',
    bool isPremiumSeatAvailable = false,
    double premiumExtra = 0.0,
    double extraLuggagePrice = 0.0,

    // 👉 NEW: optional distance/duration & platform fee
    double? distanceKm,
    int? durationMinutes,
    double platformFeePercent = 10.0,

    // Return trip options
    bool createReturn = false,
    DateTime? returnDateTime,
  }) async {
    final uid = _auth.currentUser?.uid ?? 'anonymous';

    // --------- Normalize all places (worldwide) ----------
    final origin = await GeoResolver.instance.normalizePlace(originLabel);
    final dest = await GeoResolver.instance.normalizePlace(destinationLabel);

    final resolvedStops = <Map<String, dynamic>>[];
    for (int i = 0; i < stops.length; i++) {
      final s = stops[i];
      final res = await GeoResolver.instance.normalizePlace(
        s.label,
        hintLat: s.lat,
        hintLng: s.lng,
      );
      resolvedStops.add({
        'order': i,
        'location': res.displayName,
        'locationLower': res.token, // normalized token (city token)
        'lat': res.lat,
        'lng': res.lng,
        'countryCode': res.countryCode,
      });
    }

    // Corridor signature (so results can match when users search nearby cities)
    final corridor = GeoResolver.instance.corridorSignature(
      originToken: origin.token,
      destinationToken: dest.token,
    );

    // --------- Build common trip map ----------
    Map<String, dynamic> _tripMap({
      required String driverId,
      required String displayOrigin,
      required String displayDestination,
      required String originToken,
      required String destinationToken,
      required double oLat,
      required double oLng,
      required double dLat,
      required double dLng,
      required String oCountry,
      required String dCountry,
      required DateTime dt,
      required List<Map<String, dynamic>> stopList,
    }) {
      final base = <String, dynamic>{
        'driverId': driverId,
        'driverName': _auth.currentUser?.displayName ?? '',
        'status': 'active',

        // Human-facing labels
        'origin': displayOrigin,
        'destination': displayDestination,

        // Normalized fields that the search page uses
        'originLower': originToken,
        'destinationLower': destinationToken,
        'originLat': oLat,
        'originLng': oLng,
        'destinationLat': dLat,
        'destinationLng': dLng,
        'originCountry': oCountry,
        'destinationCountry': dCountry,

        // Stops (each includes location + locationLower + lat/lng)
        'stops': stopList,

        // Matching helpers
        'corridorKey': corridor,

        // Schedule
        'date': Timestamp.fromDate(dt),
        'time': _hhmm(dt),

        // Capacity/Pricing
        'seatsTotal': seatsTotal,
        'pricePerSeat': pricePerSeat,

        // Options
        'allowsPets': allowsPets,
        'luggageSize': luggageSize,
        'carModel': carModel,
        'carColor': carColor,
        'isPremiumSeatAvailable': isPremiumSeatAvailable,
        'premiumExtra': premiumExtra,
        'extraLuggagePrice': extraLuggagePrice,

        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // 👉 Only write distance/duration if provided (keeps older trips safe)
      if (distanceKm != null) {
        base['distanceKm'] = distanceKm;
      }
      if (durationMinutes != null) {
        base['durationMinutes'] = durationMinutes;
      }
      base['platformFeePercent'] = platformFeePercent;

      return base;
    }

    // --------- Create OUTBOUND ---------
    final outDoc = await _db.collection('trips').add(_tripMap(
          driverId: uid,
          displayOrigin: origin.displayName,
          displayDestination: dest.displayName,
          originToken: origin.token,
          destinationToken: dest.token,
          oLat: origin.lat,
          oLng: origin.lng,
          dLat: dest.lat,
          dLng: dest.lng,
          oCountry: origin.countryCode,
          dCountry: dest.countryCode,
          dt: outDateTime,
          stopList: resolvedStops,
        ));

    String? retId;

    // --------- Optional RETURN (reverse route + reversed stops) ---------
    if (createReturn) {
      final rt = returnDateTime ?? outDateTime;
      final reversedStops =
          List<Map<String, dynamic>>.from(resolvedStops.reversed)
              .asMap()
              .entries
              .map((e) => {
                    ...e.value,
                    'order': e.key, // re-index
                  })
              .toList();

      final retDoc = await _db.collection('trips').add(_tripMap(
            driverId: uid,
            displayOrigin: dest.displayName,
            displayDestination: origin.displayName,
            originToken: dest.token,
            destinationToken: origin.token,
            oLat: dest.lat,
            oLng: dest.lng,
            dLat: origin.lat,
            dLng: origin.lng,
            oCountry: dest.countryCode,
            dCountry: origin.countryCode,
            dt: rt,
            stopList: reversedStops,
          ));

      // Keep a pointer for convenience
      await outDoc.update({
        'returnTripId': retDoc.id,
        'returnDate': Timestamp.fromDate(rt),
      });
      await retDoc.update({'pairedTripId': outDoc.id});
      retId = retDoc.id;
    }

    return (outId: outDoc.id, retId: retId);
  }

  static String _hhmm(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}
