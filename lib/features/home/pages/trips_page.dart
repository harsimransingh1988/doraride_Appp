// lib/features/home/pages/trips_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:async/async.dart'; // StreamZip

import '../../../app_router.dart';
import 'offer_ride_page.dart';
import 'need_ride_page.dart';
import 'driver_requests_page.dart';
import 'package:doraride_appp/services/chat_service.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

final _fmtDate = DateFormat('EEE, MMM d, yyyy');
final _fmtTime = DateFormat('h:mm a');

/// ------------------------------ PHOTO + RATING HELPERS (NO LOGIC CHANGES)
String _pickPhotoUrl(Map<String, dynamic> m) {
  // Try common keys (safe fallback)
  final keys = [
    'photoUrl',
    'photoURL',
    'profilePhoto',
    'profilePhotoUrl',
    'profileImage',
    'profileImageUrl',
    'avatar',
    'avatarUrl',
    'imageUrl',
  ];
  for (final k in keys) {
    final v = m[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return '';
}

double _avgRatingFromDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  if (docs.isEmpty) return 0.0;
  double sum = 0;
  int count = 0;
  for (final d in docs) {
    final m = d.data();
    final r = m['rating'];
    if (r is num) {
      sum += r.toDouble();
      count += 1;
    }
  }
  if (count == 0) return 0.0;
  return sum / count;
}

Widget _buildStars(double rating, {double size = 14}) {
  // rating 0..5
  final r = rating.clamp(0.0, 5.0);
  final full = r.floor();
  final hasHalf = (r - full) >= 0.5 && full < 5;
  final empty = 5 - full - (hasHalf ? 1 : 0);

  final stars = <Widget>[];
  for (int i = 0; i < full; i++) {
    stars.add(Icon(Icons.star, size: size, color: Colors.amber[700]));
  }
  if (hasHalf) {
    stars.add(Icon(Icons.star_half, size: size, color: Colors.amber[700]));
  }
  for (int i = 0; i < empty; i++) {
    stars.add(Icon(Icons.star_border, size: size, color: Colors.amber[700]));
  }

  return Row(mainAxisSize: MainAxisSize.min, children: stars);
}

class _UserBadgeButton extends StatelessWidget {
  final String userId;
  final String fallbackName;
  final VoidCallback onPressed;
  final bool dense;

  const _UserBadgeButton({
    required this.userId,
    required this.fallbackName,
    required this.onPressed,
    this.dense = true,
  });

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) {
      return Text(
        fallbackName,
        style: const TextStyle(fontWeight: FontWeight.w700),
      );
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, userSnap) {
        Map<String, dynamic> u = {};
        if (userSnap.hasData && userSnap.data!.exists) {
          u = userSnap.data!.data() ?? {};
        }

        final firstName = (u['firstName'] ?? '').toString().trim();
        final lastName = (u['lastName'] ?? '').toString().trim();
        final name = ([firstName, lastName].where((s) => s.isNotEmpty).join(' '))
            .trim()
            .isNotEmpty
            ? ([firstName, lastName].where((s) => s.isNotEmpty).join(' ')).trim()
            : fallbackName;

        final photoUrl = _pickPhotoUrl(u);

        return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('reviews')
              .where('recipientId', isEqualTo: userId)
              .limit(200)
              .get(),
          builder: (context, revSnap) {
            final docs = revSnap.data?.docs ?? [];
            final avg = _avgRatingFromDocs(docs);
            final count = docs.length;

            final padV = dense ? 6.0 : 10.0;
            final padH = dense ? 10.0 : 14.0;
            final avatarSize = dense ? 26.0 : 36.0;
            final titleSize = dense ? 14.0 : 16.0;
            final starSize = dense ? 13.0 : 14.0;

            return InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kThemeBlue.withOpacity(0.18)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: avatarSize / 2,
                      backgroundColor: _kThemeGreen.withOpacity(0.18),
                      backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                      child: photoUrl.isEmpty
                          ? const Icon(Icons.person, color: _kThemeBlue)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: titleSize,
                              color: _kThemeBlue,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildStars(avg, size: starSize),
                              const SizedBox(width: 6),
                              Text(
                                count == 0 ? 'No reviews' : '(${avg.toStringAsFixed(1)}) • $count',
                                style: TextStyle(
                                  fontSize: dense ? 11 : 12,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.chevron_right, color: _kThemeBlue),
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

/// ------------------------------ USER PROFILE DIALOG (phone + email)
Future<void> _showUserProfileDialog(
  BuildContext context, {
  required String userId,
  String? titleName,
}) async {
  if (userId.isEmpty) return;

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titleName?.trim().isNotEmpty == true ? titleName!.trim() : 'Profile'),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return Text('Error: ${snap.error}');
            }
            if (!snap.hasData || !snap.data!.exists) {
              return const Text('Profile not found.');
            }

            final m = snap.data!.data() ?? {};

            final firstName = (m['firstName'] ?? '').toString().trim();
            final lastName = (m['lastName'] ?? '').toString().trim();
            final name = [firstName, lastName].where((s) => s.isNotEmpty).join(' ');

            final email = (m['email'] ?? m['emailAddress'] ?? '').toString().trim();
            final phone = (m['phone'] ?? m['phoneNumber'] ?? '').toString().trim();

            final bio = (m['bio'] ?? '').toString().trim();
            final photoUrl = _pickPhotoUrl(m);

            return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance
                  .collection('reviews')
                  .where('recipientId', isEqualTo: userId)
                  .limit(200)
                  .get(),
              builder: (context, revSnap) {
                final docs = revSnap.data?.docs ?? [];
                final avg = _avgRatingFromDocs(docs);
                final count = docs.length;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: _kThemeGreen.withOpacity(0.18),
                          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                          child: photoUrl.isEmpty
                              ? const Icon(Icons.person, color: _kThemeBlue)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name.isNotEmpty ? name : 'User',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _buildStars(avg, size: 14),
                                  const SizedBox(width: 8),
                                  Text(
                                    count == 0 ? 'No reviews yet' : '${avg.toStringAsFixed(1)} • $count reviews',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _ProfileLine(
                      icon: Icons.phone,
                      label: 'Phone',
                      value: phone.isNotEmpty ? phone : 'Not available',
                    ),
                    const SizedBox(height: 8),
                    _ProfileLine(
                      icon: Icons.email_outlined,
                      label: 'Email',
                      value: email.isNotEmpty ? email : 'Not available',
                    ),
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Bio', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(bio),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      ],
    ),
  );
}

class _ProfileLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ProfileLine({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _kThemeBlue),
        const SizedBox(width: 10),
        SizedBox(
          width: 60,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(value)),
      ],
    );
  }
}

