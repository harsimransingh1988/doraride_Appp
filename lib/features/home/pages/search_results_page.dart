// lib/features/home/pages/search_results_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ NEW

import 'package:doraride_appp/common/models/trip_model.dart';
import '../../../app_router.dart';

// NEW: worldwide dynamic resolver
import 'package:doraride_appp/services/geo_resolver.dart';

// Theme
const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

// Toggle dynamic corridor match
const _enableDynamicCorridor = true;

// Corridor thresholds
const double _kmSameCountry = 55.0;
const double _kmDifferentCountry = 35.0;

/// ✅ Shared helpers for guest detection + popup
Future<bool> _isGuestUser() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('is_guest') == true;
}

void _showGuestRegisterDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Create an account to continue'),
      content: const Text(
        'Guests can browse trips, but to book a ride or chat with riders you need to sign in or register.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            Navigator.of(context).pushNamed(Routes.register);
          },
          child: const Text('Register now'),
        ),
      ],
    ),
  );
}

class SearchResultsPage extends StatelessWidget {
  final String from;
  final String to;
  final DateTime? date; // optional specific day
  final int seats;

  const SearchResultsPage({
    super.key,
    required this.from,
    required this.to,
    this.date,
    this.seats = 1,
  });

  // ---------------- Pricing ----------------
  double _calculateSegmentPrice(
    Map<String, dynamic> data,
    String displayFrom,
    String displayTo,
  ) {
    final segmentPrices =
        (data['segmentPrices'] as Map<String, dynamic>?)?.cast<String, num>() ??
            {};
    final targetKey = '${displayFrom.trim()} to ${displayTo.trim()}';
    final price = segmentPrices[targetKey] ?? 0;
    if (price is num && price > 0) return price.toDouble();

    final basePrice = (data['pricePerSeat'] as num?)?.toDouble() ?? 0.0;
    return basePrice;
  }

  // 🌍 NEW: read or derive currency from trip data (origin country fallback)
  Map<String, String> _readOrDeriveCurrency(Map<String, dynamic> tripData) {
    String code = (tripData['currencyCode'] as String?) ?? '';
    String symbol = (tripData['currencySymbol'] as String?) ?? '';

    // If stored in Firestore, just use it
    if (code.isNotEmpty && symbol.isNotEmpty) {
      return {'code': code, 'symbol': symbol};
    }

    // Fallback: derive from origin country text
    final origin = (tripData['origin'] ?? '').toString();
    if (origin.isNotEmpty) {
      final parts = origin.split(',');
      final lastPart =
          (parts.isNotEmpty ? parts.last : origin).trim().toLowerCase();

      if (lastPart.contains('india')) {
        code = 'INR';
        symbol = '₹';
      } else if (lastPart.contains('canada')) {
        code = 'CAD';
        symbol = 'C\$';
      } else if (lastPart.contains('united states') ||
          lastPart == 'usa' ||
          lastPart == 'us' ||
          lastPart.contains('america')) {
        code = 'USD';
        symbol = '\$';
      } else if (lastPart.contains('united kingdom') ||
          lastPart.contains('england') ||
          lastPart == 'uk') {
        code = 'GBP';
        symbol = '£';
      } else if (lastPart.contains('germany') ||
          lastPart.contains('france') ||
          lastPart.contains('italy') ||
          lastPart.contains('spain') ||
          lastPart.contains('europe') ||
          lastPart.contains('euro')) {
        code = 'EUR';
        symbol = '€';
      }
    }

    // Final default if nothing matched
    code = code.isNotEmpty ? code : 'USD';
    symbol = symbol.isNotEmpty ? symbol : '\$';

    return {'code': code, 'symbol': symbol};
  }

