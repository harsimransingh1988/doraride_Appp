import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doraride_appp/services/trip_service.dart';
import 'package:doraride_appp/app_router.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

final _fmtDateLong = DateFormat('EEE, MMM d, yyyy');
final _fmtTime = DateFormat('h:mm a');

/// Allowed trip status values
const kTripStatuses = <String>{
  'scheduled',
  'en_route',
  'arrived',
  'completed',
  'canceled',
};

class DriverManageTripPage extends StatefulWidget {
  final String tripId;
  const DriverManageTripPage({super.key, required this.tripId});

  @override
  State<DriverManageTripPage> createState() => _DriverManageTripPageState();
}

class _DriverManageTripPageState extends State<DriverManageTripPage> {
  final _auth = FirebaseAuth.instance;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _ensureAuth();
  }

  Future<void> _ensureAuth() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
    setState(() => _uid = _auth.currentUser!.uid);
  }

  CollectionReference<Map<String, dynamic>> get _trips =>
      FirebaseFirestore.instance.collection('trips');
  CollectionReference<Map<String, dynamic>> get _tripsLive =>
      FirebaseFirestore.instance.collection('trips_live');

  Stream<DocumentSnapshot<Map<String, dynamic>>> _tripStream() {
    return _trips.doc(widget.tripId).snapshots();
  }

  bool _canGoTo(String current, String next) {
    switch (current) {
      case 'scheduled':
        return next == 'en_route' || next == 'canceled';
      case 'en_route':
        return next == 'arrived' || next == 'canceled';
      case 'arrived':
        return next == 'completed' || next == 'canceled';
      default:
        return false;
    }
  }

  /// Best-effort increment of users/{driverId}.peopleDriven
  /// based on accepted bookings for this trip.
  Future<void> _incrementPeopleDrivenForTrip(
      String tripId, String driverId) async {
    try {
      final bookingsSnap = await FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .collection('booking_requests')
          .where('status', isEqualTo: 'accepted')
          .get();

      int totalSeats = 0;
      for (final doc in bookingsSnap.docs) {
        final data = doc.data();
        final seatsRaw = data['seats'];
        if (seatsRaw is num) {
          totalSeats += seatsRaw.toInt();
        } else {
          totalSeats += 1;
        }
      }

      if (totalSeats <= 0) return;

      final userRef =
          FirebaseFirestore.instance.collection('users').doc(driverId);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(userRef);
        final currentRaw = snap.data()?['peopleDriven'] ?? 0;
        int current = 0;
        if (currentRaw is num) current = currentRaw.toInt();

        tx.set(
          userRef,
          {
            'peopleDriven': current + totalSeats,
          },
          SetOptions(merge: true),
        );
      });
    } catch (_) {
      // best-effort only; ignore errors so trip completion still works
    }
  }

  Future<void> _updateStatus(String nextStatus) async {
    if (_uid == null) return;

    final tripRef = _trips.doc(widget.tripId);
    final liveRef = _tripsLive.doc(widget.tripId);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(tripRef);
        if (!snap.exists) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            message: 'Trip not found.',
          );
        }
        final data = snap.data()!;
        final driverId = data['driverId'] as String?;
        if (driverId != _uid) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            message: 'Only the trip owner can update status.',
          );
        }
        final current = (data['status'] ?? 'scheduled').toString();
        if (!_canGoTo(current, nextStatus)) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            message: 'Invalid transition: $current → $nextStatus',
          );
        }

        final updates = <String, dynamic>{
          'status': nextStatus,
          'driverId': _uid, // helps rules for legacy docs
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (nextStatus == 'en_route') {
          updates['startedAt'] = FieldValue.serverTimestamp();
        }
        if (nextStatus == 'arrived') {
          updates['arrivedAt'] = FieldValue.serverTimestamp();
        }
        if (nextStatus == 'completed') {
          updates['completedAt'] = FieldValue.serverTimestamp();
        }

        tx.update(tripRef, updates);
      });

      // Live mirror (best-effort, outside tx)
      await liveRef.set(
        {
          'driverId': _uid,
          'status': nextStatus,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // When trip is completed:
      if (nextStatus == 'completed' && _uid != null) {
        // 1) update peopleDriven (best-effort)
        await _incrementPeopleDrivenForTrip(widget.tripId, _uid!);

        // 2) mark all accepted bookings as completed + flag for rating
        try {
          await TripService().completeTripAndMarkForReview(
            tripId: widget.tripId,
            driverId: _uid!,
          );
        } catch (_) {
          // don't block UI if this fails; rating is "nice to have"
        }

        // 3) immediately open the "Rate riders" screen for the driver
        if (mounted) {
          Navigator.of(context).pushNamed(
            Routes.rateRidersList,
            arguments: {'tripId': widget.tripId},
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Trip status: $nextStatus'),
          backgroundColor: _kThemeGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is FirebaseException && e.message != null
                ? e.message!
                : e.toString(),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildActionBar(String status) {
    final buttons = <Widget>[];

    void add(String label, String next) {
      buttons.add(
        FilledButton(
          onPressed: () => _updateStatus(next),
          style: FilledButton.styleFrom(
            backgroundColor: _kThemeGreen,
            foregroundColor: Colors.white,
          ),
          child: Text(label),
        ),
      );
      buttons.add(const SizedBox(width: 12));
    }

    switch (status) {
      case 'scheduled':
        add('Start Trip', 'en_route');
        add('Cancel', 'canceled');
        break;
      case 'en_route':
        add('Mark Arrived', 'arrived');
        add('Cancel', 'canceled');
        break;
      case 'arrived':
        add('Complete Trip', 'completed');
        add('Cancel', 'canceled');
        break;
      default:
        // completed/canceled → no actions
        break;
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: buttons.isEmpty ? [const SizedBox()] : buttons,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Trip'),
        backgroundColor: _kThemeBlue,
      ),
      backgroundColor: _kThemeGreen,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _tripStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData || !snap.data!.exists) {
            return const Center(
              child: Text(
                'Unable to load trip.',
                style: TextStyle(color: Colors.white),
              ),
            );
          }
          final m = snap.data!.data()!;
          final from = (m['origin'] ?? m['from'] ?? '—').toString();
          final to = (m['destination'] ?? m['to'] ?? '—').toString();

          final dt = (m['dateTime'] is Timestamp)
              ? (m['dateTime'] as Timestamp).toDate()
              : DateTime.tryParse('${m['date']} ${m['time']}') ??
                  DateTime.now();

          final status = (m['status'] ?? 'scheduled').toString();
          final seatsAvail = ((m['seatsAvailable'] ?? 0) as num).toInt();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$from → $to',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: _kThemeBlue,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_fmtDateLong.format(dt)} at ${_fmtTime.format(dt)}',
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Chip(
                              label: Text('Status: $status'),
                              backgroundColor: Colors.white,
                              shape: StadiumBorder(
                                side: BorderSide(
                                  color: _kThemeBlue.withOpacity(0.2),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Chip(
                              label: Text('Seats left: $seatsAvail'),
                              backgroundColor: Colors.white,
                              shape: StadiumBorder(
                                side: BorderSide(
                                  color: _kThemeBlue.withOpacity(0.2),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildActionBar(status),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Accepted riders list (reads subcollection)
                _AcceptedRidersList(tripId: widget.tripId),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AcceptedRidersList extends StatelessWidget {
  final String tripId;
  const _AcceptedRidersList({required this.tripId});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('trips')
        .doc(tripId)
        .collection('booking_requests')
        .where('status', isEqualTo: 'accepted')
        .orderBy('createdAt');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(12.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Card(
            child: ListTile(
              leading: Icon(Icons.people_outline),
              title: Text('No accepted riders yet'),
              subtitle:
                  Text('When you accept booking requests, riders appear here.'),
            ),
          );
        }
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ListTile(
                leading: Icon(Icons.people),
                title: Text('Accepted Riders'),
              ),
              const Divider(height: 1),
              ...docs.map((d) {
                final m = d.data();
                final name = (m['riderName'] ?? 'Rider').toString();
                final seats = ((m['seats'] ?? 1) as num).toInt();

                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(name),
                  subtitle: Text('Seats: $seats'),
                  trailing: IconButton(
                    icon: const Icon(Icons.message_outlined,
                        color: _kThemeBlue),
                    onPressed: () {
                      // Hook up to chat if needed
                    },
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
