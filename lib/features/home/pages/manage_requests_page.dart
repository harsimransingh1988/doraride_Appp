import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../services/booking_update_service.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class ManageRequestsPage extends StatelessWidget {
  const ManageRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Please sign in.')));
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manage Requests'),
          backgroundColor: _kThemeBlue,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Pending'),
              Tab(text: 'Accepted'),
            ],
          ),
        ),
        body: Container(
          color: Colors.black,
          child: TabBarView(
            children: [
              _RequestsTab(
                stream: FirebaseFirestore.instance
                    .collectionGroup('booking_requests')
                    .where('driverId', isEqualTo: uid)
                    .where('status', whereIn: ['pending_driver']) // Only actual pending
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                pending: true,
              ),
              _RequestsTab(
                stream: FirebaseFirestore.instance
                    .collectionGroup('booking_requests')
                    .where('driverId', isEqualTo: uid)
                    .where('status', isEqualTo: 'accepted')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                pending: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestsTab extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final bool pending;

  const _RequestsTab({required this.stream, required this.pending});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return const Center(child: Text('Error', style: TextStyle(color: Colors.white)));
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return Center(
            child: Text(
              pending ? 'No pending requests' : 'No accepted requests',
              style: const TextStyle(color: Colors.white70),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i];
            final data = d.data();

            final bookingId = d.id;
            final tripId = d.reference.parent.parent!.id; // ✅ from path
            final from = (data['from'] ?? '').toString();
            final to = (data['to'] ?? '').toString();
            final date = (data['dateString'] ?? '').toString();
            final time = (data['timeString'] ?? '').toString();
            final riderName = (data['riderName'] ?? '').toString();
            final driverId = (data['driverId'] ?? '').toString();
            final riderId = (data['riderId'] ?? '').toString();

            return Card(
              color: const Color(0xFF0F0F12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$from ➜ $to', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('$date · $time', style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 8),
                    Text('Rider: $riderName', style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 12),
                    if (pending)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                await BookingUpdateService.updateBookingStatusBatch(
                                  tripId: tripId,
                                  bookingId: bookingId,
                                  status: 'rejected',
                                  driverId: driverId,
                                  riderId: riderId,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Declined')));
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                              ),
                              child: const Text('Decline'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                await BookingUpdateService.updateBookingStatusBatch(
                                  tripId: tripId,
                                  bookingId: bookingId,
                                  status: 'accepted',
                                  driverId: driverId,
                                  riderId: riderId,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Accepted')));
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kThemeGreen,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Accept'),
                            ),
                          ),
                        ],
                      )
                    else
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _kThemeGreen.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _kThemeGreen.withOpacity(0.5)),
                          ),
                          child: const Text('Accepted', style: TextStyle(color: Colors.white)),
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