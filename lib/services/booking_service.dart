// Add to lib/services/booking_update_service.dart
class BookingUpdateService {
  // ... existing code ...

  static Future<void> sendBookingStatusNotification({
    required String riderId,
    required String bookingId,
    required String status,
    required String driverName,
    required String from,
    required String to,
  }) async {
    try {
      // Get rider's FCM token from users collection
      final riderDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(riderId)
          .get();
      
      final fcmToken = riderDoc.data()?['fcmToken'] as String?;
      
      if (fcmToken == null) {
        print('No FCM token found for rider $riderId');
        return;
      }

      final statusText = status == 'accepted' ? 'accepted' : 'declined';
      
      // Send FCM notification
      await FirebaseMessaging.instance.sendMessage(
        to: fcmToken,
        notification: FirebaseNotification(
          title: 'Booking $statusText',
          body: '$driverName has $statusText your booking from $from to $to',
        ),
        data: {
          'type': 'booking_status',
          'bookingId': bookingId,
          'status': status,
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        },
      );

      // Also store notification in user's notifications collection
      await FirebaseFirestore.instance
          .collection('users')
          .doc(riderId)
          .collection('notifications')
          .add({
        'title': 'Booking $statusText',
        'body': '$driverName has $statusText your booking from $from to $to',
        'type': 'booking_status',
        'bookingId': bookingId,
        'status': status,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error sending booking status notification: $e');
    }
  }
}