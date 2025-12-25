// lib/features/home/pages/driver_requests_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doraride_appp/app_router.dart';
import 'package:doraride_appp/services/chat_service.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

final _fmtDate = DateFormat('EEE, MMM d, yyyy');
final _fmtTime = DateFormat('h:mm a');

// --- NEW HELPER: Gets all points in a trip's itinerary ---
List<String> _getTripPoints(Map<String, dynamic> tripData) {
  return [
    (tripData['origin'] ?? '').toString().toLowerCase().trim(),
    ...((tripData['stops'] as List<dynamic>?)?.map((s) => s is Map
            ? (s['location'] ?? '')
                .toString()
                .toLowerCase()
                .trim()
            : s.toString().toLowerCase().trim()) ??
        <String>[]),
    (tripData['destination'] ?? '').toString().toLowerCase().trim(),
  ];
}

// --- NEW HELPER: Core logic to calculate real-time availability ---
int _calculateSegmentAvailability({
  required Map<String, dynamic> tripData,
  required List<Map<String, dynamic>> allBookings,
  required String searchFrom,
  required String searchTo,
}) {
  final int totalCapacity = (tripData['seatsTotal'] ?? 0) as int;
  if (totalCapacity == 0) return 0;

  final searchFromLower = searchFrom.toLowerCase().trim();
  final searchToLower = searchTo.toLowerCase().trim();

  // Get the full itinerary of the trip
  final tripPoints = _getTripPoints(tripData);

  // Find the start and end index of the *searched segment* within the trip
  final int searchStartIndex = tripPoints.indexOf(searchFromLower);
  final int searchEndIndex = tripPoints.indexOf(searchToLower);

  if (searchStartIndex == -1 ||
      searchEndIndex == -1 ||
      searchEndIndex <= searchStartIndex) {
    return 0; // Not a valid segment for this trip
  }

  // Get all accepted bookings
  final bookings = allBookings;

  int maxOccupiedOnSegment = 0;

  // We must check the occupancy at *each step* of the searched segment
  for (int i = searchStartIndex; i < searchEndIndex; i++) {
    int occupiedOnThisStep = 0;

    // Check every booking to see if it overlaps this *step*
    for (final booking in bookings) {
      final bookingFrom =
          (booking['from'] ?? '').toString().toLowerCase().trim();
      final bookingTo = (booking['to'] ?? '').toString().toLowerCase().trim();
      final bookingSeats = (booking['seats'] ?? 1) as int;

      final bookingStartIndex = tripPoints.indexOf(bookingFrom);
      final bookingEndIndex = tripPoints.indexOf(bookingTo);

      if (bookingStartIndex == -1 || bookingEndIndex == -1) continue;

      // --- Overlap Check ---
      final bool overlaps =
          (bookingStartIndex <= i) && (bookingEndIndex > i);

      if (overlaps) {
        occupiedOnThisStep += bookingSeats;
      }
    }

    // We care about the *most crowded* step in our searched segment
    if (occupiedOnThisStep > maxOccupiedOnSegment) {
      maxOccupiedOnSegment = occupiedOnThisStep;
    }
  }

  // The available seats is the total capacity minus the max occupancy
  return totalCapacity - maxOccupiedOnSegment;
}

class DriverRequestsPage extends StatefulWidget {
  const DriverRequestsPage({super.key});

  @override
  State<DriverRequestsPage> createState() => _DriverRequestsPageState();
}

