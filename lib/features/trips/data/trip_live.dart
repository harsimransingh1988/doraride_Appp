// lib/features/trips/data/trip_live.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class TripLive {
  final String id;
  final String origin;
  final String destination;
  final DateTime departureAt;

  final double price;              // per-seat for offers; 0 for requests
  final int seatsTotal;            // driver capacity OR seats requested
  final int seatsAvailable;        // keep in sync with seatsTotal on create

  final String driverName;
  final String driverId;

  // optional vehicle/prefs/notes
  final String? carModel;
  final String? carColor;
  final bool allowsPets;
  final bool isPremiumSeatAvailable;
  final String luggageSize;        // 'N' | 'S' | 'M' | 'L'
  final String description;

  final String status;             // "open" | "full" | "closed"
  final DateTime createdAt;
  final DateTime updatedAt;

  TripLive({
    required this.id,
    required this.origin,
    required this.destination,
    required this.departureAt,
    required this.price,
    required this.seatsTotal,
    required this.seatsAvailable,
    required this.driverName,
    required this.driverId,
    this.carModel,
    this.carColor,
    this.allowsPets = false,
    this.isPremiumSeatAvailable = false,
    this.luggageSize = 'M',
    this.description = '',
    this.status = 'open',
    required this.createdAt,
    required this.updatedAt,
  });

  factory TripLive.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return TripLive(
      id: doc.id,
      origin: d['origin'] as String,
      destination: d['destination'] as String,
      departureAt: (d['departureAt'] as Timestamp).toDate(),
      price: (d['price'] as num).toDouble(),
      seatsTotal: d['seatsTotal'] as int,
      seatsAvailable: d['seatsAvailable'] as int,
      driverName: d['driverName'] as String,
      driverId: d['driverId'] as String,
      carModel: d['carModel'] as String?,
      carColor: d['carColor'] as String?,
      allowsPets: (d['allowsPets'] as bool?) ?? false,
      isPremiumSeatAvailable: (d['isPremiumSeatAvailable'] as bool?) ?? false,
      luggageSize: (d['luggageSize'] as String?) ?? 'M',
      description: (d['description'] as String?) ?? '',
      status: d['status'] as String? ?? 'open',
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      updatedAt: (d['updatedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        // required
        'origin': origin,
        'destination': destination,
        'departureAt': Timestamp.fromDate(departureAt),

        'price': price,
        'seatsTotal': seatsTotal,
        'seatsAvailable': seatsAvailable,

        'driverName': driverName,
        'driverId': driverId,

        // optional / prefs
        'carModel': carModel,
        'carColor': carColor,
        'allowsPets': allowsPets,
        'isPremiumSeatAvailable': isPremiumSeatAvailable,
        'luggageSize': luggageSize,
        'description': description,

        // status + meta
        'status': status,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),

        // 🔎 server-side search helpers (lowercased)
        'originLower': origin.toLowerCase(),
        'destinationLower': destination.toLowerCase(),
      };
}