  // -------------- Firestore fetch (+accepted bookings) --------------
  Future<Map<String, List<Map<String, dynamic>>>> _fetchData(
      DateTime startOfWindow) async {
    final tripsSnap = await FirebaseFirestore.instance
        .collection('trips')
        .where('status', isEqualTo: 'active')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWindow))
        .orderBy('date', descending: false)
        .limit(100)
        .get();

    final tripDocs =
        tripsSnap.docs.map((d) => d.data()..['id'] = d.id).toList();

    // pull accepted bookings for each trip
    final bookingSnaps = await Future.wait(tripDocs.map((trip) {
      final tripId = trip['id'] as String;
      return FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .collection('booking_requests')
          .where('status', isEqualTo: 'accepted')
          .get();
    }));

    for (var i = 0; i < tripDocs.length; i++) {
      tripDocs[i]['_bookings'] =
          bookingSnaps[i].docs.map((d) => d.data()).toList();
    }

    final requestsSnap = await FirebaseFirestore.instance
        .collection('requests')
        .where('status', isEqualTo: 'active')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWindow))
        .orderBy('date', descending: false)
        .limit(50)
        .get();

    final requestDocs =
        requestsSnap.docs.map((d) => d.data()..['id'] = d.id).toList();

    return {'trips': tripDocs, 'requests': requestDocs};
  }

  // -------------- Trip itinerary helpers --------------
  List<String> _getTripPointsLower(Map<String, dynamic> tripData) {
    String readOrigin() {
      final v = tripData['originLower'] ?? tripData['origin'] ?? '';
      return v.toString().toLowerCase().trim();
    }

    String readDestination() {
      final v = tripData['destinationLower'] ?? tripData['destination'] ?? '';
      return v.toString().toLowerCase().trim();
    }

    List<String> readStops() {
      final stops = (tripData['stops'] as List<dynamic>?) ?? const [];
      return stops
          .map((s) => s is Map
              ? (s['locationLower'] ?? s['location'] ?? '')
                  .toString()
                  .toLowerCase()
                  .trim()
              : s.toString().toLowerCase().trim())
          .toList();
    }

    return [readOrigin(), ...readStops(), readDestination()];
  }

  List<String> _getTripPointsRaw(Map<String, dynamic> tripData) {
    final points = <String>[];
    points.add((tripData['origin'] ?? '').toString());
    final stops = (tripData['stops'] as List<dynamic>?) ?? const [];
    for (final s in stops) {
      if (s is Map) {
        final loc = (s['location'] ?? s['locationLower'] ?? '').toString();
        if (loc.trim().isNotEmpty) points.add(loc);
      } else {
        final loc = s.toString();
        if (loc.trim().isNotEmpty) points.add(loc);
      }
    }
    points.add((tripData['destination'] ?? '').toString());
    return points;
  }

  // Map a booking to indices on this trip
  List<int> _bookingIndicesOnTrip({
    required Map<String, dynamic> tripData,
    required String bookFromRaw,
    required String bookToRaw,
  }) {
    final points = _getTripPointsLower(tripData);
    final bFrom = bookFromRaw.toLowerCase().trim();
    final bTo = bookToRaw.toLowerCase().trim();
    final s = points.indexOf(bFrom);
    final e = points.indexOf(bTo);
    if (s != -1 && e != -1 && s < e) return [s, e];
    return [-1, -1];
  }

  // -------------- Real-time segment availability (indices-based) --------------
  int _calculateSegmentAvailabilityByIndices({
    required Map<String, dynamic> tripData,
    required int startIdx,
    required int endIdx,
  }) {
    final int totalCapacity = (tripData['seatsTotal'] ?? 0) as int;
    if (totalCapacity == 0) return 0;
    if (startIdx < 0 || endIdx <= startIdx) return 0;

    final bookings = (tripData['_bookings'] as List<dynamic>?)
            ?.map((b) => b as Map<String, dynamic>)
            .toList() ??
        [];

    int maxOccupiedOnSegment = 0;

    for (int i = startIdx; i < endIdx; i++) {
      int occupiedOnThisStep = 0;

      for (final booking in bookings) {
        final bFrom = (booking['from'] ?? '').toString();
        final bTo = (booking['to'] ?? '').toString();
        final seats = (booking['seats'] ?? 1) as int;

        final be = _bookingIndicesOnTrip(
          tripData: tripData,
          bookFromRaw: bFrom,
          bookToRaw: bTo,
        );
        final bs = be[0];
        final beIdx = be[1];
        if (bs == -1 || beIdx == -1) continue;

        final overlaps = (bs <= i) && (beIdx > i);
        if (overlaps) occupiedOnThisStep += seats;
      }

      if (occupiedOnThisStep > maxOccupiedOnSegment) {
        maxOccupiedOnSegment = occupiedOnThisStep;
      }
    }

    return totalCapacity - maxOccupiedOnSegment;
  }

  // ---- lightweight name similarity to keep endpoints sane ----
  bool _nameLooksLike(String a, String b) {
    String head(String s) => s.toLowerCase().split(',').first.trim();
    final ha = head(a);
    final hb = head(b);
    if (ha == hb) return true;
    if (ha.startsWith(hb) || hb.startsWith(ha)) return true;
    if (ha.contains(hb) || hb.contains(ha)) return true;
    return false;
  }

  // -------------- dynamic corridor check --------------
  Future<bool> _isDynamicCorridorMatch(Map<String, dynamic> trip) async {
    if (!_enableDynamicCorridor) return false;

    final origin = (trip['origin'] ?? '').toString();
    final dest = (trip['destination'] ?? '').toString();

    return GeoResolver.instance.corridorMatch(
      tripOrigin: origin,
      tripDestination: dest,
      searchFrom: from,
      searchTo: to,
      kmSameCountry: _kmSameCountry,
      kmDifferentCountry: _kmDifferentCountry,
    );
  }

  // ---------- NEW: detect if Premium front seat is already taken ----------
  bool _isPremiumFrontSeatTaken(Map<String, dynamic> trip) {
    // explicit flag on trip (recommended to set during booking)
    final flag = (trip['premiumFrontSeatTaken'] ?? false) as bool;
    if (flag) return true;

    // derive from accepted bookings pulled above
    final bookingsRaw = (trip['_bookings'] as List<dynamic>?) ?? const [];
    for (final b in bookingsRaw) {
      if (b is Map<String, dynamic>) {
        final selected = (b['premiumSeatSelected'] ?? b['premium'] ?? false);
        if (selected == true) return true;
      }
    }
    return false;
  }

  // -------- find the itinerary pair (indices) that matches the search
  Future<List<int>?> _findMatchingItinerarySegment(
    Map<String, dynamic> trip,
    String fromFilter,
    String toFilter,
  ) async {
    final pointsLower = _getTripPointsLower(trip);
    final pointsRaw = _getTripPointsRaw(trip);

    // 1) Exact literal match along itinerary
    final lf = fromFilter.toLowerCase();
    final lt = toFilter.toLowerCase();
    final si = pointsLower.indexOf(lf);
    final ti = pointsLower.indexOf(lt);
    if (si != -1 && ti != -1 && si < ti) return [si, ti];

    // 2) Corridor on whole endpoints (looser: at least one resembles)
    if (await _isDynamicCorridorMatch(trip)) {
      final originRaw = (trip['origin'] ?? '').toString();
      final destRaw = (trip['destination'] ?? '').toString();
      final looksRight =
          _nameLooksLike(originRaw, from) || _nameLooksLike(destRaw, to);
      if (looksRight) return [0, pointsLower.length - 1];
    }

    // 3) Corridor on ANY forward pair within itinerary + relaxed resemblance
    if (_enableDynamicCorridor) {
      for (int i = 0; i < pointsRaw.length - 1; i++) {
        for (int j = i + 1; j < pointsRaw.length; j++) {
          final ok = await GeoResolver.instance.corridorMatch(
            tripOrigin: pointsRaw[i],
            tripDestination: pointsRaw[j],
            searchFrom: from,
            searchTo: to,
            kmSameCountry: _kmSameCountry,
            kmDifferentCountry: _kmDifferentCountry,
          );
          final looksRight =
              _nameLooksLike(pointsRaw[i], from) ||
                  _nameLooksLike(pointsRaw[j], to);
          if (ok && looksRight) return [i, j];
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final fromFilter = from.trim();
    final toFilter = to.trim();
    final title = 'Rides from $fromFilter to $toFilter';

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfWindow = date ?? startOfToday;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: _kThemeBlue,
        automaticallyImplyLeading: true,
      ),
      body: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
        future: _fetchData(startOfWindow),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error loading trips: ${snap.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }

          final allData = snap.data ?? {};
          final tripItems =
              List<Map<String, dynamic>>.from(allData['trips'] ?? const []);
          final requestItems =
              List<Map<String, dynamic>>.from(allData['requests'] ?? const []);

          return FutureBuilder<List<Map<String, dynamic>>>(
            future: () async {
              final out = <Map<String, dynamic>>[];

              for (final m in tripItems) {
                final idx = await _findMatchingItinerarySegment(
                  m,
                  fromFilter,
                  toFilter,
                );
                if (idx == null) continue;

                // Date filter
                if (date != null) {
                  final searchDay =
                      DateTime(date!.year, date!.month, date!.day);

                  DateTime? mainTripDay;
                  final mainTripTs = m['date'];
                  if (mainTripTs is Timestamp) {
                    final t = mainTripTs.toDate();
                    mainTripDay = DateTime(t.year, t.month, t.day);
                  }

                  DateTime? returnTripDay;
                  final returnTripTs = m['returnDate'];
                  if (returnTripTs is Timestamp) {
                    final t = returnTripTs.toDate();
                    returnTripDay = DateTime(t.year, t.month, t.day);
                  }

                  final dateMatch =
                      (mainTripDay == searchDay) || (returnTripDay == searchDay);
                  if (!dateMatch) continue;
                }

                // Attach match indices + computed premium taken
                final copy = Map<String, dynamic>.from(m);
                copy['_matchStart'] = idx[0];
                copy['_matchEnd'] = idx[1];
                copy['_premiumFrontSeatTaken'] = _isPremiumFrontSeatTaken(m);
                out.add(copy);
              }

              return out;
            }(),
            builder: (context, filtSnap) {
              if (filtSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final tripResults = filtSnap.data ?? const [];

              // Requests filtering (display original endpoints)
              final requestFut = () async {
                final out = <Map<String, dynamic>>[];
                for (final m in requestItems) {
                  final reqOriginRaw = (m['origin'] ?? '').toString();
                  final reqDestRaw = (m['destination'] ?? '').toString();

                  final reqOrigin = reqOriginRaw.toLowerCase().trim();
                  final reqDest = reqDestRaw.toLowerCase().trim();

                  bool match =
                      (reqOrigin == fromFilter.toLowerCase().trim() &&
                          reqDest == toFilter.toLowerCase().trim());

                  if (!match && _enableDynamicCorridor) {
                    final ok = await GeoResolver.instance.corridorMatch(
                      tripOrigin: reqOriginRaw,
                      tripDestination: reqDestRaw,
                      searchFrom: from,
                      searchTo: to,
                      kmSameCountry: _kmSameCountry,
                      kmDifferentCountry: _kmDifferentCountry,
                    );
                    final looksRight = _nameLooksLike(reqOriginRaw, from) ||
                        _nameLooksLike(reqDestRaw, to);
                    match = ok && looksRight;
                  }

                  if (!match) continue;

                  if (date != null) {
                    final searchDay =
                        DateTime(date!.year, date!.month, date!.day);
                    final v = m['date'];
                    DateTime? d;
                    if (v is Timestamp) {
                      final t = v.toDate();
                      d = DateTime(t.year, t.month, t.day);
                    }
                    if (d != searchDay) continue;
                  }

                  final seatsRequired = (m['seatsRequired'] ?? 1) as int;
                  if (seatsRequired < seats) continue;

                  out.add(m);
                }
                return out;
              }();

              return FutureBuilder<List<Map<String, dynamic>>>(
                future: requestFut,
                builder: (context, reqSnap) {
                  if (reqSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final requestResults = reqSnap.data ?? const [];

                  if (tripResults.isEmpty && requestResults.isEmpty) {
                    return _EmptyState(
                        from: fromFilter, to: toFilter, date: date);
                  }

                  final totalItems =
                      tripResults.length + requestResults.length;

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: totalItems,
                    itemBuilder: (context, i) {
                      // ---- Trips ----
                      if (i < tripResults.length) {
                        final data = tripResults[i];

                        final v = data['date'];
                        DateTime? dt;
                        if (v is Timestamp) dt = v.toDate();
                        if (v is String) dt = DateTime.tryParse(v);

                        final dateStr = dt == null
                            ? '—'
                            : DateFormat('EEE, MMM d, yyyy').format(dt);
                        final timeStr = (data['time'] is String &&
                                (data['time'] as String).isNotEmpty)
                            ? data['time'] as String
                            : (dt == null
                                ? '—'
                                : DateFormat('h:mm a').format(dt));

                        // Determine which original segment to SHOW (snapped)
                        final pointsRaw = _getTripPointsRaw(data);
                        final sIdx = (data['_matchStart'] ?? -1) as int;
                        final eIdx = (data['_matchEnd'] ?? -1) as int;
                        final premiumTaken =
                            (data['_premiumFrontSeatTaken'] ?? false) as bool;

                        final displayFrom =
                            (sIdx >= 0 && sIdx < pointsRaw.length)
                                ? pointsRaw[sIdx]
                                : (data['origin'] ?? '').toString();
                        final displayTo =
                            (eIdx >= 0 && eIdx < pointsRaw.length)
                                ? pointsRaw[eIdx]
                                : (data['destination'] ?? '').toString();

                        final segmentPrice =
                            _calculateSegmentPrice(data, displayFrom, displayTo);

                        final driverId = (data['driverId'] ?? '') as String;

                        // Availability across the matched indices
                        int available;
                        if (sIdx != -1 && eIdx != -1 && sIdx < eIdx) {
                          available = _calculateSegmentAvailabilityByIndices(
                            tripData: data,
                            startIdx: sIdx,
                            endIdx: eIdx,
                          );
                        } else {
                          available = (data['seatsTotal'] ?? 0) as int;
                        }

                        final isTripFull = available < seats;

                        // premium front seat availability = trip flag AND not taken
                        final bool premiumSeatAvailableFlag =
                            (data['isPremiumSeatAvailable'] ?? false) as bool;
                        final bool showPremiumAvailable =
                            premiumSeatAvailableFlag && !premiumTaken;

                        // NEW: read "people driven" from trip doc
                        int driverPeopleDriven = 0;
                        if (data['peopleDrivenSeats'] is num) {
                          driverPeopleDriven =
                              (data['peopleDrivenSeats'] as num).toInt();
                        } else if (data['driverPeopleDriven'] is num) {
                          // fallback if some older trips used this key
                          driverPeopleDriven =
                              (data['driverPeopleDriven'] as num).toInt();
                        }

                        // 🌍 NEW: read / derive currency for this trip
                        final currency = _readOrDeriveCurrency(data);
                        final currencyCode = currency['code'] ?? 'USD';
                        final currencySymbol = currency['symbol'] ?? '\$';

                        final trip = TripDetail(
                          id: (data['id'] ?? '') as String,
                          origin: displayFrom,
                          destination: displayTo,
                          dateString: dateStr,
                          timeString: timeStr,
                          driverName:
                              (data['driverName'] ?? data['driverId'] ?? 'Driver')
                                  .toString(),
                          driverRating:
                              (data['driverRating'] ?? '5.0').toString(),
                          price: segmentPrice,
                          availableSeats: available,
                          isPremiumSeatAvailable: showPremiumAvailable,
                          premiumExtra:
                              ((data['premiumExtra'] as num?)?.toDouble() ??
                                  0.0),
                          extraLuggagePrice:
                              ((data['extraLuggagePrice'] as num?)
                                      ?.toDouble() ??
                                  0.0),
                          allowsPets:
                              (data['allowsPets'] ?? data['otherPets'] ?? false)
                                  as bool,
                          luggageSize:
                              (data['luggageSize'] ?? 'M').toString(),
                          description: (data['description'] ?? '').toString(),
                          carModel: (data['carModel'] ?? '').toString(),
                          carColor: (data['carColor'] ?? '').toString(),
                          peopleDriven: driverPeopleDriven, // NEW
                          currencyCode: currencyCode, // NEW
                          currencySymbol: currencySymbol, // NEW
                        );

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.only(left: 4, bottom: 4),
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _kThemeBlue.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Matches your search segment: $fromFilter → $toFilter',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: _kThemeBlue,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (!showPremiumAvailable &&
                                      premiumSeatAvailableFlag)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withOpacity(0.18),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'Front seat booked',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.black87,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            _TripResultCard(
                              trip: trip,
                              driverId: driverId,
                              isTripFull: isTripFull,
                              requestedSeats: seats, // ✅ name fixed
                              premiumFrontSeatTaken: premiumTaken,
                            ),
                          ],
                        );
                      }

                      // ---- Requests ---- (DISPLAY original request endpoints)
                      final data = requestResults[i - tripResults.length];

                      final v = data['date'];
                      DateTime? dt;
                      if (v is Timestamp) dt = v.toDate();
                      if (v is String) dt = DateTime.tryParse(v);

                      final dateStr = dt == null
                          ? '—'
                          : DateFormat('EEE, MMM d, yyyy').format(dt);
                      final timeStr = (data['time'] is String &&
                              (data['time'] as String).isNotEmpty)
                          ? data['time'] as String
                          : (dt == null
                              ? '—'
                              : DateFormat('h:mm a').format(dt));

                      final riderId = (data['riderUid'] ?? '') as String;
                      final riderName = (data['riderName'] ?? 'Rider') as String;
                      final seatsRequired = (data['seatsRequired'] ?? 1) as int;

                      final displayFrom = (data['origin'] ?? '').toString();
                      final displayTo = (data['destination'] ?? '').toString();

                      return _RequestResultCard(
                        requestId: (data['id'] ?? '') as String,
                        origin: displayFrom,
                        destination: displayTo,
                        dateString: dateStr,
                        timeString: timeStr,
                        riderName: riderName,
                        riderId: riderId,
                        seatsRequired: seatsRequired,
                        allowsPets: (data['allowsPets'] ?? false) as bool,
                        luggageSize: (data['luggageSize'] ?? 'M').toString(),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------- View model used by the card & navigator ----------------
class TripDetail {
  final String id;
  final String origin;
  final String destination;
  final String dateString;
  final String timeString;
  final String driverName;
  final String driverRating;
  final double price;
  final int availableSeats;
  final bool isPremiumSeatAvailable;
  final double premiumExtra;
  final double extraLuggagePrice;
  final bool allowsPets;
  final String luggageSize;
  final String description;
  final String carModel;
  final String carColor;
  final int peopleDriven; // NEW
  final String currencyCode; // NEW
  final String currencySymbol; // NEW

  TripDetail({
    required this.id,
    required this.origin,
    required this.destination,
    required this.dateString,
    required this.timeString,
    required this.driverName,
    required this.driverRating,
    required this.price,
    required this.availableSeats,
    required this.isPremiumSeatAvailable,
    required this.premiumExtra,
    required this.extraLuggagePrice,
    required this.allowsPets,
    required this.luggageSize,
    required this.description,
    required this.carModel,
    required this.carColor,
    required this.peopleDriven,
    required this.currencyCode,
    required this.currencySymbol,
  });
}

/// Small holder for driver header info (name, photo, rating, people driven)
class _DriverHeaderData {
  final String name;
  final String? photoUrl;
  final bool verified;
  final double rating;
  final int peopleDriven;

  _DriverHeaderData({
    required this.name,
    required this.photoUrl,
    required this.verified,
    required this.rating,
    required this.peopleDriven,
  });
}

/// Load REAL rating from `reviews` + peopleDriven from user doc / trip
Future<_DriverHeaderData> _loadDriverHeaderData(
  String driverId,
  TripDetail trip,
) async {
  String name = trip.driverName;
  String? photoUrl;
  bool verified = false;

  // start from trip rating (usually "5.0" fallback)
  double ratingValue = double.tryParse(trip.driverRating) ?? 5.0;

  // start from trip-level peopleDriven
  int peopleDriven = trip.peopleDriven;

  // 1) Read user profile
  final userSnap =
      await FirebaseFirestore.instance.collection('users').doc(driverId).get();
  if (userSnap.exists) {
    final user = userSnap.data() ?? {};

    name = (user['displayName'] ??
            user['fullName'] ??
            user['name'] ??
            name)
        .toString();

    photoUrl = (user['photoUrl'] ??
            user['profilePhotoUrl'] ??
            user['avatarUrl'] ??
            '')
        .toString();

    verified = (user['isVerified'] == true) ||
        (user['driverVerified'] == true) ||
        (user['isDriverVerified'] == true) ||
        (user['isVerifiedDriver'] == true) ||
        (user['accountVerified'] == true) ||
        (user['verificationStatus'] == 'verified') ||
        (user['driverStatus'] == 'verified');

    if (user['rating'] is num) {
      ratingValue = (user['rating'] as num).toDouble();
    }

    // prefer larger peopleDriven from user doc if present
    if (user['peopleDriven'] is num) {
      final userCount = (user['peopleDriven'] as num).toInt();
      if (userCount > peopleDriven) peopleDriven = userCount;
    } else if (user['peopleDrivenSeats'] is num) {
      final userCount = (user['peopleDrivenSeats'] as num).toInt();
      if (userCount > peopleDriven) peopleDriven = userCount;
    }
  }

  // 2) REAL rating: average from reviews where this driver is recipient
  final reviewsSnap = await FirebaseFirestore.instance
      .collection('reviews')
      .where('recipientId', isEqualTo: driverId)
      .get();

  if (reviewsSnap.docs.isNotEmpty) {
    double sum = 0;
    int count = 0;
    for (final doc in reviewsSnap.docs) {
      final data = doc.data();
      final r = data['rating'];
      if (r is num) {
        sum += r.toDouble();
        count++;
      }
    }
    if (count > 0) {
      ratingValue = sum / count;
    }
  }

  return _DriverHeaderData(
    name: name,
    photoUrl: photoUrl,
    verified: verified,
    rating: ratingValue,
    peopleDriven: peopleDriven,
  );
}

// ---------------- Trip Result Card (with OWN-TRIP popup) ----------------
class _TripResultCard extends StatelessWidget {
  final TripDetail trip;
  final String driverId;
  final bool isTripFull;
  final int requestedSeats; // ✅ consistent name
  final bool premiumFrontSeatTaken; // NEW

  _TripResultCard({
    // keep non-const; previous const/non-const flip caused hot-reload error
    required this.trip,
    required this.driverId,
    required this.isTripFull,
    required this.requestedSeats, // ✅ consistent name
    required this.premiumFrontSeatTaken,
  });

  void _showOwnTripSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, size: 44, color: _kThemeBlue),
            const SizedBox(height: 12),
            const Text(
              "You can't book your own trip",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: _kThemeBlue,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You can view or edit the trip instead.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kThemeBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.visibility, color: Colors.white),
                    label: const Text('View Your Trip',
                        style: TextStyle(color: Colors.white)),
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      Future.microtask(() {
                        Navigator.of(context, rootNavigator: true).pushNamed(
                          Routes.home,
                          arguments: {'tab': 'trips'},
                        );
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kThemeGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.edit, color: Colors.white),
                    label: const Text('Edit Trip',
                        style: TextStyle(color: Colors.white)),
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      Future.microtask(() {
                        Navigator.of(context, rootNavigator: true).pushNamed(
                          Routes.postOffer,
                          arguments: {
                            'mode': 'edit',
                            'tripIdToEdit': trip.id,
                          },
                        );
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ratingShort = (trip.driverRating).toString().split(' ').first;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isTripFull
            ? null
            : () async {
                // ✅ 1) Block guests first
                if (await _isGuestUser()) {
                  _showGuestRegisterDialog(context);
                  return;
                }

                final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                if (myUid.isNotEmpty && myUid == driverId) {
                  _showOwnTripSheet(context);
                  return;
                }

                Navigator.pushNamed(
                  context,
                  Routes.tripBooking,
                  arguments: {
                    'tripId': trip.id,
                    'from': trip.origin,
                    'to': trip.destination,
                    'dateString': trip.dateString,
                    'timeString': trip.timeString,
                    'price': trip.price,
                    'availableSeats': trip.availableSeats,
                    'driverName': trip.driverName,
                    'driverId': driverId,
                    'isPremiumSeatAvailable': trip.isPremiumSeatAvailable,
                    'premiumExtra': trip.premiumExtra,
                    'extraLuggagePrice': trip.extraLuggagePrice,
                    'frontSeatTaken': premiumFrontSeatTaken,
                    // 🌍 pass currency through to booking page
                    'currencyCode': trip.currencyCode,
                    'currencySymbol': trip.currencySymbol,
                  },
                );
              },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${trip.dateString} at ${trip.timeString}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _kThemeBlue,
                        ),
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(trip.origin,
                              style: Theme.of(context).textTheme.titleMedium),
                          const Icon(Icons.arrow_downward,
                              size: 16, color: Colors.black54),
                          Text(trip.destination,
                              style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                              '${trip.currencySymbol}${trip.price.toStringAsFixed(2)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color:
                                        isTripFull ? Colors.grey : _kThemeGreen,
                                  )),
                          Text('${trip.availableSeats} seat(s)',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: isTripFull ? Colors.grey : null,
                                  )),
                          if (trip.isPremiumSeatAvailable && !isTripFull)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _kThemeBlue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Premium +${trip.currencySymbol}${trip.premiumExtra.toStringAsFixed(2)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: _kThemeBlue,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 16),

                  /// Driver row: photo + left name + right big rating & people driven
                  FutureBuilder<_DriverHeaderData>(
                    future: _loadDriverHeaderData(driverId, trip),
                    builder: (context, snapshot) {
                      // fallback UI while loading
                      final fallback = _DriverHeaderData(
                        name: trip.driverName,
                        photoUrl: null,
                        verified: false,
                        rating: double.tryParse(ratingShort) ?? 5.0,
                        peopleDriven: trip.peopleDriven,
                      );

                      final info = snapshot.data ?? fallback;

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: _kThemeBlue.withOpacity(0.08),
                            backgroundImage: (info.photoUrl != null &&
                                    info.photoUrl!.isNotEmpty)
                                ? NetworkImage(info.photoUrl!)
                                : null,
                            child: (info.photoUrl == null ||
                                    info.photoUrl!.isEmpty)
                                ? Text(
                                    info.name.isNotEmpty
                                        ? info.name[0].toUpperCase()
                                        : 'D',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: _kThemeBlue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        info.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: isTripFull
                                                  ? Colors.grey
                                                  : null,
                                              fontWeight: FontWeight.w600,
                                            ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (info.verified) ...[
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.verified,
                                        size: 18,
                                        color: _kThemeGreen,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star,
                                    size: 20,
                                    color: isTripFull
                                        ? Colors.grey
                                        : Colors.amber,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    info.rating.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: _kThemeBlue,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${info.peopleDriven} people driven',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isTripFull
                                          ? Colors.grey
                                          : Colors.black87,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
              if (isTripFull)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _kThemeBlue,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Text(
                      'SEATS FULL',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Request Result Card ----------------
class _RequestResultCard extends StatelessWidget {
  final String requestId;
  final String origin; // DISPLAY original request origin
  final String destination; // DISPLAY original request destination
  final String dateString;
  final String timeString;
  final String riderName;
  final String riderId;
  final int seatsRequired;
  final bool allowsPets;
  final String luggageSize;

  const _RequestResultCard({
    required this.requestId,
    required this.origin,
    required this.destination,
    required this.dateString,
    required this.timeString,
    required this.riderName,
    required this.riderId,
    required this.seatsRequired,
    required this.allowsPets,
    required this.luggageSize,
  });

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isMyRequest = myUid.isNotEmpty && myUid == riderId;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _kThemeBlue, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          // ✅ Block guests from starting chat with rider
          if (await _isGuestUser()) {
            _showGuestRegisterDialog(context);
            return;
          }

          if (isMyRequest) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("This is your own ride request.")),
            );
            return;
          }

          Navigator.pushNamed(
            context,
            Routes.chatScreen,
            arguments: {
              'recipientId': riderId,
              'segmentFrom': origin,
              'segmentTo': destination,
              'tripId': null,
              'requestId': requestId,
            },
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$dateString at $timeString',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _kThemeBlue,
                        ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _kThemeBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'RIDE REQUEST',
                      style: TextStyle(
                        color: _kThemeBlue,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(origin,
                          style: Theme.of(context).textTheme.titleMedium),
                      const Icon(Icons.arrow_downward,
                          size: 16, color: Colors.black54),
                      Text(destination,
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$seatsRequired SEAT(S)',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: _kThemeBlue,
                              )),
                      Text('needed',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Empty State ----------------
class _EmptyState extends StatelessWidget {
  final String from;
  final String to;
  final DateTime? date;

  const _EmptyState({required this.from, required this.to, this.date});

  @override
  Widget build(BuildContext context) {
    final when =
        date == null ? '' : ' on ${DateFormat('EEE, MMM d, yyyy').format(date!)}';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No live trips or requests found for "$from → $to"$when yet.\n'
          'Try different dates or check back soon.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
