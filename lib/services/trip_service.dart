// lib/services/trip_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class TripService {
  final _db = FirebaseFirestore.instance;

  // ---------------------------------------------------------------------------
  // Small internal geohash encoder (5-char precision).
  // This replaces the external `geohash` package so you don't need a dependency.
  // ---------------------------------------------------------------------------
  String _encodeGeohash5(double lat, double lon) {
    const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

    double minLat = -90.0, maxLat = 90.0;
    double minLon = -180.0, maxLon = 180.0;
    bool isEvenBit = true;

    int bit = 0;
    int ch = 0;
    final buffer = StringBuffer();

    while (buffer.length < 5) {
      if (isEvenBit) {
        final mid = (minLon + maxLon) / 2;
        if (lon >= mid) {
          ch |= 1 << (4 - bit);
          minLon = mid;
        } else {
          maxLon = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (lat >= mid) {
          ch |= 1 << (4 - bit);
          minLat = mid;
        } else {
          maxLat = mid;
        }
      }

      isEvenBit = !isEvenBit;

      if (bit < 4) {
        bit++;
      } else {
        buffer.write(base32[ch]);
        bit = 0;
        ch = 0;
      }
    }

    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Post a new trip.
  //
  // - Fails if driver is blocked (isBlocked == true).
  // - Copies driver's effectiveRating (fallback ratingAvg) to driverRatingAvg
  //   so we can sort search results by rating.
  // ---------------------------------------------------------------------------
  Future<void> postTrip({
    required String driverId,
    required String originName,
    required LatLng origin,
    required String destName,
    required LatLng dest,
    required DateTime dateLocal, // date picker value (no time)
    required List<LatLng> sampledRoute,
    required int seats,
    required int price,
  }) async {
    final dateUtc =
        DateTime.utc(dateLocal.year, dateLocal.month, dateLocal.day);

    final driverRef = _db.collection('users').doc(driverId);
    final driverSnap = await driverRef.get();
    final driverData = driverSnap.data() ?? {};

    final isBlocked = (driverData['isBlocked'] as bool?) ?? false;
    if (isBlocked) {
      throw Exception('Driver is blocked and cannot post new trips.');
    }

    final ratingAvgRaw = driverData['ratingAvg'];
    final effectiveRatingRaw = driverData['effectiveRating'];

    double ratingAvg = 0.0;
    if (ratingAvgRaw is num) ratingAvg = ratingAvgRaw.toDouble();

    double effectiveRating = ratingAvg;
    if (effectiveRatingRaw is num) {
      effectiveRating = effectiveRatingRaw.toDouble();
    }

    await _db.collection('trips').add({
      'driverId': driverId,
      'origin': {
        'name': originName,
        'lat': origin.latitude,
        'lng': origin.longitude,
      },
      'destination': {
        'name': destName,
        'lat': dest.latitude,
        'lng': dest.longitude,
      },
      'date': Timestamp.fromDate(dateUtc),
      'route': {
        'sampled': sampledRoute
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
      },
      'geohashOrigin': _encodeGeohash5(origin.latitude, origin.longitude),
      'geohashDest': _encodeGeohash5(dest.latitude, dest.longitude),
      'seats': seats,
      'price': price,
      'driverRatingAvg': effectiveRating, // used for ranking in search
      'status': 'active', // active | completed | cancelled
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // Mark trip as completed and mark all accepted bookings
  // so driver + riders get rating prompts.
  //
  // - trips/{tripId}.status = "completed"
  // - users/{driverId}/my_bookings/{bookingId}:
  //     { status: "completed", needsDriverReview: true }
  // - users/{riderId}/my_bookings/{bookingId}:
  //     { status: "completed", needsRiderReview: true }
  // ---------------------------------------------------------------------------
  Future<void> completeTripAndMarkForReview({
    required String tripId,
    required String driverId,
  }) async {
    final tripRef = _db.collection('trips').doc(tripId);
    final bookingsRef = tripRef.collection('booking_requests');

    final batch = _db.batch();

    // mark trip completed
    batch.update(tripRef, {
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    });

    // find all accepted bookings under this trip
    final accepted =
        await bookingsRef.where('status', isEqualTo: 'accepted').get();

    for (final doc in accepted.docs) {
      final data = doc.data();
      final bookingId = doc.id;
      final riderId = (data['riderId'] ?? '') as String;

      if (riderId.isEmpty) continue;

      // driver-side booking doc
      final driverBookingRef = _db
          .collection('users')
          .doc(driverId)
          .collection('my_bookings')
          .doc(bookingId);

      batch.set(
        driverBookingRef,
        {
          'status': 'completed',
          'needsDriverReview': true,
        },
        SetOptions(merge: true),
      );

      // rider-side booking doc
      final riderBookingRef = _db
          .collection('users')
          .doc(riderId)
          .collection('my_bookings')
          .doc(bookingId);

      batch.set(
        riderBookingRef,
        {
          'status': 'completed',
          'needsRiderReview': true,
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // Driver decision on a booking:
  //
  // - If accept == true:
  //     * booking_requests/{bookingId}.status = "accepted"
  //     * resets consecutiveRejects = 0
  //
  // - If accept == false (reject):
  //     * booking_requests/{bookingId}.status = "rejected"
  //     * increments consecutiveRejects
  //     * if consecutiveRejects == 5 → rating down by 1 star
  //     * if consecutiveRejects >= 10 → isBlocked = true
  //
  // You should call this instead of manually updating the booking.
  // ---------------------------------------------------------------------------
  Future<void> handleDriverDecisionOnBooking({
    required String tripId,
    required String bookingId,
    required String driverId,
    required bool accept,
  }) async {
    final driverRef = _db.collection('users').doc(driverId);
    final bookingRef = _db
        .collection('trips')
        .doc(tripId)
        .collection('booking_requests')
        .doc(bookingId);

    await _db.runTransaction((txn) async {
      final driverSnap = await txn.get(driverRef);
      final bookingSnap = await txn.get(bookingRef);

      if (!bookingSnap.exists) {
        throw Exception('Booking not found.');
      }

      final driverData = driverSnap.data() as Map<String, dynamic>? ?? {};
      final isBlocked = (driverData['isBlocked'] as bool?) ?? false;

      if (isBlocked) {
        throw Exception('Driver is blocked and cannot handle bookings.');
      }

      int consecutiveRejects =
          (driverData['consecutiveRejects'] as int?) ?? 0;

      double ratingAvg = 0.0;
      final ratingAvgRaw = driverData['ratingAvg'];
      if (ratingAvgRaw is num) ratingAvg = ratingAvgRaw.toDouble();

      double effectiveRating = ratingAvg;
      final effectiveRaw = driverData['effectiveRating'];
      if (effectiveRaw is num) {
        effectiveRating = effectiveRaw.toDouble();
      }

      if (accept) {
        // ACCEPT: set status accepted + reset consecutiveRejects
        txn.update(bookingRef, {
          'status': 'accepted',
          'driverDecisionAt': FieldValue.serverTimestamp(),
        });

        txn.set(
          driverRef,
          {
            'consecutiveRejects': 0,
          },
          SetOptions(merge: true),
        );
      } else {
        // REJECT
        consecutiveRejects += 1;

        txn.update(bookingRef, {
          'status': 'rejected',
          'driverDecisionAt': FieldValue.serverTimestamp(),
        });

        bool blockDriver = false;
        double newEffectiveRating = effectiveRating;

        // After 5 consecutive rejects → rating down by 1 star
        if (consecutiveRejects == 5) {
          newEffectiveRating = (effectiveRating - 1.0).clamp(1.0, 5.0);
        }

        // After 10 consecutive rejects → block driver
        if (consecutiveRejects >= 10) {
          blockDriver = true;
        }

        final updateData = <String, dynamic>{
          'consecutiveRejects': consecutiveRejects,
          'effectiveRating': newEffectiveRating,
        };

        if (blockDriver) {
          updateData['isBlocked'] = true;
        }

        txn.set(
          driverRef,
          updateData,
          SetOptions(merge: true),
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Quick prefilter: same day and coarse geohash overlaps.
  //
  // - Only shows status == "active"
  // - Sorts by driverRatingAvg descending (higher rating first).
  // ---------------------------------------------------------------------------
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchCandidates({
    required DateTime dateLocal,
    required String fromGeohash5,
    required String toGeohash5,
  }) async {
    final d0 =
        DateTime.utc(dateLocal.year, dateLocal.month, dateLocal.day);
    final d1 = d0.add(const Duration(days: 1));

    final q = await _db
        .collection('trips')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(d0))
        .where('date', isLessThan: Timestamp.fromDate(d1))
        .where('status', isEqualTo: 'active')
        .get();

    final prefixFrom = fromGeohash5.substring(0, 3);
    final prefixTo = toGeohash5.substring(0, 3);

    final candidates = q.docs.where((doc) {
      final data = doc.data();
      final o = (data['geohashOrigin'] as String?) ?? '';
      final d = (data['geohashDest'] as String?) ?? '';
      return o.startsWith(prefixFrom) ||
          d.startsWith(prefixFrom) ||
          d.startsWith(prefixTo);
    }).toList();

    // Sort by rating (driverRatingAvg) high → low
    candidates.sort((a, b) {
      final ad = a.data();
      final bd = b.data();
      final ra = (ad['driverRatingAvg'] ?? 0) is num
          ? (ad['driverRatingAvg'] as num).toDouble()
          : 0.0;
      final rb = (bd['driverRatingAvg'] ?? 0) is num
          ? (bd['driverRatingAvg'] as num).toDouble()
          : 0.0;
      return rb.compareTo(ra);
    });

    return candidates;
  }
}
