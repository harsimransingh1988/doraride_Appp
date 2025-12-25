// lib/services/booking_notification_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BookingNotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Stream<QuerySnapshot<Map<String, dynamic>>> getUserBookings() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('my_bookings')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Future<void> sendBookingNotification(
      String bookingId, String driverId, String message) async {
    await _firestore.collection('notifications').add({
      'userId': driverId,
      'title': 'New Booking Request',
      'message': message,
      'type': 'booking_request',
      'bookingId': bookingId,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getBookingRequestsForDriver(String driverId) {
    return _firestore
        .collectionGroup('booking_requests')
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'pending_driver')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Future<void> updateBookingStatus(String tripId, String bookingId, String status) async {
    await _firestore
        .collection('rides')
        .doc(tripId)
        .collection('booking_requests')
        .doc(bookingId)
        .update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Also update in user's my_bookings collection
    final bookingDoc = await _firestore
        .collection('rides')
        .doc(tripId)
        .collection('booking_requests')
        .doc(bookingId)
        .get();

    if (bookingDoc.exists) {
      final riderId = bookingDoc.data()!['riderId'];
      await _firestore
          .collection('users')
          .doc(riderId)
          .collection('my_bookings')
          .doc(bookingId)
          .update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }
}