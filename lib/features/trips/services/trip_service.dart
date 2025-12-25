import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/trip.dart';

class TripService {
  TripService._();
  static final instance = TripService._();

  CollectionReference<Trip> get _col => Trip.col();

  Future<void> createTrip(Trip trip) async {
    await _col.add(trip);
  }

  /// Stream upcoming "open" trips, optional origin/destination filters (prefix).
  Stream<List<Trip>> streamTrips({
    String? originStartsWith,
    String? destinationStartsWith,
    DateTime? from,
  }) {
    Query<Trip> q = _col
        .where('status', isEqualTo: 'open')
        .where('departureAt',
            isGreaterThanOrEqualTo:
                Timestamp.fromDate(from ?? DateTime.now()))
        .orderBy('departureAt');

    // simple case-insensitive prefix filters using array of search terms can be added later;
    // for now, we do naive contains on client after stream to avoid complex indexes.
    return q.snapshots().map((snap) {
      final all = snap.docs.map((d) => d.data()).toList();
      return all.where((t) {
        final okOrigin = (originStartsWith == null || originStartsWith.isEmpty)
            ? true
            : t.origin.toLowerCase().contains(originStartsWith.toLowerCase());
        final okDest = (destinationStartsWith == null || destinationStartsWith.isEmpty)
            ? true
            : t.destination.toLowerCase().contains(destinationStartsWith.toLowerCase());
        return okOrigin && okDest;
      }).toList();
    });
  }

  Future<void> decrementSeat(String tripId) async {
    final ref = _col.doc(tripId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return;
      final remaining = (data.seatsAvailable - 1).clamp(0, data.seatsTotal);
      tx.update(ref, {
        'seatsAvailable': remaining,
        'status': remaining == 0 ? 'full' : data.status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
