import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:doraride_appp/app_router.dart';

const _kThemeBlue = Color(0xFF180D3B);

class RateRidersListPage extends StatelessWidget {
  final String tripId;

  const RateRidersListPage({super.key, required this.tripId});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Rate Your Riders'),
          backgroundColor: _kThemeBlue,
        ),
        body: const Center(
          child: Text('Please sign in to rate your riders.'),
        ),
      );
    }

    final driverId = user.uid;

    // All accepted OR already-completed bookings on this trip
    final stream = FirebaseFirestore.instance
        .collection('trips')
        .doc(tripId)
        .collection('booking_requests')
        .where('status', whereIn: ['accepted', 'completed'])
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate Your Riders'),
        backgroundColor: _kThemeBlue,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Text('There were no riders on this trip.'),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final bookingDoc = docs[index];
              final booking = bookingDoc.data();
              final bookingId = bookingDoc.id;

              final riderId = (booking['riderId'] ?? '') as String;
              final riderName = (booking['riderName'] ?? 'Rider') as String;

              if (riderId.isEmpty) {
                return const SizedBox.shrink();
              }

              // Canonical review doc: 1 review per (trip + driver + rider)
              final reviewDocId = '${tripId}_${driverId}_$riderId';

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('reviews')
                    .doc(reviewDocId)
                    .snapshots(),
                builder: (context, reviewSnap) {
                  bool hasReview = false;
                  int rating = 0;

                  if (reviewSnap.hasData &&
                      reviewSnap.data != null &&
                      reviewSnap.data!.exists) {
                    final data = reviewSnap.data!.data()!;
                    final r = data['rating'];
                    if (r is int) rating = r;
                    if (r is double) rating = r.round();
                    hasReview = true;
                  } else {
                    // fallback: old flag on booking, if present
                    final isDriverRated =
                        (booking['isDriverRated'] as bool?) ?? false;
                    hasReview = isDriverRated;
                  }

                  String subtitle;
                  if (hasReview && rating > 0) {
                    subtitle = 'Rated $rating★';
                  } else if (hasReview) {
                    subtitle = 'Rated';
                  } else {
                    subtitle = 'Pending review';
                  }

                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: _kThemeBlue,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    title: Text(riderName),
                    subtitle: Text(subtitle),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hasReview ? Colors.grey : Colors.amber,
                        foregroundColor: Colors.white,
                      ),
                      // Always allow editing; RateTripPage will pre-fill if review exists
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          Routes.rateTrip,
                          arguments: {
                            'bookingId': bookingId,
                            'tripId': tripId,
                            'recipientId': riderId,   // The rider
                            'recipientName': riderName,
                            'role': 'driver',          // I am the driver
                          },
                        );
                      },
                      child: Text(hasReview ? 'Edit' : 'Rate'),
                    ),
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
