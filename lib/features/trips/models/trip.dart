import 'package:cloud_firestore/cloud_firestore.dart';

class Trip {
  final String id;
  final String origin;
  final String destination;
  final DateTime departureAt;
  final double price;
  final int seatsTotal;
  final int seatsAvailable;
  final String driverId;
  final String driverName;
  final String carModel;
  final String carColor;

  // optional UX fields
  final String luggageSize; // e.g. "Medium"
  final bool allowsPets;
  final bool isPremiumSeatAvailable;
  final String description;
  final String status; // open | full | cancelled | completed
  final DateTime createdAt;
  final DateTime updatedAt;

  Trip({
    required this.id,
    required this.origin,
    required this.destination,
    required this.departureAt,
    required this.price,
    required this.seatsTotal,
    required this.seatsAvailable,
    required this.driverId,
    required this.driverName,
    required this.carModel,
    required this.carColor,
    this.luggageSize = "Medium",
    this.allowsPets = false,
    this.isPremiumSeatAvailable = false,
    this.description = "",
    this.status = "open",
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // ---------- Firestore converter ----------
  static final _col = FirebaseFirestore.instance
      .collection('trips')
      .withConverter<Trip>(
        fromFirestore: (snap, _) {
          final d = snap.data()!;
          return Trip(
            id: snap.id,
            origin: (d['origin'] ?? '').toString(),
            destination: (d['destination'] ?? '').toString(),
            departureAt: (d['departureAt'] as Timestamp?)?.toDate() ??
                DateTime.tryParse(d['departureAt']?.toString() ?? '') ??
                DateTime.now(),
            price: (d['price'] is int)
                ? (d['price'] as int).toDouble()
                : (d['price'] ?? 0.0) * 1.0,
            seatsTotal: (d['seatsTotal'] ?? 1) as int,
            seatsAvailable: (d['seatsAvailable'] ?? 1) as int,
            driverId: (d['driverId'] ?? '').toString(),
            driverName: (d['driverName'] ?? '').toString(),
            carModel: (d['carModel'] ?? '').toString(),
            carColor: (d['carColor'] ?? '').toString(),
            luggageSize: (d['luggageSize'] ?? 'Medium').toString(),
            allowsPets: (d['allowsPets'] ?? false) as bool,
            isPremiumSeatAvailable: (d['isPremiumSeatAvailable'] ?? false) as bool,
            description: (d['description'] ?? '').toString(),
            status: (d['status'] ?? 'open').toString(),
            createdAt: (d['createdAt'] as Timestamp?)?.toDate() ??
                DateTime.tryParse(d['createdAt']?.toString() ?? '') ??
                DateTime.now(),
            updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ??
                DateTime.tryParse(d['updatedAt']?.toString() ?? '') ??
                DateTime.now(),
          );
        },
        toFirestore: (trip, _) => {
          'origin': trip.origin,
          'destination': trip.destination,
          'departureAt': Timestamp.fromDate(trip.departureAt),
          'price': trip.price,
          'seatsTotal': trip.seatsTotal,
          'seatsAvailable': trip.seatsAvailable,
          'driverId': trip.driverId,
          'driverName': trip.driverName,
          'carModel': trip.carModel,
          'carColor': trip.carColor,
          'luggageSize': trip.luggageSize,
          'allowsPets': trip.allowsPets,
          'isPremiumSeatAvailable': trip.isPremiumSeatAvailable,
          'description': trip.description,
          'status': trip.status,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

  static CollectionReference<Trip> col() => _col;
}
