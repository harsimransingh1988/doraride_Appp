// lib/features/home/pages/booking_status_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:doraride_appp/app_router.dart';
import 'package:doraride_appp/services/booking_update_service.dart';
import 'package:doraride_appp/services/chat_service.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class BookingStatusPage extends StatefulWidget {
  final String bookingId;
  final String tripId;
  final String from;
  final String to;
  final String dateString;
  final String timeString;
  final String driverName;

  const BookingStatusPage({
    super.key,
    required this.bookingId,
    required this.tripId,
    required this.from,
    required this.to,
    required this.dateString,
    required this.timeString,
    required this.driverName,
  });

  @override
  State<BookingStatusPage> createState() => _BookingStatusPageState();
}

class _BookingStatusPageState extends State<BookingStatusPage> {
  bool _hasOpenedRating = false;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null || widget.bookingId.isEmpty || widget.tripId.isEmpty) {
      return const Scaffold(
        appBar: _StatusAppBar(title: 'Booking Status'),
        body: Center(
          child: Text(
            'Error: Booking or User ID missing.',
            style: TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    // Stream the rider's mirror booking document for real-time status updates
    final bookingStream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('my_bookings')
        .doc(widget.bookingId)
        .snapshots();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const _StatusAppBar(title: 'Booking Status'),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: bookingStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final data = snapshot.data?.data();
          if (data == null || !snapshot.data!.exists) {
            return const Center(child: Text('Booking not found.'));
          }

          final status = (data['status'] ?? 'unknown') as String;
          final amountPaid =
              (data['amountPaid'] as num? ?? 0.0).toDouble();
          final driverId = (data['driverId'] ?? 'N/A').toString();

          // 🔹 If trip for this booking is completed, auto-open rating once
          if (status == 'completed' &&
              !_hasOpenedRating &&
              driverId.isNotEmpty &&
              driverId != 'N/A') {
            _hasOpenedRating = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Navigator.of(context).pushNamed(
                Routes.rateTrip,
                arguments: {
                  'bookingId': widget.bookingId,
                  'tripId': widget.tripId,
                  'recipientId': driverId,
                  'recipientName': widget.driverName,
                  // current user is rider → rating the driver
                  'role': 'driver',
                },
              );
            });
          }

          return _StatusContent(
            status: status,
            from: widget.from,
            to: widget.to,
            dateString: widget.dateString,
            timeString: widget.timeString,
            driverName: widget.driverName,
            driverId: driverId,
            tripId: widget.tripId,
            bookingId: widget.bookingId,
            amountPaid: amountPaid,
          );
        },
      ),
    );
  }
}

