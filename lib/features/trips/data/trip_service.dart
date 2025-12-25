// lib/features/trips/data/trip_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'trip_live.dart';

class TripService {
  TripService._();
  static final TripService instance = TripService._();

  final _col = FirebaseFirestore.instance.collection('trips_live');

  Future<String> create(TripLive t) async {
    final doc = _col.doc();
    await doc.set(t.toFirestore());
    return doc.id;
  }

  Future<void> update(String id, Map<String, dynamic> data) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _col.doc(id).update(data);
  }

  Stream<List<TripLive>> openTripsStream({
    DateTime? earliest,
    int minSeats = 1,
  }) {
    var q = _col.where('status', isEqualTo: 'open')
                .where('seatsAvailable', isGreaterThanOrEqualTo: minSeats);
    if (earliest != null) {
      q = q.where('departureAt', isGreaterThanOrEqualTo: Timestamp.fromDate(earliest));
    }
    return q.orderBy('departureAt').limit(50).snapshots().map(
      (snap) => snap.docs.map((d) => TripLive.fromFirestore(d)).toList(),
    );
  }
}
