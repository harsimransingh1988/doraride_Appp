// lib/common/models/trip_model.dart

// Note: This model is used primarily for mock data loading and router arguments.

enum TripType { offer, request }

/// Defines the fields necessary to display a single trip in the search results
/// and on the details page. Used primarily for mock data.
class MockTripDetail {
  final String id;
  final String origin;
  final String destination;
  final String dateString;
  final String timeString;
  final double price;
  final int availableSeats;
  final String driverName;
  final String driverRating; // e.g., "4.5 (10)"
  final String carModel;
  final String carColor;
  final bool allowsPets;
  final String description;
  final String luggageSize;
  final bool isPremiumSeatAvailable;
  final double premiumExtra;
  final double extraLuggagePrice;
  final TripType type;

  // NEW: driver verified flag for mock trips
  final bool isDriverVerified;

  const MockTripDetail({
    required this.id,
    required this.origin,
    required this.destination,
    required this.dateString,
    required this.timeString,
    required this.price,
    required this.availableSeats,
    this.driverName = 'Unknown Driver',
    this.driverRating = '5.0 (0)',
    this.carModel = 'Sedan',
    this.carColor = 'Black',
    this.allowsPets = false,
    this.description = 'A comfortable and friendly shared journey.',
    this.luggageSize = 'M',
    this.isPremiumSeatAvailable = false,
    this.premiumExtra = 0.0,
    this.extraLuggagePrice = 0.0,
    this.type = TripType.offer,
    this.isDriverVerified = false, // NEW default
  });
}