class _DriverRequestsPageState extends State<DriverRequestsPage>
    with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  String? _uid;
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _ensureSignedIn();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _ensureSignedIn() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
    setState(() => _uid = _auth.currentUser!.uid);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _tabStream(String status) {
    if (_uid == null) return const Stream.empty();

    print('🚗 Driver Requests Query: status=$status, driverId=$_uid');

    // For pending tab, exclude cancelled/rejected bookings
    if (status == 'pending_driver') {
      return FirebaseFirestore.instance
          .collectionGroup('booking_requests')
          .where('driverId', isEqualTo: _uid)
          .where('status',
              whereIn: ['pending_driver']) // Only show actual pending
          .orderBy('createdAt', descending: false)
          .snapshots();
    }

    // ✅ For accepted tab, show accepted + completed
    if (status == 'accepted') {
      return FirebaseFirestore.instance
          .collectionGroup('booking_requests')
          .where('driverId', isEqualTo: _uid)
          .where('status', whereIn: ['accepted', 'completed'])
          .orderBy('createdAt', descending: false)
          .snapshots();
    }

    // For rejected tab, include both rejected and rider-cancelled
    if (status == 'rejected') {
      return FirebaseFirestore.instance
          .collectionGroup('booking_requests')
          .where('driverId', isEqualTo: _uid)
          .where('status', whereIn: ['rejected', 'cancelled_by_rider'])
          .orderBy('createdAt', descending: false)
          .snapshots();
    }

    return const Stream.empty();
  }

  // 🔵 NEW: increment driver + trip "people driven" counters
  Future<void> _incrementPeopleDriven({
    required String driverId,
    required String tripId,
    required int seats,
  }) async {
    if (driverId.isEmpty || tripId.isEmpty || seats <= 0) return;

    final db = FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(driverId);
    final tripRef = db.collection('trips').doc(tripId);

    await db.runTransaction((txn) async {
      txn.set(
        userRef,
        {
          'peopleDriven': FieldValue.increment(seats),
        },
        SetOptions(merge: true),
      );
      txn.set(
        tripRef,
        {
          // keep same key as existing trips (your screenshot)
          'peopleDrivenSeats': FieldValue.increment(seats),
        },
        SetOptions(merge: true),
      );
    });
  }

  /// Accept/Reject handler with detailed error reporting
  ///
  /// ✅ NEW: Also updates driver stats:
  ///   - on accept: consecutiveRejects = 0
  ///   - on reject: consecutiveRejects++, at 5 → rating down 1 star, at 10 → isBlocked = true
  Future<void> _handleAction({
    required String tripId,
    required String bookingId,
    required String riderId,
    required String riderName,
    required int seats,
    required bool accept,
  }) async {
    if (_uid == null) {
      _showError('Please sign in first');
      return;
    }

    print('🔄 Starting action: ${accept ? 'ACCEPT' : 'REJECT'}');
    print('   Trip: $tripId, Booking: $bookingId, Rider: $riderId');
    print('   Current user UID: $_uid');

    try {
      final driverRef =
          FirebaseFirestore.instance.collection('users').doc(_uid);

      // Check if driver is already blocked
      final driverSnap = await driverRef.get();
      final driverData = driverSnap.data() ?? {};
      final isBlocked = (driverData['isBlocked'] as bool?) ?? false;

      if (isBlocked) {
        _showError('You are blocked from handling booking requests.');
        return;
      }

      // 1) First verify the booking exists and is pending
      final bookingRef = FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .collection('booking_requests')
          .doc(bookingId);

      final bookingSnapshot = await bookingRef.get();
      if (!bookingSnapshot.exists) {
        _showError('Booking request not found');
        return;
      }

      final bookingData = bookingSnapshot.data()!;
      final currentStatus = (bookingData['status'] ?? '').toString();
      print('📋 Current booking status: $currentStatus');

      // Check if booking is already cancelled by rider
      if (bookingData['status'] == 'cancelled_by_rider') {
        _showError('This booking was cancelled by the rider.');
        return;
      }

      if (currentStatus != 'pending_driver') {
        _showError(
            'Booking already processed (current status: $currentStatus)');
        return;
      }

      // 2) If accepting, check available seats
      if (accept) {
        final tripRef =
            FirebaseFirestore.instance.collection('trips').doc(tripId);
        final tripSnapshot = await tripRef.get();

        if (!tripSnapshot.exists) {
          _showError("Cannot accept: The trip no longer exists.");
          return;
        }

        final tripData = tripSnapshot.data()!;

        // --- START MODIFIED SEAT LOGIC ---
        // 1. Fetch all *other* accepted bookings
        final otherBookingsSnap = await FirebaseFirestore.instance
            .collection('trips')
            .doc(tripId)
            .collection('booking_requests')
            .where('status', isEqualTo: 'accepted')
            .get();
        final otherBookings =
            otherBookingsSnap.docs.map((d) => d.data()).toList();

        // 2. Calculate real-time availability for *this segment*
        final realTimeAvailableSeats = _calculateSegmentAvailability(
          tripData: tripData,
          allBookings: otherBookings,
          searchFrom:
              bookingData['from'], // 'from' of the request we're accepting
          searchTo: bookingData['to'], // 'to' of the request we're accepting
        );

        print(
            '💺 Real-time available on segment: $realTimeAvailableSeats, Requested: $seats');

        // 3. Check if there is space
        if (realTimeAvailableSeats < seats) {
          _showError(
              "Not enough seats available on this segment (Requested: $seats, Available: $realTimeAvailableSeats).");
          return;
        }
        // --- END MODIFIED SEAT LOGIC ---

        // --- REMOVED: Do NOT update seatsAvailable here. ---
        // A Cloud Function should handle this based on status change.
        // We only check if we *can* accept.
      }

      // 3) Update booking status
      final newStatus = accept ? 'accepted' : 'rejected';
      print('📝 Updating booking status to: $newStatus');
      await bookingRef.update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        'reviewedBy': _uid,
      });

      // 4) Update rider's my_bookings mirror - FIXED PERMISSIONS
      final riderMirrorRef = FirebaseFirestore.instance
          .collection('users')
          .doc(riderId)
          .collection('my_bookings')
          .doc(bookingId);

      print('👤 Updating rider mirror document');
      // Use update instead of set to avoid permission issues with creating new documents
      await riderMirrorRef.update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        'reviewedBy': _uid,
      }).catchError((error) async {
        // If update fails (document doesn't exist), create it with set
        print('⚠️ Mirror document not found, creating new one...');
        await riderMirrorRef.set({
          'status': newStatus,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'driverId': _uid,
          'tripId': tripId,
          'riderId': riderId,
          'riderName': riderName,
          'from': bookingData['from'],
          'to': bookingData['to'],
          'seats': seats,
          'dateString': bookingData['dateString'],
          'timeString': bookingData['timeString'],
          'amountPaidNow': bookingData['amountPaidNow'],
          'reviewedBy': _uid,
        });
      });

      // 5) NEW: update driver penalties / blocking
      if (accept) {
        // on accept → reset consecutiveRejects
        await driverRef.set(
          {
            'consecutiveRejects': 0,
          },
          SetOptions(merge: true),
        );
      } else {
        // on reject → increment & apply rules
        await FirebaseFirestore.instance
            .runTransaction((Transaction txn) async {
          final snap = await txn.get(driverRef);
          final data = snap.data() as Map<String, dynamic>? ?? {};

          int consecutiveRejects =
              (data['consecutiveRejects'] as int?) ?? 0;
          consecutiveRejects += 1;

          final ratingAvgRaw = data['ratingAvg'];
          final effectiveRaw = data['effectiveRating'];

          double ratingAvg = 5.0;
          if (ratingAvgRaw is num) ratingAvg = ratingAvgRaw.toDouble();

          double effectiveRating = ratingAvg;
          if (effectiveRaw is num) {
            effectiveRating = effectiveRaw.toDouble();
          }

          bool shouldBlock = false;

          // After 5 consecutive rejects → rating down by 1 star
          if (consecutiveRejects == 5) {
            effectiveRating =
                (effectiveRating - 1.0).clamp(1.0, 5.0); // 1–5 stars
          }

          // After 10 consecutive rejects → block driver
          if (consecutiveRejects >= 10) {
            shouldBlock = true;
          }

          final updateData = <String, dynamic>{
            'consecutiveRejects': consecutiveRejects,
            'effectiveRating': effectiveRating,
          };

          if (shouldBlock) {
            updateData['isBlocked'] = true;
          }

          txn.set(driverRef, updateData, SetOptions(merge: true));
        });
      }

      // 6) If accepted, create chat conversation
      if (accept) {
        try {
          final chatService = ChatService();
          final chatId = await chatService.ensureConversationTrip(
            me: _uid!,
            other: riderId,
            tripId: tripId,
          );
          print(
              '💬 Trip-specific chat created for trip: $tripId, chatId: $chatId');
        } catch (chatError) {
          print('⚠️ Chat creation failed (non-critical): $chatError');
        }
      }

      // 7) Update trips_live mirror
      // We only update fields that might change, but don't touch seats.
      final liveRef =
          FirebaseFirestore.instance.collection('trips_live').doc(tripId);
      await liveRef.set({
        'driverId': _uid,
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 8) 🔵 NEW: increment "people driven" counters on ACCEPT
      if (accept) {
        try {
          await _incrementPeopleDriven(
            driverId: _uid!,
            tripId: tripId,
            seats: seats,
          );
          print(
              '👥 Updated peopleDriven stats for driver $_uid on trip $tripId (seats=$seats)');
        } catch (e) {
          print('⚠️ Failed to update peopleDriven stats: $e');
        }
      }

      print('🎉 Action completed successfully');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(accept ? 'Booking Accepted 📩' : 'Booking Rejected 🛑'),
          backgroundColor: accept ? _kThemeGreen : Colors.red,
        ),
      );
    } catch (e, st) {
      print('❌ ACTION FAILED:');
      print('   Error type: ${e.runtimeType}');
      print('   Error: $e');
      print('   Stack: $st');

      String errorMessage = 'Failed to process request';
      if (e is FirebaseException) {
        errorMessage = 'Firestore error: ${e.message}';
      } else {
        errorMessage = 'Error: ${e.toString()}';
      }

      _showError(errorMessage);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    // 🔴 NEW: listen to driver doc for isBlocked / penalties
    final userStream = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Booking Requests'),
              backgroundColor: _kThemeBlue,
            ),
            body: Center(
              child: Text('Error loading driver info: ${snap.error}'),
            ),
          );
        }

        final data = snap.data?.data() ?? {};
        final isBlocked = (data['isBlocked'] as bool?) ?? false;
        final consecutiveRejects =
            (data['consecutiveRejects'] as int?) ?? 0;
        final effectiveRatingRaw = data['effectiveRating'];
        final effectiveRating = effectiveRatingRaw is num
            ? effectiveRatingRaw.toDouble()
            : null;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Booking Requests'),
            backgroundColor: _kThemeBlue,
            bottom: TabBar(
              controller: _tab,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(text: 'Pending'),
                Tab(text: 'Accepted'),
                Tab(text: 'Rejected'),
              ],
            ),
          ),
          backgroundColor: _kThemeGreen,
          body: Column(
            children: [
              if (isBlocked)
                _BlockedBanner(consecutiveRejects: consecutiveRejects)
              else if (consecutiveRejects >= 5)
                const _WarningBanner(),
              if (effectiveRating != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.star,
                          color: Colors.amber, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        effectiveRating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: _kThemeBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'system rating',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _RequestsList(
                      stream: _tabStream('pending_driver'),
                      mode: _CardMode.pending,
                      isBlocked: isBlocked,
                      onAccept: (args) => _handleAction(
                        tripId: args.tripId,
                        bookingId: args.bookingId,
                        riderId: args.riderId,
                        riderName: args.riderName,
                        seats: args.seats,
                        accept: true,
                      ),
                      onReject: (args) => _handleAction(
                        tripId: args.tripId,
                        bookingId: args.bookingId,
                        riderId: args.riderId,
                        riderName: args.riderName,
                        seats: args.seats,
                        accept: false,
                      ),
                    ),
                    _RequestsList(
                      stream: _tabStream('accepted'),
                      mode: _CardMode.accepted,
                      isBlocked: isBlocked,
                    ),
                    _RequestsList(
                      stream: _tabStream('rejected'),
                      mode: _CardMode.rejected,
                      isBlocked: isBlocked,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _CardMode { pending, accepted, rejected }

class _RequestArgs {
  final String tripId;
  final String bookingId;
  final String riderId;
  final String riderName;
  final int seats;
  final String from;
  final String to;
  _RequestArgs({
    required this.tripId,
    required this.bookingId,
    required this.riderId,
    required this.riderName,
    required this.seats,
    required this.from,
    required this.to,
  });
}

class _RequestsList extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final _CardMode mode;
  final void Function(_RequestArgs args)? onAccept;
  final void Function(_RequestArgs args)? onReject;
  final bool isBlocked; // 🔴 NEW

  const _RequestsList({
    required this.stream,
    required this.mode,
    this.onAccept,
    this.onReject,
    required this.isBlocked,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        print('📋 Driver Requests Stream State: ${snap.connectionState}');
        print('📋 Driver Requests Has Error: ${snap.hasError}');

        if (snap.hasError) {
          print('📋 Driver Requests Error: ${snap.error}');
          return _ErrorPanel(errorText: snap.error.toString());
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final qs = snap.data;
        if (qs == null) return const _EmptyTab(mode: _CardMode.pending);

        final docs = qs.docs;
        print('📋 Driver received ${docs.length} booking requests');

        for (final doc in docs) {
          final data = doc.data();
          print(
              '📋 Driver Booking: ${data['riderName']} | Status: ${data['status']} | From: ${data['from']} -> ${data['to']}');
        }

        if (docs.isEmpty) return _EmptyTab(mode: mode);

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            try {
              final doc = docs[i];
              final m = doc.data();

              if (m['riderId'] == null || m['riderId'].toString().isEmpty) {
                return const SizedBox.shrink();
              }

              final parent = doc.reference.parent.parent;
              final tripId = parent?.id ?? '';

              if (tripId.isEmpty) {
                return const SizedBox.shrink();
              }

              final args = _RequestArgs(
                tripId: tripId,
                bookingId: doc.id,
                riderId: m['riderId'].toString(),
                riderName: (m['riderName'] ?? 'Rider').toString(),
                seats: ((m['seats'] ?? 1) as num?)?.toInt() ?? 1,
                from: (m['from'] ?? '').toString(),
                to: (m['to'] ?? '').toString(),
              );

              final isPending = mode == _CardMode.pending;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const CircleAvatar(
                            backgroundColor: _kThemeGreen,
                            child: Icon(Icons.person, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Rider: ${args.riderName}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                const SizedBox(height: 4),
                                Text('${args.from} → ${args.to}',
                                    style: const TextStyle(
                                        color: Colors.black54)),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      _DetailRow('Seats Requested', '${args.seats}',
                          icon: Icons.event_seat),
                      _DetailRow('Route', '${args.from} → ${args.to}',
                          icon: Icons.route),

                      const Divider(height: 24),

                      if (isPending) ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.close),
                                label: const Text('Reject'),
                                onPressed: (onReject == null || isBlocked)
                                    ? null
                                    : () => onReject!(args),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.check),
                                label: const Text('Accept'),
                                onPressed: (onAccept == null || isBlocked)
                                    ? null
                                    : () => onAccept!(args),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kThemeGreen,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (isBlocked)
                          const Padding(
                            padding: EdgeInsets.only(top: 8.0),
                            child: Text(
                              'You are blocked from taking new actions.',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ] else ...[
                        Row(
                          children: [
                            Text(
                              // ✅ Proper status text including completed
                              m['status'] == 'cancelled_by_rider'
                                  ? 'Cancelled by Rider'
                                  : m['status'] == 'completed'
                                      ? 'Completed'
                                      : mode == _CardMode.accepted
                                          ? 'Accepted'
                                          : 'Rejected',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: m['status'] == 'cancelled_by_rider'
                                    ? Colors.orange
                                    : m['status'] == 'completed'
                                        ? _kThemeBlue
                                        : mode == _CardMode.accepted
                                            ? _kThemeGreen
                                            : Colors.red,
                              ),
                            ),
                            const Spacer(),
                            if (mode == _CardMode.accepted)
                              IconButton(
                                icon: const Icon(Icons.message_outlined,
                                    color: _kThemeBlue),
                                tooltip: 'Chat with Rider',
                                onPressed: () async {
                                  final currentUser =
                                      FirebaseAuth.instance.currentUser;
                                  if (currentUser == null) return;

                                  try {
                                    final chatService = ChatService();
                                    final chatId =
                                        chatService.getTripChatId(
                                      args.tripId,
                                      currentUser.uid,
                                      args.riderId,
                                    );

                                    await chatService.ensureConversationTrip(
                                      me: currentUser.uid,
                                      other: args.riderId,
                                      tripId: args.tripId,
                                      segmentFrom: args.from,
                                      segmentTo: args.to,
                                    );

                                    if (context.mounted) {
                                      Navigator.pushNamed(
                                        context,
                                        Routes.chatScreen,
                                        arguments: {
                                          'chatId': chatId,
                                          'recipientId': args.riderId,
                                          'segmentFrom': args.from,
                                          'segmentTo': args.to,
                                          'tripId': args.tripId,
                                        },
                                      );
                                    }
                                  } catch (e) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content:
                                            Text('Could not open chat'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                },
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            } catch (e) {
              print('❌ Error building booking card: $e');
              return const SizedBox.shrink();
            }
          },
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? color;

  const _DetailRow(this.label, this.value, {this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: color ?? _kThemeBlue),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: color ?? Colors.black,
                fontWeight:
                    color != null ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  final _CardMode mode;
  const _EmptyTab({required this.mode});

  String get _title {
    switch (mode) {
      case _CardMode.pending:
        return 'No Pending Requests';
      case _CardMode.accepted:
        return 'No Accepted Bookings';
      case _CardMode.rejected:
        return 'No Rejected Requests';
    }
  }

  String get _hint {
    switch (mode) {
      case _CardMode.pending:
        return 'New rider booking requests will appear here.';
      case _CardMode.accepted:
        return 'Accepted bookings will be shown here.';
      case _CardMode.rejected:
        return 'Rejected requests will be listed here.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              mode == _CardMode.pending
                  ? Icons.inbox_outlined
                  : mode == _CardMode.accepted
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined,
              size: 56,
              color: Colors.black26,
            ),
            const SizedBox(height: 12),
            Text(_title,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(_hint, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
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
          color: Colors.red.withOpacity(0.08),
          border: Border.all(color: Colors.redAccent),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(height: 8),
            const Text(
              'Couldn\'t load requests.',
              style: TextStyle(fontWeight: FontWeight.w600),
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

/// 🔴 NEW: banner when driver is blocked
class _BlockedBanner extends StatelessWidget {
  final int consecutiveRejects;
  const _BlockedBanner({required this.consecutiveRejects});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.red.withOpacity(0.9),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.block, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You are temporarily blocked because of too many rejected requests '
              '($consecutiveRejects rejections). Please contact support.',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ⚠️ NEW: warning banner after 5 rejects (rating penalty applied)
class _WarningBanner extends StatelessWidget {
  const _WarningBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.orange.withOpacity(0.9),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: const [
          Icon(Icons.warning_amber_rounded, color: Colors.white),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'You have rejected many requests. Your rating has been penalized. '
              'If you reject 10 requests in a row, your account will be blocked.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