// --- NEW: Helper classes to merge Bookings and Requests ---
abstract class _RiderActivityItem {
  final DateTime date;
  final Map<String, dynamic> data;
  final String id;
  _RiderActivityItem(this.date, this.data, this.id);
}

class _BookingItem extends _RiderActivityItem {
  _BookingItem(DateTime date, Map<String, dynamic> data, String id) : super(date, data, id);
}

class _RequestItem extends _RiderActivityItem {
  _RequestItem(DateTime date, Map<String, dynamic> data, String id) : super(date, data, id);
}
// --- END NEW ---

void _navigateToPostPage(BuildContext context) {
  Navigator.of(context).pushNamed(Routes.homePost);
}

class TripsPage extends StatefulWidget {
  const TripsPage({super.key});
  @override
  State<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends State<TripsPage> with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  String? _uid;

  late TabController _mainTabController;

  @override
  void initState() {
    super.initState();
    _ensureSignedIn();
    _mainTabController = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final rawArgs = ModalRoute.of(context)?.settings.arguments;

    if (rawArgs is String && rawArgs == 'trips') {
      return;
    }

    final args = rawArgs is Map ? rawArgs : null;

    final subview = args?['subview'] as String?;
    if (subview == 'requests' && _mainTabController.index != 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_mainTabController.indexIsChanging) {
          _mainTabController.index = 1;
        }
      });
    }
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    super.dispose();
  }

  Future<void> _ensureSignedIn() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
    setState(() => _uid = _auth.currentUser!.uid);
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final uid = _uid!;
    return Scaffold(
      backgroundColor: _kThemeGreen,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'My Trips',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _kThemeBlue,
        bottom: TabBar(
          controller: _mainTabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'As Driver'),
            Tab(text: 'As Rider'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _mainTabController,
        children: [
          _DriverTripsNestedList(uid: uid),
          _RiderPage(uid: uid),
        ],
      ),
    );
  }
}