class _StatusAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  const _StatusAppBar({required this.title});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      backgroundColor: _kThemeBlue,
      foregroundColor: Colors.white,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _StatusContent extends StatelessWidget {
  final String status;
  final String from;
  final String to;
  final String dateString;
  final String timeString;
  final String driverName;
  final String driverId;
  final String tripId;
  final String bookingId;
  final double amountPaid;

  const _StatusContent({
    required this.status,
    required this.from,
    required this.to,
    required this.dateString,
    required this.timeString,
    required this.driverName,
    required this.driverId,
    required this.tripId,
    required this.bookingId,
    required this.amountPaid,
  });

  _BookingState get _bookingState {
    switch (status) {
      case 'accepted':
        return _BookingState.confirmed;
      case 'rejected':
      case 'cancelled':
      case 'cancelled_by_driver':
      case 'cancelled_by_rider':
        return _BookingState.rejected;
      case 'completed':
        return _BookingState.completed;
      default:
        return _BookingState.pending;
    }
  }

  // --- MODIFIED: This function now checks the 1-hour rule ---
  Future<void> _cancelBooking(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Cancellation'),
        // --- MODIFIED: Updated text ---
        content: const Text(
          'You can cancel up to 1 hour before departure. A penalty fee may apply. Are you sure you want to cancel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep Booking'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Confirm Cancellation'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      // --- NEW: Fetch the trip to check departure time ---
      final tripRef =
          FirebaseFirestore.instance.collection('trips').doc(tripId);
      final tripDoc = await tripRef.get();

      if (!tripDoc.exists) {
        if (context.mounted) _showError(context, 'Error: Trip not found.');
        return;
      }

      final tripData = tripDoc.data()!;
      final dateTimestamp = tripData['date'] as Timestamp?;
      if (dateTimestamp == null) {
        if (context.mounted) {
          _showError(
              context, 'Error: Trip departure time is missing.');
        }
        return;
      }

      final departureTime = dateTimestamp.toDate();
      final cutoffTime =
          departureTime.subtract(const Duration(hours: 1));
      final now = DateTime.now();

      // --- NEW: Apply the 1-hour rule ---
      if (now.isAfter(cutoffTime)) {
        if (context.mounted) {
          _showError(context,
              'Sorry, you can only cancel up to 1 hour before departure.');
        }
        return;
      }

      // --- Proceed with cancellation (this logic is unchanged) ---

      // 1. Update status in the trip's booking_requests collection (driver sees this)
      await FirebaseFirestore.instance
          .collection('trips')
          .doc(tripId)
          .collection('booking_requests')
          .doc(bookingId)
          .update({
        'status': 'cancelled_by_rider',
        'updatedAt': FieldValue.serverTimestamp()
      });

      // 2. Update status in the rider's mirror document
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('my_bookings')
          .doc(bookingId)
          .update({
        'status': 'cancelled_by_rider',
        'updatedAt': FieldValue.serverTimestamp()
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Booking cancelled successfully.')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        _showError(context, 'Failed to cancel: $e');
      }
    }
  }

  // --- NEW: Error helper ---
  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _bookingState;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusHeader(state: state, driverName: driverName),
          const SizedBox(height: 24),

          _buildTimeline(state),
          const SizedBox(height: 32),

          _buildTripSummary(),
          const SizedBox(height: 16),

          _buildPaymentSummary(amountPaid),
          const SizedBox(height: 32),

          // --- ACTION BUTTONS ---

          // Show "Chat with Driver" for Pending AND Confirmed
          if (state == _BookingState.pending ||
              state == _BookingState.confirmed) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final uid =
                      FirebaseAuth.instance.currentUser?.uid;
                  if (uid == null) return;
                  final chatId = ChatService()
                      .getTripChatId(tripId, uid, driverId);
                  Navigator.of(context).pushNamed(
                    Routes.chatScreen,
                    arguments: {
                      'chatId': chatId,
                      'recipientId': driverId,
                      'tripId': tripId,
                      'segmentFrom': from,
                      'segmentTo': to,
                    },
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kThemeBlue,
                  side: const BorderSide(
                      color: _kThemeBlue, width: 2),
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.message_outlined),
                label: const Text('Chat with Driver'),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Show "Cancel" button for Pending AND Confirmed
          if (state == _BookingState.pending ||
              state == _BookingState.confirmed)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _cancelBooking(context),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(state == _BookingState.pending
                    ? 'Cancel Booking Request'
                    : 'Cancel Confirmed Booking'),
              ),
            ),

          // Show "Message Driver" for Rejected
          if (state == _BookingState.rejected) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  final uid =
                      FirebaseAuth.instance.currentUser?.uid;
                  if (uid == null) return;
                  final chatId = ChatService()
                      .getTripChatId(tripId, uid, driverId);
                  Navigator.of(context).pushNamed(
                    Routes.chatScreen,
                    arguments: {
                      'chatId': chatId,
                      'recipientId': driverId,
                      'tripId': tripId,
                      'segmentFrom': from,
                      'segmentTo': to,
                    },
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kThemeBlue,
                  side: const BorderSide(
                      color: _kThemeBlue, width: 2),
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Message Driver'),
              ),
            ),
          ],

          // 🔹 Show explicit "Rate your driver" button on completed state
          if (state == _BookingState.completed &&
              driverId.isNotEmpty &&
              driverId != 'N/A') ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pushNamed(
                    Routes.rateTrip,
                    arguments: {
                      'bookingId': bookingId,
                      'tripId': tripId,
                      'recipientId': driverId,
                      'recipientName': driverName,
                      'role': 'driver',
                    },
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: _kThemeBlue,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.star_rate_rounded),
                label: const Text('Rate your driver'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTripSummary() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Trip Details',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: _kThemeBlue,
              ),
            ),
            const Divider(),
            _DetailRow('Route', '$from → $to', icon: Icons.route),
            _DetailRow('Date', dateString,
                icon: Icons.calendar_today),
            _DetailRow('Time', timeString,
                icon: Icons.access_time),
            _DetailRow('Driver', driverName,
                icon: Icons.person_outline),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSummary(double amount) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payment Summary',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: _kThemeBlue,
              ),
            ),
            const Divider(),
            _DetailRow(
              'Amount Paid Now',
              '\$${amount.toStringAsFixed(2)}',
              icon: Icons.payments,
              color: _kThemeGreen,
            ),
            _DetailRow(
              'Payment Status',
              amount > 0 ? 'Paid' : 'Pending',
              icon: Icons.check_circle_outline,
              color: amount > 0 ? _kThemeGreen : Colors.grey,
            ),
            const SizedBox(height: 8),
            // --- MODIFIED: Updated text ---
            const Text(
              'If you cancel more than 1 hour before departure, your payment will be refunded (less a penalty fee) within 7 working days.',
              style: TextStyle(
                  fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline(_BookingState currentState) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          _TimelineStep(
            label: 'Request Sent',
            icon: Icons.send,
            isCurrent: currentState == _BookingState.pending,
            isCompleted:
                currentState.statusOrder >= _BookingState.pending.statusOrder,
            activeColor: _kThemeBlue,
          ),
          _TimelineStep(
            label: 'Driver Confirmation',
            icon: Icons.thumb_up,
            isCurrent:
                currentState == _BookingState.confirmed,
            isCompleted: currentState.statusOrder >=
                _BookingState.confirmed.statusOrder,
            activeColor: _kThemeGreen,
          ),
          _TimelineStep(
            label: 'Trip Day',
            icon: Icons.calendar_today,
            isCurrent: false,
            isCompleted: currentState.statusOrder >=
                _BookingState.completed.statusOrder,
            activeColor: _kThemeGreen,
          ),
          if (currentState == _BookingState.rejected)
            _TimelineStep(
              label: 'Request Rejected/Cancelled',
              icon: Icons.cancel,
              isCurrent: true,
              isCompleted: true,
              activeColor: Colors.red,
            ),
        ],
      ),
    );
  }
}

