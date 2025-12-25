// lib/features/home/pages/trip_details_page.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_router.dart';
import 'package:doraride_appp/features/chat/open_trip_chat.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

final DateFormat fmtDate = DateFormat('EEE, MMM d, yyyy');
final DateFormat fmtTime = DateFormat('h:mm a');

// We’ll consistently use this label everywhere.
const String kPremiumSeatLabel = 'Premium Front Seat';

class TripDetailsPage extends StatefulWidget {
  final Map<String, dynamic> trip;
  const TripDetailsPage({super.key, required this.trip});

  @override
  State<TripDetailsPage> createState() => _TripDetailsPageState();
}

class _TripDetailsPageState extends State<TripDetailsPage> {
  String? _uid;

  @override
  void initState() {
    super.initState();
    _ensureAuth();
  }

  Future<void> _ensureAuth() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
    if (mounted) setState(() => _uid = auth.currentUser?.uid);
  }

  String _safeFirstLetter(String source) {
    final s = source.trim();
    if (s.isEmpty) return 'D';
    final runes = s.runes;
    return runes.isEmpty ? 'D' : String.fromCharCode(runes.first).toUpperCase();
  }

  Future<void> _tapHeaderToChat({
    required String? tripId,
    required String? driverId,
    required String? riderId,
    required String from,
    required String to,
  }) async {
    if (tripId == null || tripId.isEmpty || driverId == null || driverId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing trip or driver information')),
      );
      return;
    }

    try {
      await openTripChat(
        context: context,
        tripId: tripId,
        driverId: driverId,
        riderId: riderId,
        segmentFrom: from,
        segmentTo: to,
      );
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('TripDetails header tap error: $e\n$st');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn’t open chat.')),
      );
    }
  }

  /// UI-level guard so only one rider can take the Premium Front Seat.
  /// We consider a front seat "taken" if there exists a booking_request
  /// with premiumSeatSelected == true and a status that is NOT cancelled/declined/expired/refunded.
  Future<bool> _isFrontSeatAlreadyBooked(String tripId) async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .collection('booking_requests')
          .where('premiumSeatSelected', isEqualTo: true)
          .get();

      const badStatuses = {'cancelled', 'declined', 'rejected', 'expired', 'refunded'};
      for (final doc in qs.docs) {
        final status = (doc['status'] ?? '').toString().toLowerCase();
        if (!badStatuses.contains(status)) {
          // Anything pending/accepted/confirmed/etc. counts as taken.
          return true;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Front seat check failed: $e');
      }
      // Fail open (not taken) rather than block.
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.trip;

    final bool isRequest = _looksLikeRequest(m);
    final String? driverId =
        (m['driverId'] as String?) ?? (m['driverUid'] as String?);
    final String? riderUid = m['riderUid'] as String?;

    final bool isOwner = _uid != null && (_uid == (isRequest ? riderUid : driverId));

    final String origin = (m['origin'] ?? '') as String;
    final String destination = (m['destination'] ?? '') as String;
    final DateTime dt = _bestDateTime(m);
    final int seats = _bestSeats(m, isRequest: isRequest);
    final double price = _bestPrice(m);

    // Add-on fields (may be missing on older posts)
    final bool isPremiumSeatAvailable =
        (m['isPremiumSeatAvailable'] as bool?) ?? false;
    final double premiumExtra = (m['premiumExtra'] is num)
        ? (m['premiumExtra'] as num).toDouble()
        : 0.0;
    final double extraLuggagePrice = (m['extraLuggagePrice'] is num)
        ? (m['extraLuggagePrice'] as num).toDouble()
        : 0.0;

    final String? tripId =
        (m['id'] as String?) ?? (m['tripId'] as String?) ?? (m['trip_id'] as String?);

    final driverLabel = (m['driverName'] ?? m['driverId'] ?? 'Driver').toString();
    final avatarLetter = _safeFirstLetter(driverLabel);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Details'),
        backgroundColor: _kThemeBlue,
        actions: [
          if (!isOwner && tripId != null && driverId != null)
            IconButton(
              icon: const Icon(Icons.chat, color: Colors.white),
              onPressed: () => _tapHeaderToChat(
                tripId: tripId,
                driverId: driverId,
                riderId: _uid,
                from: origin,
                to: destination,
              ),
              tooltip: 'Chat with Driver',
            ),
        ],
      ),
      body: _uid == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
                  children: [
                    // Header
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: const Color(0xFFE8F5E9),
                                  child: Text(
                                    avatarLetter,
                                    style: const TextStyle(
                                      color: _kThemeGreen,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$origin → $destination',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${fmtDate.format(dt)} at ${fmtTime.format(dt)}',
                                        style: const TextStyle(color: Colors.black87),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Driver: $driverLabel',
                                        style: const TextStyle(color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isOwner)
                                  InkWell(
                                    onTap: () => _tapHeaderToChat(
                                      tripId: tripId,
                                      driverId: driverId,
                                      riderId: _uid,
                                      from: origin,
                                      to: destination,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _kThemeGreen,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.chat, size: 16, color: Colors.white),
                                          SizedBox(width: 4),
                                          Text('Chat', style: TextStyle(color: Colors.white, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    _sectionCard(
                      title: 'Trip Itinerary',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          _iconLine(Icons.place, 'Origin shown above'),
                          _iconLine(Icons.flag, 'Destination shown above'),
                        ],
                      ),
                    ),

                    _sectionCard(
                      title: 'Vehicle Details',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          _kv(icon: Icons.directions_car, label: 'Car', value: '—'),
                          _kv(icon: Icons.calendar_today, label: 'Year', value: '—'),
                          _kv(icon: Icons.palette_outlined, label: 'Color', value: '—'),
                          _kv(icon: Icons.confirmation_num_outlined, label: 'Plate', value: '—'),
                        ],
                      ),
                    ),

                    _sectionCard(
                      title: 'Trip Preferences',
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          _pref(icon: Icons.pets_outlined, label: 'Pets Allowed', value: 'No'),
                          _pref(icon: Icons.luggage_outlined, label: 'Max Luggage', value: 'M'),
                        ],
                      ),
                    ),
                  ],
                ),

                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        icon: Icon(isOwner ? Icons.edit : Icons.event_seat),
                        label: Text(isOwner ? 'Edit' : 'Book Ride'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kThemeBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onPressed: () async {
                          if (isOwner) {
                            final args = {'prefill': m};
                            if (!mounted) return;
                            await Navigator.of(context).pushNamed(
                              isRequest ? Routes.postNeed : Routes.postOffer,
                              arguments: args,
                            );
                            return;
                          }

                          // Build base args with pricing info
                          final baseArgs = _buildBookingArgs(
                            m,
                            dt,
                            seats,
                            price,
                            isPremiumSeatAvailable: isPremiumSeatAvailable,
                            premiumExtra: premiumExtra,
                            extraLuggagePrice: extraLuggagePrice,
                          );

                          // Also check if the front seat is already claimed.
                          bool frontSeatTaken = false;
                          if (baseArgs['tripId'] != null &&
                              (baseArgs['tripId'] as String).isNotEmpty &&
                              isPremiumSeatAvailable) {
                            frontSeatTaken =
                                await _isFrontSeatAlreadyBooked(baseArgs['tripId'] as String);
                          }

                          // Forward a couple more helper flags/labels for the next screen
                          baseArgs['premiumSeatLabel'] = kPremiumSeatLabel;
                          baseArgs['frontSeatTaken'] = frontSeatTaken;

                          if (!mounted) return;
                          await Navigator.of(context).pushNamed(
                            Routes.tripBooking, // your Review/Booking page
                            arguments: baseArgs,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ---------- helpers ----------
  bool _looksLikeRequest(Map<String, dynamic> m) {
    if (m.containsKey('seatsRequired')) return true;
    if (m.containsKey('riderUid') && !m.containsKey('driverId')) return true;
    final kind = (m['kind'] ?? m['type'] ?? '') as String;
    if (kind.toLowerCase().contains('request')) return true;
    return false;
  }

  DateTime _bestDateTime(Map<String, dynamic> m) {
    final candidates = [m['departureAt'], m['dateOut'], m['date'], m['createdAt'], m['postedAt']];
    for (final v in candidates) {
      final d = _asDate(v);
      if (d != null) return d;
    }
    final dateStr = (m['dateString'] ?? m['date_text'] ?? '') as String;
    final timeStr = (m['timeString'] ?? m['time'] ?? '') as String;
    DateTime base = DateTime.now();
    final parsedDate = DateTime.tryParse(dateStr);
    if (parsedDate != null) base = parsedDate;
    if (timeStr.isNotEmpty) {
      final reg = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*([AaPp][Mm])\s*$');
      final mt = reg.firstMatch(timeStr);
      if (mt != null) {
        var h = int.tryParse(mt.group(1)!) ?? 0;
        final min = int.tryParse(mt.group(2)!) ?? 0;
        final ampm = mt.group(3)!.toUpperCase();
        if (ampm == 'PM' && h != 12) h += 12;
        if (ampm == 'AM' && h == 12) h = 0;
        return DateTime(base.year, base.month, base.day, h, min);
      }
    }
    return base;
  }

  int _bestSeats(Map<String, dynamic> m, {required bool isRequest}) {
    final keys = isRequest
        ? ['seatsRequired', 'seats', 'seatCount']
        : ['seatsAvailable', 'availableSeats', 'seats'];
    for (final k in keys) {
      final v = m[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
    }
    return 1;
  }

  double _bestPrice(Map<String, dynamic> m) {
    final v1 = m['pricePerSeat'];
    if (v1 is num) return v1.toDouble();
    final v2 = m['price'];
    if (v2 is num) return v2.toDouble();
    for (final k in const ['price_cents', 'pricePerSeatCents', 'amount_cents']) {
      final v = m[k];
      if (v is num) return (v / 100).toDouble();
    }
    return 0.0;
  }

  Map<String, dynamic> _buildBookingArgs(
    Map<String, dynamic> m,
    DateTime dt,
    int seats,
    double price, {
    required bool isPremiumSeatAvailable,
    required double premiumExtra,
    required double extraLuggagePrice,
  }) {
    final tripId = (m['id'] as String?) ?? (m['tripId'] as String?) ?? (m['trip_id'] as String?) ?? '';
    return <String, dynamic>{
      'tripId': tripId,
      'from': (m['origin'] ?? '') as String,
      'to': (m['destination'] ?? '') as String,
      'dateString': fmtDate.format(dt),
      'timeString': fmtTime.format(dt),
      'price': price,
      'availableSeats': seats,
      'driverName': (m['driverName'] ?? m['driverId'] ?? 'Driver').toString(),
      'driverId': (m['driverId'] ?? m['driverUid'] ?? '').toString(),

      // Add-ons to seed the Review/Payment flow
      'isPremiumSeatAvailable': isPremiumSeatAvailable,
      'premiumExtra': premiumExtra,
      'extraLuggagePrice': extraLuggagePrice,
    };
  }

  DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) {
      final parsed = DateTime.tryParse(v);
      if (parsed != null) return parsed;
    }
    return null;
  }
}

// ----- small UI helpers -----
class _sectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _sectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                )),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _iconLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _iconLine(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _kThemeBlue),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _kv extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _kv({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.black87),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _pref extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _pref({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.black87),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(value),
      ],
    );
  }
}
