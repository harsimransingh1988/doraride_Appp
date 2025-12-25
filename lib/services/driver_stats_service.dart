import 'package:cloud_firestore/cloud_firestore.dart';

class DriverStatsService {
  DriverStatsService._();
  static final DriverStatsService instance = DriverStatsService._();

  final _db = FirebaseFirestore.instance;

  /// Increment how many people this driver has driven.
  /// `seats` = number of seats that were actually occupied in that booking.
  Future<void> incrementPeopleDriven({
    required String driverId,
    required int seats,
  }) async {
    if (driverId.isEmpty || seats <= 0) return;

    final userRef = _db.collection('users').doc(driverId);

    await userRef.set(
      {
        'peopleDriven': FieldValue.increment(seats),
      },
      SetOptions(merge: true),
    );
  }

  /// Optional: also store it on the trip doc (for quick reading in search).
  Future<void> incrementTripPeopleDriven({
    required String tripId,
    required int seats,
  }) async {
    if (tripId.isEmpty || seats <= 0) return;

    final tripRef = _db.collection('trips').doc(tripId);

    await tripRef.set(
      {
        'driverPeopleDriven': FieldValue.increment(seats),
      },
      SetOptions(merge: true),
    );
  }
}