enum _BookingState {
  pending(0),
  confirmed(1),
  completed(2),
  rejected(-1);

  final int statusOrder;
  const _BookingState(this.statusOrder);
}

class _StatusHeader extends StatelessWidget {
  final _BookingState state;
  final String driverName;

  const _StatusHeader({required this.state, required this.driverName});

  Color get _color {
    switch (state) {
      case _BookingState.pending:
        return Colors.orange.shade700;
      case _BookingState.confirmed:
        return _kThemeGreen;
      case _BookingState.rejected:
        return Colors.red;
      case _BookingState.completed:
        return _kThemeBlue;
    }
  }

  String get _title {
    switch (state) {
      case _BookingState.pending:
        return 'Waiting for $driverName...';
      case _BookingState.confirmed:
        return 'Booking Confirmed!';
      case _BookingState.rejected:
        return 'Booking Rejected/Cancelled.';
      case _BookingState.completed:
        return 'Trip Completed';
    }
  }

  String get _subtitle {
    switch (state) {
      case _BookingState.pending:
        return 'The driver is reviewing your request. You can chat with the driver while you wait.';
      case _BookingState.confirmed:
        return 'Your seats are secured! You can now chat with $driverName.';
      case _BookingState.rejected:
        return 'Unfortunately, the driver did not accept this request or you cancelled it. You will be fully refunded as per our policy.';
      case _BookingState.completed:
        return 'Thank you for riding with us!';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.1),
        border: Border(
          left: BorderSide(color: _color, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _color,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            _subtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.black87),
          ),
        ],
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isCompleted;
  final bool isCurrent;
  final Color activeColor;

  const _TimelineStep({
    required this.label,
    required this.icon,
    required this.isCompleted,
    required this.isCurrent,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        isCompleted ? activeColor : Colors.grey.shade400;
    final fontWeight =
        isCompleted ? FontWeight.bold : FontWeight.normal;

    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted
                      ? color.withOpacity(0.2)
                      : Colors.transparent,
                  border:
                      Border.all(color: color, width: 2),
                ),
                child: Icon(icon,
                    size: 16, color: color),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: fontWeight,
                  ),
                ),
                if (isCurrent)
                  Text(
                    'Current Step',
                    style: TextStyle(
                      color: activeColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const _DetailRow(
    this.label,
    this.value, {
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18,
              color: color ?? _kThemeBlue),
          const SizedBox(width: 8),
          Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: color ?? Colors.black54,
                fontWeight:
                    color != null
                        ? FontWeight.w700
                        : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