class _RiderPage extends StatelessWidget {
  final String uid;
  const _RiderPage({required this.uid});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kThemeGreen,
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            Container(
              color: Colors.white,
              child: const TabBar(
                labelColor: _kThemeBlue,
                unselectedLabelColor: Colors.black54,
                indicatorColor: _kThemeBlue,
                tabs: [
                  Tab(text: 'Active/Future'),
                  Tab(text: 'Past/Recent'),
                  Tab(text: 'Canceled/Rejected'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _RiderCombinedList(
                    uid: uid,
                    dateFilter: 'future',
                    bookingStatusFilter: const ['pending_driver', 'accepted', 'completed'],
                    requestStatusFilter: const ['active'],
                  ),
                  _RiderCombinedList(
                    uid: uid,
                    dateFilter: 'past',
                    bookingStatusFilter: const ['pending_driver', 'accepted', 'completed'],
                    requestStatusFilter: const ['active'],
                  ),
                  _RiderCombinedList(
                    uid: uid,
                    dateFilter: 'none',
                    bookingStatusFilter: const ['cancelled', 'rejected', 'cancelled_by_rider'],
                    requestStatusFilter: const ['cancelled'],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiderCombinedList extends StatelessWidget {
  final String uid;
  final String dateFilter;
  final List<String> bookingStatusFilter;
  final List<String> requestStatusFilter;

  const _RiderCombinedList({
    required this.uid,
    required this.dateFilter,
    required this.bookingStatusFilter,
    required this.requestStatusFilter,
  });

  bool _shouldInclude(_RiderActivityItem item) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (dateFilter == 'none') return true;
    if (dateFilter == 'future') {
      return item.date.isAfter(today) || item.date.isAtSameMomentAs(today);
    }
    if (dateFilter == 'past') {
      return item.date.isBefore(today);
    }
    return false;
  }

  Stream<List<_RiderActivityItem>> _combinedStream() {
    Query<Map<String, dynamic>> bookingsQuery = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('my_bookings')
        .where('type', isEqualTo: 'as_rider');

    if (bookingStatusFilter.isNotEmpty) {
      bookingsQuery = bookingsQuery.where('status', whereIn: bookingStatusFilter);
    }

    final bookingsStream = bookingsQuery.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return _BookingItem(_bestBookingDate(data), data, doc.id);
      }).toList();
    });

    Query<Map<String, dynamic>> requestsQuery =
        FirebaseFirestore.instance.collection('requests').where('riderUid', isEqualTo: uid);

    if (requestStatusFilter.isNotEmpty) {
      requestsQuery = requestsQuery.where('status', whereIn: requestStatusFilter);
    }

    final requestsStream = requestsQuery.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return _RequestItem(_bestTripDate(data), data, doc.id);
      }).toList();
    });

    return StreamZip([bookingsStream, requestsStream]).map((results) {
      final List<_RiderActivityItem> bookings = results[0] as List<_RiderActivityItem>;
      final List<_RiderActivityItem> requests = results[1] as List<_RiderActivityItem>;

      final allItems = [...bookings, ...requests];
      final filteredItems = allItems.where(_shouldInclude).toList();

      filteredItems.sort((a, b) {
        if (dateFilter == 'past' || dateFilter == 'none') {
          return b.date.compareTo(a.date);
        }
        return a.date.compareTo(b.date);
      });

      return filteredItems;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool disableAllTaps = dateFilter != 'future'; // ✅ validation

    return StreamBuilder<List<_RiderActivityItem>>(
      stream: _combinedStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        if (snapshot.hasError) {
          return _ErrorPanel(errorText: snapshot.error.toString());
        }

        final items = snapshot.data ?? [];

        if (items.isEmpty) {
          String emptyText = 'You have no $dateFilter items.';
          if (dateFilter == 'future') {
            emptyText = 'You have no active trips. Find a ride or post a request!';
          }
          if (dateFilter == 'past') emptyText = 'You have no past trips.';
          if (dateFilter == 'none') emptyText = 'You have no cancelled trips.';

          return _Empty(
            text: emptyText,
            buttonAction: dateFilter == 'future'
                ? () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    Navigator.of(context).pushReplacementNamed(
                      Routes.home,
                      arguments: 'search',
                    );
                  }
                : null,
            buttonText: 'Find a Ride',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];

            if (item is _BookingItem) {
              // ✅ past/cancelled: not clickable
              return IgnorePointer(
                ignoring: disableAllTaps,
                child: Opacity(
                  opacity: disableAllTaps ? 0.7 : 1.0,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).pushNamed(
                        Routes.bookingStatus,
                        arguments: {
                          'bookingId': item.id,
                          'tripId': item.data['tripId'] ?? '',
                          'from': item.data['from'] ?? 'N/A',
                          'to': item.data['to'] ?? 'N/A',
                          'dateString': item.data['dateString'] ?? 'N/A',
                          'timeString': item.data['timeString'] ?? 'N/A',
                          'driverName': item.data['driverName'] ?? 'N/A',
                        },
                      );
                    },
                    child: _buildEnhancedBookingCardWithCurrency(
                      item.data,
                      context,
                      item.id,
                      dateFilter,
                    ),
                  ),
                ),
              );
            }

            if (item is _RequestItem) {
              final m = item.data;
              final origin = (m['origin'] ?? '') as String;
              final dest = (m['destination'] ?? '') as String;
              final seats = (m['seatsRequired'] ?? 1) as int;
              final dt = item.date;
              final dateStr = _fmtDate.format(dt);
              final timeStr = (m['time'] is String && (m['time'] as String).isNotEmpty)
                  ? m['time'] as String
                  : _fmtTime.format(dt);

              final bool disableEditing = disableAllTaps;

              return _CardRow(
                leadingIcon: Icons.hail,
                title: '$origin → $dest',
                subtitle: '$dateStr  •  $timeStr  •  $seats seat(s) needed',
                trailing: (dateFilter == 'future') ? _RequestChatBadge(requestId: item.id, myUid: uid) : null,
                tripData: m,
                tripId: item.id,
                isDriverTrip: false,
                disableTap: disableEditing,
              );
            }

            return const SizedBox.shrink();
          },
        );
      },
    );
  }
}

