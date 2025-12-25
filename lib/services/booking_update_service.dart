// lib/services/booking_update_service.dart
//
// Central helper for all booking-related notifications.
// Uses NotificationService to actually send FCM messages
// and also writes a copy into users/{uid}/notifications where needed.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:doraride_appp/services/notification_service.dart';
import 'package:flutter/material.dart';

class BookingUpdateService {
  // ---------------------------------------------------------------------------
  // 1) NEW BOOKING → notify DRIVER
  // Called from final_payment_page.dart after a rider sends a request
  // ---------------------------------------------------------------------------
  static Future<void> sendNewBookingNotification({
    required String tripId,
    required String bookingId,
    required String driverId,
    required String riderName,
    required String from,
    required String to,
  }) async {
    const title = 'New Booking Request!';
    final body = '$riderName requested seats for your trip from $from to $to.';

    try {
      await NotificationService.sendBookingNotification(
        recipientId: driverId,
        title: title,
        body: body,
        data: {
          'type': 'new_request',
          'tripId': tripId,
          'bookingId': bookingId,
        },
      );
    } catch (e) {
      debugPrint('MOCK WARNING: Failed to send new booking notification: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 2) DRIVER ACCEPTS → notify RIDER (simple confirmation)
  // Used where you only need a generic “booking accepted” message
  // ---------------------------------------------------------------------------
  static Future<void> sendBookingConfirmationNotification({
    required String riderId,
    required String riderName,
    required String tripId,
  }) async {
    const title = 'Booking Confirmed! ✅';
    const body = 'Your trip request has been accepted by the driver.';

    try {
      await NotificationService.sendBookingNotification(
        recipientId: riderId,
        title: title,
        body: body,
        data: {
          'type': 'booking_accepted',
          'tripId': tripId,
        },
      );
    } catch (e) {
      debugPrint('MOCK WARNING: Failed to send booking confirmation notification: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 3) DRIVER REJECTS → notify RIDER (simple rejection)
  // ---------------------------------------------------------------------------
  static Future<void> sendBookingRejectionNotification({
    required String riderId,
    required String riderName,
    required String tripId,
  }) async {
    const title = 'Booking Declined 😔';
    const body = 'Your trip request was declined by the driver.';

    try {
      await NotificationService.sendBookingNotification(
        recipientId: riderId,
        title: title,
        body: body,
        data: {
          'type': 'booking_rejected',
          'tripId': tripId,
        },
      );
    } catch (e) {
      debugPrint('MOCK WARNING: Failed to send booking rejection notification: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 4) RIDER CANCELS → notify DRIVER
  // ---------------------------------------------------------------------------
  static Future<void> sendBookingCancellationNotification({
    required String driverId,
    required String riderName,
    required String tripId,
  }) async {
    const title = 'Booking Cancelled!';
    final body = '$riderName has cancelled their booking for your trip.';

    try {
      await NotificationService.sendBookingNotification(
        recipientId: driverId,
        title: title,
        body: body,
        data: {
          'type': 'booking_cancelled',
          'tripId': tripId,
        },
      );
    } catch (e) {
      debugPrint('MOCK WARNING: Failed to send cancellation notification: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 5) GENERIC STATUS UPDATE → notify RIDER + store in notifications collection
  //
  // This is the merged version of the snippet you pasted earlier.
  // Use this from driver_requests_page.dart when status changes
  // (accepted / rejected / cancelled / etc).
  // ---------------------------------------------------------------------------
  static Future<void> sendBookingStatusNotification({
    required String riderId,
    required String bookingId,
    required String status,     // e.g. 'accepted', 'rejected', 'cancelled_by_rider'
    required String driverName,
    required String from,
    required String to,
  }) async {
    try {
      final isAccepted = status == 'accepted';
      final isRejected = status == 'rejected';
      final prettyStatus =
          isAccepted ? 'accepted' : (isRejected ? 'declined' : status);

      final title = isAccepted
          ? 'Booking Accepted ✅'
          : isRejected
              ? 'Booking Declined 😔'
              : 'Booking Update';

      final body =
          '$driverName has $prettyStatus your booking from $from to $to.';

      // 1) Push FCM via your NotificationService
      await NotificationService.sendBookingNotification(
        recipientId: riderId,
        title: title,
        body: body,
        data: {
          'type': 'booking_status',
          'bookingId': bookingId,
          'status': status,
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        },
      );

      // 2) Store a copy under users/{riderId}/notifications
      await FirebaseFirestore.instance
          .collection('users')
          .doc(riderId)
          .collection('notifications')
          .add({
        'title': title,
        'body': body,
        'type': 'booking_status',
        'bookingId': bookingId,
        'status': status,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error sending booking status notification: $e');
    }
  }
}
