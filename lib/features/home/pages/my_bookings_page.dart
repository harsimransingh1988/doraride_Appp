import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:doraride_appp/app_router.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class MyBookingsPage extends StatefulWidget {
  const MyBookingsPage({super.key, this.embedded = false});

  /// When embedded in the Trips hub, we hide the page AppBar
  /// and only render the inner tabs + lists.
  final bool embedded;

  @override
  State<MyBookingsPage> createState() => _MyBookingsPageState();
}

class _MyBookingsPageState extends State<MyBookingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 4, vsync: this);

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ratingSub;
  bool _ratingDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _setupRiderRatingListener();
  }

  void _setupRiderRatingListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;

    // Listen for any *completed* booking that still needs rider review
    _ratingSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('my_bookings')
        .where('status', isEqualTo: 'completed')
        .where('needsRiderReview', isEqualTo: true)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      if (snap.docs.isEmpty) return;
      if (_ratingDialogOpen) return; // avoid showing multiple dialogs

      final doc = snap.docs.first;
      final data = doc.data();

      final bookingId = doc.id;
      final tripId = (data['tripId'] ?? '') as String;
      final driverId = (data['driverId'] ?? '') as String;
      final driverName = (data['driverName'] ?? 'your driver').toString();

      if (tripId.isEmpty || driverId.isEmpty) return;

      _showRiderRatingDialog(
        bookingId: bookingId,
        tripId: tripId,
        driverId: driverId,
        driverName: driverName,
      );
    });
  }

  void _showRiderRatingDialog({
    required String bookingId,
    required String tripId,
    required String driverId,
    required String driverName,
  }) {
    _ratingDialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Rate your trip'),
          content: Text('Please rate your experience with $driverName.'),
          actions: [
            TextButton(
              onPressed: () {
                _ratingDialogOpen = false;
                Navigator.of(ctx).pop(); // "Later"
              },
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () {
                _ratingDialogOpen = false;
                Navigator.of(ctx).pop();
                Navigator.pushNamed(
                  context,
                  Routes.rateTrip,
                  arguments: {
                    'bookingId': bookingId,
                    'tripId': tripId,
                    'recipientId': driverId,
                    'recipientName': driverName,
                    'role': 'rider', // rider is rating the driver
                  },
                );
              },
              child: const Text('Rate now'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    _ratingSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        // Inner tab bar for booking statuses
        Material(
          color: widget.embedded ? Colors.white : _kThemeBlue,
          child: TabBar(
            controller: _tab,
            labelColor: widget.embedded ? _kThemeBlue : Colors.white,
            unselectedLabelColor:
                widget.embedded ? Colors.black54 : Colors.white70,
            indicatorColor: widget.embedded ? _kThemeBlue : Colors.white,
            tabs: const [
              Tab(text: 'Pending'),
              Tab(text: 'Accepted'),
              Tab(text: 'Rejected'),
              Tab(text: 'Cancelled'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: const [
              _BookingsList(status: 'pending_driver'),
              _BookingsList(status: 'accepted'),
              _BookingsList(status: 'rejected'),
              _BookingsList(status: 'cancelled'),
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) {
      // Render only content when used inside TripsHubPage
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _kThemeBlue,
        foregroundColor: Colors.white,
        title: const Text('My bookings'),
      ),
      body: body,
    );
  }
}

class _BookingsList extends StatelessWidget {
  const _BookingsList({required this.status});
  final String status;

  // Helper to format date & time into a single line
  String _formatBookingDateTime(String dateStr, String timeStr) {
    // e.g. "Mon, Oct 27, 2025 • 3:30 AM"
    return '$dateStr • $timeStr';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending_driver':
        return Colors.orange;
      case 'accepted':
        return Colors.lightGreenAccent;
      case 'completed':
        return Colors.white;
      case 'rejected':
        return Colors.redAccent;
      case 'cancelled':
      case 'cancelled_by_rider':
      case 'cancelled_by_driver':
        return Colors.grey.shade300;
      default:
        return Colors.white70;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending_driver':
        return 'Waiting';
      case 'accepted':
        return 'Confirmed';
      case 'completed':
        return 'Completed';
      case 'rejected':
        return 'Declined';
      case 'cancelled':
      case 'cancelled_by_rider':
      case 'cancelled_by_driver':
        return 'Cancelled';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const _CenteredInfo(
        title: 'Sign in required',
        subtitle: 'Please sign in to see your bookings.',
        icon: Icons.lock_outline,
      );
    }

    // ✅ Use the rider's own my_bookings collection
    Query<Map<String, dynamic>> base = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('my_bookings');

    // Fix status filtering for different tabs
    if (status == 'pending_driver') {
      base = base.where('status', isEqualTo: 'pending_driver');
    } else if (status == 'accepted') {
      // Accepted tab shows accepted + completed
      base = base.where('status', whereIn: ['accepted', 'completed']);
    } else if (status == 'rejected') {
      base = base.where('status', isEqualTo: 'rejected');
    } else if (status == 'cancelled') {
      // Cancelled tab shows cancelled + cancelled_by_x
      base = base.where(
        'status',
        whereIn: ['cancelled', 'cancelled_by_rider', 'cancelled_by_driver'],
      );
    }

    base = base.orderBy('createdAt', descending: true).limit(13);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: base.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return const _CenteredInfo(
            title: 'Couldn’t load bookings',
            subtitle: 'Please try again shortly.',
            icon: Icons.wifi_off_rounded,
          );
        }

        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const _CenteredInfo(
            title: 'No trips',
            subtitle: 'Once you join or post a trip, it will appear here.',
            icon: Icons.location_on_outlined,
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final snapshot = docs[i];
            final d = snapshot.data();

            final from = (d['from'] ?? '—').toString();
            final to = (d['to'] ?? '—').toString();
            final date = (d['dateString'] ?? '—').toString();
            final time = (d['timeString'] ?? '—').toString();
            final seats = d['seats'] is int ? d['seats'] as int : 1;
            final total =
                d['total'] is num ? (d['total'] as num).toDouble() : 0.0;
            final tripId = (d['tripId'] ?? '').toString();
            final driverName = (d['driverName'] ?? 'Driver').toString();
            final bookingId = snapshot.id;
            final statusRaw = (d['status'] ?? '').toString();

            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                if (tripId.isEmpty) return;
                Navigator.pushNamed(
                  context,
                  Routes.bookingStatus,
                  arguments: {
                    'bookingId': bookingId,
                    'tripId': tripId,
                    'from': from,
                    'to': to,
                    'dateString': date,
                    'timeString': time,
                    'driverName': driverName,
                  },
                );
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kThemeGreen,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    // Icon/Avatar on the left
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.white,
                      child: Icon(
                        Icons.directions_car_outlined,
                        color: _kThemeBlue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Route
                          Text(
                            '$from → $to',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Date/Time and Seats
                          Text(
                            '${_formatBookingDateTime(date, time)} • $seats seat(s)',
                            style: TextStyle(
                              color: Colors.white.withOpacity(.85),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Status chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _statusColor(statusRaw).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _statusColor(statusRaw),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _statusLabel(statusRaw),
                        style: TextStyle(
                          color: _statusColor(statusRaw),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Price on the right
                    Text(
                      '\$${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CenteredInfo extends StatelessWidget {
  const _CenteredInfo(
      {required this.title, required this.subtitle, required this.icon});
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Colors.black26),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: _kThemeBlue,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black.withOpacity(.6),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