/// ------------------------------ DRIVER TRIPS (nested tabs)
class _DriverTripsNestedList extends StatelessWidget {
  final String uid;
  const _DriverTripsNestedList({required this.uid});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kThemeGreen,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, Routes.driverRequests);
              },
              icon: const Icon(Icons.notifications_active),
              label: const Text('View Booking Requests'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kThemeBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  const TabBar(
                    labelColor: _kThemeBlue,
                    unselectedLabelColor: Colors.black54,
                    indicatorColor: _kThemeBlue,
                    tabs: [
                      Tab(text: 'Active/Future'),
                      Tab(text: 'Past/Recent'),
                      Tab(text: 'Canceled'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _DriverTripsList(
                          uid: uid,
                          dateFilter: 'future',
                          statusFilter: const ['active', 'open'],
                        ),
                        _DriverTripsList(
                          uid: uid,
                          dateFilter: 'past',
                          statusFilter: const ['active', 'open', 'completed'],
                        ),
                        _DriverTripsList(
                          uid: uid,
                          dateFilter: 'none',
                          statusFilter: const ['cancelled', 'deleted'],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverTripsList extends StatelessWidget {
  final String uid;
  final String dateFilter;
  final List<String> statusFilter;
  const _DriverTripsList({
    required this.uid,
    required this.dateFilter,
    required this.statusFilter,
  });

  bool _shouldInclude(Map<String, dynamic> data) {
    final tripDate = _bestTripDate(data);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final status = (data['status'] ?? 'active').toString().toLowerCase();

    if (status == 'cancelled' || status == 'deleted' || status == 'rejected') {
      return dateFilter == 'none';
    }
    if (dateFilter == 'none') {
      return statusFilter.contains(status);
    }
    if (dateFilter == 'future') {
      if (!statusFilter.contains(status)) return false;
      return tripDate.isAfter(today) || tripDate.isAtSameMomentAs(today);
    }
    if (dateFilter == 'past') {
      if (!statusFilter.contains(status)) return false;
      return tripDate.isBefore(today);
    }
    return false;
  }

  bool _shouldShowChatFeatures() {
    return dateFilter == 'future' && statusFilter.any((status) => ['active', 'open', 'accepted'].contains(status));
  }

  Widget _buildRateRidersButton(BuildContext context, String tripId) {
    if (dateFilter != 'past') return const SizedBox.shrink();

    return IconButton(
      icon: Icon(Icons.rate_review_outlined, color: Colors.amber[700]),
      tooltip: 'Rate Riders',
      onPressed: () {
        Navigator.pushNamed(
          context,
          Routes.rateRidersList,
          arguments: {'tripId': tripId},
        );
      },
    );
  }

  Widget _buildBookingRequestsBadge(String tripId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .collection('booking_requests')
          .where('status', isEqualTo: 'pending_driver')
          .snapshots(),
      builder: (context, snapshot) {
        final pendingCount = snapshot.data?.docs.length ?? 0;
        if (pendingCount == 0) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$pendingCount',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPassengerCountBadge(String tripId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .collection('booking_requests')
          .where('status', isEqualTo: 'accepted')
          .snapshots(),
      builder: (context, snapshot) {
        final acceptedBookings = snapshot.data?.docs ?? [];
        if (acceptedBookings.isEmpty) return const SizedBox.shrink();

        int totalPassengers = 0;
        for (final booking in acceptedBookings) {
          final seats = (booking.data()['seats'] as num?)?.toInt() ?? 1;
          totalPassengers += seats;
        }

        if (totalPassengers == 0) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _kThemeGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people, color: Colors.white, size: 12),
              const SizedBox(width: 4),
              Text(
                '$totalPassengers',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChatButton(String tripId) {
    if (!_shouldShowChatFeatures()) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .collection('booking_requests')
          .where('status', isEqualTo: 'accepted')
          .snapshots(),
      builder: (context, snapshot) {
        final acceptedBookings = snapshot.data?.docs ?? [];
        if (acceptedBookings.isEmpty) return const SizedBox.shrink();

        return IconButton(
          icon: const Icon(Icons.message_outlined, color: _kThemeBlue),
          tooltip: 'Chat with Riders',
          onPressed: () {
            _showAcceptedRidersDialog(context, tripId, acceptedBookings);
          },
        );
      },
    );
  }

  void _showAcceptedRidersDialog(
    BuildContext context,
    String tripId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> acceptedBookings,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chat with Riders'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: acceptedBookings.length,
            itemBuilder: (context, index) {
              final booking = acceptedBookings[index].data();
              final riderId = (booking['riderId'] ?? '').toString();
              final riderName = booking['riderName'] as String? ?? 'Rider';
              final seats = (booking['seats'] as num?)?.toInt() ?? 1;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: _UserBadgeButton(
                        userId: riderId,
                        fallbackName: riderName,
                        onPressed: () {
                          _showUserProfileDialog(
                            context,
                            userId: riderId,
                            titleName: riderName,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: _kThemeBlue.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kThemeBlue.withOpacity(0.12)),
                      ),
                      child: Text(
                        '$seats',
                        style: const TextStyle(fontWeight: FontWeight.w900, color: _kThemeBlue),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      tooltip: 'Chat',
                      icon: const Icon(Icons.message, color: _kThemeBlue),
                      onPressed: () {
                        Navigator.pop(context);
                        final me = FirebaseAuth.instance.currentUser?.uid ?? '';
                        if (me.isEmpty) return;
                        final chatId = ChatService().getTripChatId(tripId, me, riderId);
                        Navigator.pushNamed(
                          context,
                          Routes.chatScreen,
                          arguments: {
                            'chatId': chatId,
                            'recipientId': riderId,
                            'tripId': tripId,
                            'segmentFrom': booking['from'] ?? '',
                            'segmentTo': booking['to'] ?? '',
                          },
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final collectionName = dateFilter == 'future' ? 'trips_live' : 'trips';
    final stream = FirebaseFirestore.instance.collection(collectionName).where('driverId', isEqualTo: uid).snapshots();

    final bool disableEditing = (dateFilter == 'past' || dateFilter == 'none'); // ✅ no click

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }

        final allDocs = snap.data?.docs ?? [];
        final docs = allDocs.where((doc) => _shouldInclude(doc.data())).toList();

        docs.sort((a, b) {
          final ad = _bestTripDate(a.data());
          final bd = _bestTripDate(b.data());
          if (dateFilter == 'future') return ad.compareTo(bd);
          return bd.compareTo(ad);
        });

        final limitedDocs = (dateFilter == 'past' || dateFilter == 'none') ? docs.take(30).toList() : docs;

        if (limitedDocs.isEmpty) {
          return _Empty(
            text: 'No ${dateFilter == "past" ? "past" : "active"} driver trips found.',
            buttonAction: dateFilter == 'future' ? () => _navigateToPostPage(context) : null,
            buttonText: 'Post a Trip',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: limitedDocs.length,
          itemBuilder: (_, i) {
            final m = limitedDocs[i].data();
            final origin = (m['origin'] ?? '') as String;
            final dest = (m['destination'] ?? '') as String;
            final seats = (m['seatsAvailable'] ?? m['seats'] ?? 0) as int;

            final dt = _bestTripDate(m);
            final dateStr = _fmtDate.format(dt);
            final timeStr = (m['time'] is String && (m['time'] as String).isNotEmpty) ? m['time'] as String : _fmtTime.format(dt);

            final price = _bestPrice(m);
            final currencySymbol = _currencySymbolForTrip(m);

            return _CardRow(
              leadingIcon: Icons.directions_car,
              title: '$origin → $dest',
              subtitle: '$dateStr  •  $timeStr  •  $seats seat(s) available',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildChatButton(limitedDocs[i].id),
                  _buildPassengerCountBadge(limitedDocs[i].id),
                  if (dateFilter == 'future') _buildBookingRequestsBadge(limitedDocs[i].id),
                  _buildRateRidersButton(context, limitedDocs[i].id),
                  const SizedBox(width: 8),
                  Text(
                    '$currencySymbol${price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: _kThemeGreen,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              tripData: m,
              tripId: limitedDocs[i].id,
              isDriverTrip: true,
              disableTap: disableEditing,
            );
          },
        );
      },
    );
  }
}

/// ------------------------------ RIDER BOOKING CARD (WITH DRIVER PROFILE button)
Widget _buildEnhancedBookingCard(
  Map<String, dynamic> booking,
  BuildContext context,
  String bookingId,
  String dateFilter,
) {
  final status = booking['status'] ?? 'pending';
  final statusColor = _getStatusColor(status);
  final statusText = _getStatusText(status);

  final tripId = booking['tripId'] ?? '';
  final driverId = (booking['driverId'] ?? '').toString();
  final driverName = (booking['driverName'] ?? 'Driver').toString();

  final bool isPast = dateFilter == 'past';
  final bool isCompleted = status == 'completed';
  final bool isRiderRated = (booking['isRiderRated'] as bool?) ?? false;
  final bool showRateButton = isPast && isCompleted && !isRiderRated;

  final seats = booking['seats'] ?? 1;
  final amountPaidNum = booking['amountPaid'] as num?;
  final amountPaidStr = amountPaidNum != null ? amountPaidNum.toStringAsFixed(2) : '0.00';

  final currencySymbol = _currencySymbolForBooking(booking);

  final bool showDriverProfile = (status == 'accepted' || status == 'completed') && driverId.isNotEmpty;

  return Card(
    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${booking['from']} → ${booking['to']}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${booking['dateString']} at ${booking['timeString']}'),
          Text('$seats seat(s) • $currencySymbol$amountPaidStr paid'),
          const SizedBox(height: 12),

          if (status == 'pending_driver')
            Column(
              children: [
                LinearProgressIndicator(
                  backgroundColor: Colors.grey[200],
                  color: _kThemeBlue,
                ),
                const SizedBox(height: 8),
                Text(
                  'Waiting for driver confirmation',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),

          if (status == 'accepted')
            Column(
              children: [
                LinearProgressIndicator(
                  value: 0.6,
                  backgroundColor: Colors.grey[200],
                  color: _kThemeGreen,
                ),
                const SizedBox(height: 8),
                Text(
                  'Booking confirmed!',
                  style: TextStyle(
                    color: _kThemeGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

          if (status == 'rejected')
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cancel, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Text('Booking declined by driver', style: TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ),
            ),

          if (status == 'cancelled_by_rider')
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.cancel_outlined, color: Colors.grey[700], size: 16),
                  const SizedBox(width: 8),
                  Text('You cancelled this booking', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                ],
              ),
            ),

          if (showDriverProfile) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: _UserBadgeButton(
                userId: driverId,
                fallbackName: driverName,
                dense: false,
                onPressed: () {
                  _showUserProfileDialog(
                    context,
                    userId: driverId,
                    titleName: driverName,
                  );
                },
              ),
            ),
          ],

          if (status == 'accepted' || showRateButton) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: showRateButton
                  ? ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          Routes.rateTrip,
                          arguments: {
                            'bookingId': bookingId,
                            'tripId': tripId,
                            'recipientId': driverId,
                            'recipientName': booking['driverName'] ?? 'Driver',
                            'role': 'rider',
                          },
                        );
                      },
                      icon: const Icon(Icons.star, size: 18),
                      label: const Text('Rate Driver'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber[700],
                        foregroundColor: Colors.white,
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: () {
                        final uid = FirebaseAuth.instance.currentUser?.uid;
                        if (uid == null) return;
                        final chatId = ChatService().getTripChatId(tripId, uid, driverId);
                        Navigator.pushNamed(
                          context,
                          Routes.chatScreen,
                          arguments: {
                            'chatId': chatId,
                            'recipientId': driverId,
                            'tripId': tripId,
                            'segmentFrom': booking['from'] ?? '',
                            'segmentTo': booking['to'] ?? '',
                          },
                        );
                      },
                      icon: const Icon(Icons.message, size: 18),
                      label: const Text('Chat with Driver'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kThemeBlue,
                        foregroundColor: Colors.white,
                      ),
                    ),
            ),
          ],
        ],
      ),
    ),
  );
}

Widget _buildEnhancedBookingCardWithCurrency(
  Map<String, dynamic> booking,
  BuildContext context,
  String bookingId,
  String dateFilter,
) {
  final tripId = booking['tripId'] as String? ?? '';

  if (booking['currencySymbol'] != null || booking['currencyCode'] != null) {
    return _buildEnhancedBookingCard(booking, context, bookingId, dateFilter);
  }

  if (tripId.isEmpty) {
    final updatedBooking = Map<String, dynamic>.from(booking)
      ..['currencySymbol'] = '₹'
      ..['currencyCode'] = 'INR';
    return _buildEnhancedBookingCard(updatedBooking, context, bookingId, dateFilter);
  }

  return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    future: FirebaseFirestore.instance.collection('trips').doc(tripId).get(),
    builder: (context, tripSnap) {
      if (tripSnap.connectionState == ConnectionState.waiting) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(color: _kThemeBlue)),
          ),
        );
      }

      final updatedBooking = Map<String, dynamic>.from(booking);

      if (tripSnap.hasData && tripSnap.data!.exists) {
        final tripData = tripSnap.data!.data() ?? {};
        updatedBooking['currencySymbol'] = tripData['currencySymbol'] ?? '₹';
        updatedBooking['currencyCode'] = tripData['currencyCode'] ?? 'INR';
      } else {
        updatedBooking['currencySymbol'] = '₹';
        updatedBooking['currencyCode'] = 'INR';
      }

      return _buildEnhancedBookingCard(updatedBooking, context, bookingId, dateFilter);
    },
  );
}

Color _getStatusColor(String status) {
  switch (status) {
    case 'pending_driver':
      return Colors.orange;
    case 'accepted':
      return _kThemeGreen;
    case 'rejected':
      return Colors.red;
    case 'cancelled':
      return Colors.grey;
    case 'cancelled_by_rider':
      return Colors.grey;
    case 'completed':
      return _kThemeBlue;
    default:
      return Colors.grey;
  }
}

String _getStatusText(String status) {
  switch (status) {
    case 'pending_driver':
      return 'Waiting';
    case 'accepted':
      return 'Confirmed';
    case 'rejected':
      return 'Declined';
    case 'cancelled':
      return 'Cancelled';
    case 'cancelled_by_rider':
      return 'Cancelled';
    case 'completed':
      return 'Completed';
    default:
      return status;
  }
}

class _ErrorPanel extends StatelessWidget {
  final String errorText;
  const _ErrorPanel({required this.errorText});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red[100]?.withOpacity(0.8),
          border: Border.all(color: Colors.redAccent),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Error Loading Trips',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
              errorText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestChatBadge extends StatelessWidget {
  final String requestId;
  final String myUid;

  const _RequestChatBadge({required this.requestId, required this.myUid});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('conversations')
        .where('associatedRequestIds', arrayContains: requestId)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final chats = snapshot.data!.docs;
        final driverCount = chats.length;
        if (driverCount == 0) return const SizedBox.shrink();

        final hasUnread = false;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: hasUnread ? Colors.orange : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasUnread ? Icons.chat_bubble : Icons.chat_bubble_outline,
                size: 14,
                color: hasUnread ? Colors.white : _kThemeBlue,
              ),
              const SizedBox(width: 4),
              Text(
                '$driverCount',
                style: TextStyle(
                  color: hasUnread ? Colors.white : _kThemeBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CardRow extends StatelessWidget {
  final IconData leadingIcon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Map<String, dynamic>? tripData;
  final String? tripId;
  final bool isDriverTrip;
  final bool disableTap;

  const _CardRow({
    super.key,
    required this.leadingIcon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.tripId,
    this.tripData,
    required this.isDriverTrip,
    this.disableTap = false,
  });

  @override
  Widget build(BuildContext context) {
    final VoidCallback? cardOnTap = disableTap
        ? null
        : () {
            if (tripData != null && tripId != null) {
              Navigator.of(context)
                  .push(
                MaterialPageRoute(
                  builder: (_) => _TripDetailsPage(
                    data: tripData!,
                    tripId: tripId!,
                    isDriverTrip: isDriverTrip,
                  ),
                ),
              )
                  .then((result) {
                if (result == 'trips' && Navigator.of(context).canPop()) {
                  // no-op
                }
              });
            }
          };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: disableTap ? Colors.grey[200] : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: cardOnTap,
        leading: CircleAvatar(
          backgroundColor: _kThemeBlue.withOpacity(.08),
          child: Icon(leadingIcon, color: _kThemeBlue),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: trailing,
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  final VoidCallback? buttonAction;
  final String buttonText;

  const _Empty({
    required this.text,
    this.buttonAction,
    this.buttonText = 'Post Trip',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            if (buttonAction != null) ...[
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: buttonAction,
                  icon: const Icon(Icons.add),
                  label: Text(buttonText),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kThemeBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ------------------------------ HELPERS
DateTime _asDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is String) {
    final p = DateTime.tryParse(v);
    if (p != null) return p;
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime _bestTripDate(Map<String, dynamic> m) {
  final d1 = m['date'];
  if (d1 != null) return _asDate(d1);
  final d2 = m['dateOut'];
  if (d2 != null) return _asDate(d2);
  final d3 = m['createdAt'];
  if (d3 != null) return _asDate(d3);
  return DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime _bestBookingDate(Map<String, dynamic> m) {
  final dateStr = m['dateString'];
  final timeStr = m['timeString'];

  if (dateStr is String && dateStr.isNotEmpty) {
    try {
      final combined = '$dateStr at ${timeStr ?? ''}'.trim();
      final format = DateFormat('EEE, MMM d, yyyy at h:mm a');
      return format.parse(combined);
    } catch (_) {
      try {
        return DateFormat('EEE, MMM d, yyyy').parse(dateStr);
      } catch (_) {}
    }
  }
  final d3 = m['createdAt'];
  if (d3 != null) return _asDate(d3);
  return DateTime.fromMillisecondsSinceEpoch(0);
}

double _bestPrice(Map<String, dynamic> m) {
  final v1 = m['pricePerSeat'];
  if (v1 is num) return v1.toDouble();
  final v2 = m['price'];
  if (v2 is num) return v2.toDouble();
  for (final k in ['price_cents', 'pricePerSeatCents', 'amount_cents']) {
    final v = m[k];
    if (v is num) return (v / 100).toDouble();
  }
  return 0.0;
}

String _symbolFromCurrencyCode(String code) {
  switch (code.toUpperCase()) {
    case 'INR':
      return '₹';
    case 'USD':
    case 'CAD':
    case 'AUD':
    case 'NZD':
    case 'SGD':
      return '\$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    default:
      return code.toUpperCase();
  }
}

String _currencySymbolForTrip(Map<String, dynamic> m) {
  final sym = m['currencySymbol'];
  if (sym is String && sym.isNotEmpty) return sym;

  final code = m['currencyCode'];
  if (code is String && code.isNotEmpty) {
    return _symbolFromCurrencyCode(code);
  }
  return '₹';
}

String _currencySymbolForBooking(Map<String, dynamic> booking) {
  final sym = booking['currencySymbol'];
  if (sym is String && sym.isNotEmpty) return sym;

  final code = booking['currencyCode'];
  if (code is String && code.isNotEmpty) {
    return _symbolFromCurrencyCode(code);
  }

  final tripSnap = booking['trip'] as Map<String, dynamic>?;
  if (tripSnap != null) {
    final tripSym = tripSnap['currencySymbol'];
    if (tripSym is String && tripSym.isNotEmpty) return tripSym;

    final tripCode = tripSnap['currencyCode'];
    if (tripCode is String && tripCode.isNotEmpty) {
      return _symbolFromCurrencyCode(tripCode);
    }
  }

  return '₹';
}

/// ------------------------------ DETAILS PAGE
class _TripDetailsPage extends StatelessWidget {
  final Map<String, dynamic> data;
  final String tripId;
  final bool isDriverTrip;

  const _TripDetailsPage({
    required this.data,
    required this.tripId,
    required this.isDriverTrip,
  });

  Future<void> _navigateToEditForm(BuildContext context) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => isDriverTrip ? OfferRidePage(tripIdToEdit: tripId) : NeedRidePage(requestIdToEdit: tripId),
      ),
    );
    if (result == 'trips' && context.mounted) {
      Navigator.of(context).pop('trips');
    }
  }

  Widget _buildPassengerList(BuildContext context) {
    if (!isDriverTrip) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .collection('booking_requests')
          .where('status', isEqualTo: 'accepted')
          .snapshots(),
      builder: (context, snapshot) {
        final acceptedBookings = snapshot.data?.docs ?? [];
        if (acceptedBookings.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No passengers booked yet',
              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          );
        }

        int totalPassengers = 0;
        for (final booking in acceptedBookings) {
          final seats = (booking.data()['seats'] as num?)?.toInt() ?? 1;
          totalPassengers += seats;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            const Text(
              'Passengers',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: _kThemeBlue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Total: $totalPassengers passenger(s)',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: _kThemeGreen,
              ),
            ),
            const SizedBox(height: 12),
            ...acceptedBookings.map((bookingDoc) {
              final booking = bookingDoc.data();
              final riderId = (booking['riderId'] ?? '').toString();
              final riderName = booking['riderName'] as String? ?? 'Rider';

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _UserBadgeButton(
                  userId: riderId,
                  fallbackName: riderName,
                  dense: false,
                  onPressed: () {
                    _showUserProfileDialog(context, userId: riderId, titleName: riderName);
                  },
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildChatButton(BuildContext context) {
    if (!isDriverTrip) return const SizedBox.shrink();

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .collection('booking_requests')
          .where('status', isEqualTo: 'accepted')
          .snapshots(),
      builder: (context, snapshot) {
        final acceptedBookings = snapshot.data?.docs ?? [];
        if (acceptedBookings.isEmpty) return const SizedBox.shrink();

        return SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () {
              _showAcceptedRidersDialog(context, acceptedBookings, currentUser.uid);
            },
            icon: const Icon(Icons.message),
            label: const Text('Chat with Riders'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kThemeBlue,
              side: const BorderSide(color: _kThemeBlue),
            ),
          ),
        );
      },
    );
  }

  void _showAcceptedRidersDialog(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> acceptedBookings,
    String currentUserId,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chat with Riders'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: acceptedBookings.length,
            itemBuilder: (context, index) {
              final booking = acceptedBookings[index].data();
              final riderId = (booking['riderId'] ?? '').toString();
              final riderName = booking['riderName'] as String? ?? 'Rider';

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: _UserBadgeButton(
                        userId: riderId,
                        fallbackName: riderName,
                        onPressed: () {
                          _showUserProfileDialog(context, userId: riderId, titleName: riderName);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      tooltip: 'Chat',
                      icon: const Icon(Icons.message, color: _kThemeBlue),
                      onPressed: () {
                        Navigator.pop(context);
                        final chatId = ChatService().getTripChatId(tripId, currentUserId, riderId);
                        Navigator.pushNamed(
                          context,
                          Routes.chatScreen,
                          arguments: {
                            'chatId': chatId,
                            'recipientId': riderId,
                            'tripId': tripId,
                            'segmentFrom': booking['from'] ?? '',
                            'segmentTo': booking['to'] ?? '',
                          },
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = isDriverTrip ? 'Driver Trip Details' : 'Ride Request Details';

    final origin = (data['origin'] ?? data['from'] ?? 'N/A') as String;
    final destination = (data['destination'] ?? data['to'] ?? 'N/A') as String;
    final seats = data['seatsAvailable'] ?? data['seatsRequired'] ?? data['seats'] ?? 'N/A';
    final status = (data['status'] ?? 'N/A') as String;

    final dt = _bestTripDate(data);
    final dateStr = _fmtDate.format(dt);
    final timeStr = (data['time'] is String && (data['time'] as String).isNotEmpty) ? data['time'] as String : _fmtTime.format(dt);

    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: _kThemeGreen,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(color: Colors.white)),
        backgroundColor: _kThemeBlue,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$origin → $destination',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
            ),
            const SizedBox(height: 16),
            _DetailRow('Status:', status.toUpperCase()),
            _DetailRow(isDriverTrip ? 'Seats Available:' : 'Seats Needed:', seats.toString()),
            _DetailRow('Date:', dateStr),
            _DetailRow('Time:', timeStr),
            if (isDriverTrip)
              _buildPassengerList(context)
            else
              _RequestChatsList(requestId: tripId, myUid: myUid),
            if (isDriverTrip) ...[
              const SizedBox(height: 24),
              _buildChatButton(context),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: () => _navigateToEditForm(context),
                style: FilledButton.styleFrom(backgroundColor: _kThemeBlue),
                child: const Text(
                  'Edit / Manage Post',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ------------------------------ REQUEST CHATS LIST
class _RequestChatsList extends StatelessWidget {
  final String requestId;
  final String myUid;
  const _RequestChatsList({required this.requestId, required this.myUid});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('conversations')
        .where('associatedRequestIds', arrayContains: requestId)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final chats = snapshot.data?.docs ?? [];

        if (chats.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No drivers have messaged you about this request yet.',
              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            const Text(
              'Driver Messages',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: _kThemeBlue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${chats.length} drivers have contacted you about this request.',
              style: const TextStyle(fontWeight: FontWeight.w600, color: _kThemeGreen),
            ),
            const SizedBox(height: 12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: chats.length,
              itemBuilder: (context, index) {
                final chatDoc = chats[index];
                final data = chatDoc.data();

                final participants = (data['participants'] as List<dynamic>?)?.cast<String>() ?? [];
                final driverId = participants.firstWhere((id) => id != myUid, orElse: () => '');

                if (driverId.isEmpty) {
                  return const SizedBox.shrink();
                }

                return _DriverChatTile(
                  chatId: chatDoc.id,
                  driverId: driverId,
                  requestId: requestId,
                  origin: (context.findAncestorWidgetOfExactType<_TripDetailsPage>()?.data['origin'] ?? '') as String,
                  destination:
                      (context.findAncestorWidgetOfExactType<_TripDetailsPage>()?.data['destination'] ?? '') as String,
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _DriverChatTile extends StatelessWidget {
  final String chatId;
  final String driverId;
  final String requestId;
  final String origin;
  final String destination;

  const _DriverChatTile({
    required this.chatId,
    required this.driverId,
    required this.requestId,
    required this.origin,
    required this.destination,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(driverId).get(),
      builder: (context, userSnap) {
        String driverName = 'Driver';
        if (userSnap.hasData && userSnap.data!.exists) {
          final data = userSnap.data!.data() ?? {};
          final firstName = (data['firstName'] ?? '').toString().trim();
          final lastName = (data['lastName'] ?? '').toString().trim();
          driverName = [firstName, lastName].where((s) => s.isNotEmpty).join(' ');
          if (driverName.isEmpty) driverName = 'Driver';
        }

        return ListTile(
          leading: const CircleAvatar(
            backgroundColor: _kThemeBlue,
            child: Icon(Icons.person, color: Colors.white, size: 20),
          ),
          title: Text(driverName),
          subtitle: const Text('View chat'),
          trailing: const Icon(Icons.message, color: _kThemeBlue),
          contentPadding: EdgeInsets.zero,
          onTap: () {
            Navigator.pushNamed(
              context,
              Routes.chatScreen,
              arguments: {
                'chatId': chatId,
                'recipientId': driverId,
                'requestId': requestId,
                'segmentFrom': origin,
                'segmentTo': destination,
              },
            );
          },
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
