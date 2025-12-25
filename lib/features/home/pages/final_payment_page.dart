// lib/features/home/pages/final_payment_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../app_router.dart';
import '../../../services/booking_update_service.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class FinalPaymentPage extends StatefulWidget {
  final String tripId;
  final String from;
  final String to;
  final String dateString;
  final String timeString;
  final double price;
  final int availableSeats;
  final String driverName;
  final String driverId;

  final int initialSeats;
  final bool initialPaymentFull; // kept for compatibility, but overridden
  final bool premiumSeatSelected;
  final double premiumExtra;
  final int extraLuggageCount;
  final double extraLuggagePrice;
  final bool premiumSeatAlreadyTaken;

  /// NEW: currency code (e.g. 'CAD', 'USD', 'INR').
  final String currencyCode;

  const FinalPaymentPage({
    super.key,
    required this.tripId,
    required this.from,
    required this.to,
    required this.dateString,
    required this.timeString,
    required this.price,
    required this.availableSeats,
    required this.driverName,
    required this.driverId,
    this.initialSeats = 1,
    this.initialPaymentFull = false,
    this.premiumSeatSelected = false,
    this.premiumExtra = 0.0,
    this.extraLuggageCount = 0,
    this.extraLuggagePrice = 0.0,
    this.premiumSeatAlreadyTaken = false,
    this.currencyCode = 'INR',
  });

  @override
  State<FinalPaymentPage> createState() => _FinalPaymentPageState();
}

/// 3 payment modes:
/// - reservation  = pay deposit now
/// - full         = pay everything online now
/// - cash         = pay full in cash to driver
enum _PaymentMode { reservation, full, cash }

class _FinalPaymentPageState extends State<FinalPaymentPage> {
  int _seats = 1;
  bool _submitting = false;
  bool _premiumSeatSelected = false;
  int _extraLuggageCount = 0;
  bool _premiumAlreadyBooked = false;
  String? _lastBookingId;

  _PaymentMode _mode = _PaymentMode.reservation;

  // --- Currency helpers ---
  String get _cur => widget.currencyCode.toUpperCase();
  String _fmtMoney(double v) => '$_cur ${v.toStringAsFixed(2)}';

  @override
  void initState() {
    super.initState();
    _seats = widget.initialSeats.clamp(1, widget.availableSeats);

    // ✅ DEFAULT: Cash first & auto-selected
    _mode = _PaymentMode.cash;

    _extraLuggageCount = widget.extraLuggageCount;
    _premiumAlreadyBooked = widget.premiumSeatAlreadyTaken;
    _premiumSeatSelected =
        _premiumAlreadyBooked ? false : widget.premiumSeatSelected;
  }

  double get _baseTotal => widget.price * _seats;
  double get _premiumTotal => _premiumSeatSelected ? widget.premiumExtra : 0.0;
  double get _luggageTotal => widget.extraLuggagePrice * _extraLuggageCount;
  double get _fullTotal => _baseTotal + _premiumTotal + _luggageTotal;

  /// Reservation fee (deposit)
  double get _reservationFee {
    final tenPercent = _fullTotal * 0.10;
    if (_cur == 'INR') {
      const double minInr = 50.0;
      return tenPercent < minInr ? minInr : tenPercent;
    }
    return tenPercent;
  }

  double get _pricePaidNow {
    switch (_mode) {
      case _PaymentMode.reservation:
        return _reservationFee;
      case _PaymentMode.full:
        return _fullTotal;
      case _PaymentMode.cash:
        return 0.0;
    }
  }

  double get _balanceDue => _fullTotal - _pricePaidNow;

  bool get _isReservation => _mode == _PaymentMode.reservation;
  bool get _isFullOnline => _mode == _PaymentMode.full;
  bool get _isCash => _mode == _PaymentMode.cash;

  // ---------- Booking creation (online payment) ----------

  Future<void> _createBookingAfterStripe(
      Map<String, dynamic> paymentResult) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to book a ride.')),
      );
      return;
    }
    if (_seats < 1) return;

    setState(() => _submitting = true);
    try {
      final bookingRef = FirebaseFirestore.instance
          .collection('trips')
          .doc(widget.tripId)
          .collection('booking_requests')
          .doc();

      _lastBookingId = bookingRef.id;

      // Stripe IDs/amounts
      final String paymentIntentId =
          (paymentResult['txnId'] ?? '').toString(); // PaymentIntent ID

      final num paidAmount =
          (paymentResult['paidAmount'] is num)
              ? paymentResult['paidAmount'] as num
              : _pricePaidNow;

      final String paidCurrency =
          (paymentResult['currency'] ?? widget.currencyCode).toString();

      final bool isFullPayment = _isFullOnline;

      final bookingData = {
        'bookingId': bookingRef.id,
        'tripId': widget.tripId,
        'riderId': user.uid,
        'riderName': user.displayName ?? 'Rider',
        'riderEmail': user.email,
        'from': widget.from,
        'to': widget.to,
        'dateString': widget.dateString,
        'timeString': widget.timeString,
        'seats': _seats,
        'pricePerSeat': widget.price,
        'baseTotal': _baseTotal,
        'premiumSeatSelected': _premiumSeatSelected,
        'premiumExtra': _premiumTotal,
        'extraLuggageCount': _extraLuggageCount,
        'extraLuggageTotal': _luggageTotal,
        'fullTotal': _fullTotal,
        'amountPaidNow': _pricePaidNow,
        'amountPaidNowCents': (paidAmount * 100).round(),
        'balanceDue': _balanceDue,
        'isFullPayment': isFullPayment,
        'status': 'pending_driver',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'driverId': widget.driverId,
        'driverName': widget.driverName,

        // Stripe payment details
        'paymentProvider': 'stripe',
        'paymentStatus': isFullPayment ? 'paid_full' : 'paid_deposit',
        'reservationFee': _reservationFee,
        'paymentIntentId': paymentIntentId,
        'currency': paidCurrency,
        'refundStripeDone': false,
        'paymentResult': {
          'status': paymentResult['status'] ?? 'unknown',
          'clientSecret': paymentResult['clientSecret'],
          'amount': paymentResult['amount'],
          'currency': paidCurrency,
          'txnId': paymentIntentId,
          'paidAmount': paidAmount,
        },
      };

      await bookingRef.set(bookingData);

      // Mirror under user
      try {
        final userBookingRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('my_bookings')
            .doc(bookingRef.id);

        await userBookingRef.set({
          'bookingId': bookingRef.id,
          'tripId': widget.tripId,
          'status': 'pending_driver',
          'createdAt': FieldValue.serverTimestamp(),
          'type': 'as_rider',
          'from': widget.from,
          'to': widget.to,
          'dateString': widget.dateString,
          'timeString': widget.timeString,
          'driverName': widget.driverName,
          'driverId': widget.driverId,
          'riderId': user.uid,
          'amountPaid': _pricePaidNow,
          'premiumSeatSelected': _premiumSeatSelected,
          'extraLuggageCount': _extraLuggageCount,
          'reservationFee': _reservationFee,
          'seats': _seats,
          'paymentProvider': 'stripe',
          'currency': paidCurrency,
        });
      } catch (_) {}

      await BookingUpdateService.sendNewBookingNotification(
        tripId: widget.tripId,
        bookingId: bookingRef.id,
        driverId: widget.driverId,
        riderName: user.displayName ?? 'A rider',
        from: widget.from,
        to: widget.to,
      );

      if (!mounted) return;
      await _showBookingSuccessDialog(context, paidOnline: true);
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Could not place booking: $e';
        if (e.toString().contains('permission') ||
            e.toString().contains('PERMISSION_DENIED')) {
          errorMessage =
              'Booking failed: Permission denied. Please make sure you are signed in and try again.';
        } else if (e.toString().contains('not-found')) {
          errorMessage =
              'Booking failed: Trip not found or may have been deleted.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---------- Booking creation (cash, no Stripe) ----------

  Future<void> _createBookingCash() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to book a ride.')),
      );
      return;
    }
    if (_seats < 1) return;

    setState(() => _submitting = true);

    try {
      final bookingRef = FirebaseFirestore.instance
          .collection('trips')
          .doc(widget.tripId)
          .collection('booking_requests')
          .doc();

      _lastBookingId = bookingRef.id;

      final bookingData = {
        'bookingId': bookingRef.id,
        'tripId': widget.tripId,
        'riderId': user.uid,
        'riderName': user.displayName ?? 'Rider',
        'riderEmail': user.email,
        'from': widget.from,
        'to': widget.to,
        'dateString': widget.dateString,
        'timeString': widget.timeString,
        'seats': _seats,
        'pricePerSeat': widget.price,
        'baseTotal': _baseTotal,
        'premiumSeatSelected': _premiumSeatSelected,
        'premiumExtra': _premiumTotal,
        'extraLuggageCount': _extraLuggageCount,
        'extraLuggageTotal': _luggageTotal,
        'fullTotal': _fullTotal,
        'amountPaidNow': 0.0,
        'amountPaidNowCents': 0,
        'balanceDue': _fullTotal,
        'isFullPayment': false,
        'status': 'pending_driver',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'driverId': widget.driverId,
        'driverName': widget.driverName,

        // CASH payment details
        'paymentProvider': 'cash',
        'paymentStatus': 'unpaid',
        'reservationFee': 0.0,
        'paymentIntentId': null,
        'currency': widget.currencyCode,
        'refundStripeDone': false,
      };

      await bookingRef.set(bookingData);

      // mirror under user
      try {
        final userBookingRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('my_bookings')
            .doc(bookingRef.id);

        await userBookingRef.set({
          'bookingId': bookingRef.id,
          'tripId': widget.tripId,
          'status': 'pending_driver',
          'createdAt': FieldValue.serverTimestamp(),
          'type': 'as_rider',
          'from': widget.from,
          'to': widget.to,
          'dateString': widget.dateString,
          'timeString': widget.timeString,
          'driverName': widget.driverName,
          'driverId': widget.driverId,
          'riderId': user.uid,
          'amountPaid': 0.0,
          'premiumSeatSelected': _premiumSeatSelected,
          'extraLuggageCount': _extraLuggageCount,
          'reservationFee': 0.0,
          'seats': _seats,
          'paymentProvider': 'cash',
          'currency': widget.currencyCode,
        });
      } catch (_) {}

      await BookingUpdateService.sendNewBookingNotification(
        tripId: widget.tripId,
        bookingId: bookingRef.id,
        driverId: widget.driverId,
        riderName: user.displayName ?? 'A rider',
        from: widget.from,
        to: widget.to,
      );

      if (!mounted) return;
      await _showBookingSuccessDialog(context, paidOnline: false);
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Could not place booking: $e';
        if (e.toString().contains('permission') ||
            e.toString().contains('PERMISSION_DENIED')) {
          errorMessage =
              'Booking failed: Permission denied. Please make sure you are signed in and try again.';
        } else if (e.toString().contains('not-found')) {
          errorMessage =
              'Booking failed: Trip not found or may have been deleted.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---------- Payment + dialogs ----------

  Future<void> _startStripeAndBook() async {
    final result = await Navigator.of(context).pushNamed(
      Routes.paymentGateway,
      arguments: {
        'amount': _pricePaidNow,
        'currency': widget.currencyCode,
        'tripTitle': '${widget.from} → ${widget.to}',
        'subtitle': '${widget.dateString} at ${widget.timeString}',
      },
    ) as Map<String, dynamic>?;

    if (!mounted) return;

    if (result == null) {
      await _showPaymentErrorDialog(
        'Payment was cancelled. Your booking request was not sent.',
      );
      return;
    }

    final status = (result['status'] ?? 'error').toString();

    if (status != 'success') {
      final msg = (result['errorMessage'] ??
              result['message'] ??
              'Payment was not successful. Please check your card details and try again.')
          .toString();
      await _showPaymentErrorDialog(msg);
      return;
    }

    await _createBookingAfterStripe(result);
  }

  Future<void> _showPaymentErrorDialog(String message) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.error_outline, color: Colors.red, size: 24),
              SizedBox(width: 8),
              Text(
                'Payment Failed',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                Text(
                  message,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No money has been taken. You can try again.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Try Again',
                style:
                    TextStyle(color: _kThemeBlue, fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).maybePop();
              },
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showBookingSuccessDialog(BuildContext context,
      {required bool paidOnline}) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        final titleText =
            paidOnline ? 'Payment Successful!' : 'Request Sent!';
        final mainText = paidOnline
            ? 'Your payment was processed successfully and your booking request has been sent to the driver.'
            : 'Your booking request has been sent to the driver.';
        final secondaryText = paidOnline
            ? 'You will receive a notification once the driver responds.'
            : 'You chose to pay the remaining amount in cash directly to the driver at pickup. You will receive a notification once the driver responds.';

        return AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.check_circle, color: _kThemeGreen, size: 24),
              SizedBox(width: 8),
              Text(
                '',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  titleText,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 12),
                Text(
                  mainText,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                Text(
                  secondaryText,
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text(
                'OK',
                style:
                    TextStyle(color: _kThemeBlue, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _navigateToHome(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _navigateToHome(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context)
        .pushReplacementNamed(Routes.home, arguments: {'tab': 'trips'});
  }

  // ---------- UI helpers ----------

  Widget _buildPriceRow(String label, String description, String amount,
      {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
                      fontSize: isTotal ? 16 : 14,
                      color: isTotal ? _kThemeBlue : Colors.black87,
                    )),
                if (description.isNotEmpty)
                  Text(description,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(amount,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: isTotal ? FontWeight.w900 : FontWeight.w600,
                  fontSize: isTotal ? 18 : 14,
                  color: isTotal ? _kThemeGreen : Colors.black87,
                )),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceBreakdown() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Price Breakdown',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: _kThemeBlue)),
          const SizedBox(height: 12),
          _buildPriceRow(
            'Base Price',
            '${_fmtMoney(widget.price)} × $_seats seat(s)',
            _fmtMoney(_baseTotal),
          ),
          if (_premiumSeatSelected)
            _buildPriceRow(
              'Premium Seat',
              '+${_fmtMoney(widget.premiumExtra)}',
              '+${_fmtMoney(_premiumTotal)}',
            ),
          if (_extraLuggageCount > 0)
            _buildPriceRow(
              'Extra Luggage',
              '$_extraLuggageCount × ${_fmtMoney(widget.extraLuggagePrice)}',
              '+${_fmtMoney(_luggageTotal)}',
            ),
          const Divider(height: 16),
          _buildPriceRow(
            'Total Amount',
            '',
            _fmtMoney(_fullTotal),
            isTotal: true,
          ),
        ],
      ),
    );
  }

  void _onPrimaryPressed() {
    if (_submitting) return;
    if (_isCash) {
      _createBookingCash();
    } else {
      _startStripeAndBook();
    }
  }

  String _ctaLabel() {
    if (_isCash) {
      return 'Send request (Pay cash ${_fmtMoney(_fullTotal)})';
    }
    return 'Send request & Pay ${_fmtMoney(_pricePaidNow)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_submitting) {
      return Scaffold(
        backgroundColor: _kThemeGreen,
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 20),
            Text('Processing your booking...',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            SizedBox(height: 10),
            Text('Please wait', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    final bool balanceIsZero = _balanceDue <= 0.01;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment'),
        backgroundColor: _kThemeBlue,
      ),
      backgroundColor: _kThemeGreen,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              children: [
                // Summary header
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${widget.from} → ${widget.to}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: _kThemeBlue)),
                        const SizedBox(height: 4),
                        Text('${widget.dateString} at ${widget.timeString}',
                            style: TextStyle(
                                color: Colors.black.withOpacity(.65),
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('Driver: ${widget.driverName}',
                            style: TextStyle(
                                color: Colors.black.withOpacity(.65),
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                _buildPriceBreakdown(),
                const SizedBox(height: 16),

                // Seats + payment options
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Seats',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: _kThemeBlue)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          IconButton(
                            onPressed: _seats > 1
                                ? () => setState(() => _seats--)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text('$_seats',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 18)),
                          IconButton(
                            onPressed: (_seats < widget.availableSeats)
                                ? () => setState(() => _seats++)
                                : null,
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _fmtMoney(_fullTotal),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: _kThemeBlue,
                                ),
                              ),
                              Text(
                                'Base: ${_fmtMoney(_baseTotal)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '(${_fmtMoney(widget.price)} per seat • ${widget.availableSeats} available)',
                        style: TextStyle(
                          color: Colors.black.withOpacity(.6),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),

                      const Text('Choose Payment Option',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: _kThemeBlue)),
                      const SizedBox(height: 8),

                      // 🔹 1) CASH FIRST (default selected)
                      Card(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        color: _isCash
                            ? _kThemeBlue.withOpacity(0.1)
                            : Colors.white,
                        child: RadioListTile<_PaymentMode>(
                          title: const Text('Pay Cash to Driver',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _kThemeBlue)),
                          subtitle: Text(
                            'No online payment. You will pay ${_fmtMoney(_fullTotal)} in cash directly to the driver when you meet.',
                          ),
                          value: _PaymentMode.cash,
                          groupValue: _mode,
                          onChanged: (val) =>
                              setState(() => _mode = val!),
                          activeColor: _kThemeBlue,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // 2) Reservation
                      Card(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        color: _isReservation
                            ? _kThemeBlue.withOpacity(0.1)
                            : Colors.white,
                        child: RadioListTile<_PaymentMode>(
                          title: const Text('Pay Reservation Fee Only',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _kThemeBlue)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pay ${_fmtMoney(_reservationFee)} now. (10% of total amount, min may apply)',
                              ),
                              Text(
                                balanceIsZero
                                    ? 'Balance: ${_fmtMoney(0)}'
                                    : 'Balance of ${_fmtMoney(_balanceDue)} due to the driver.',
                                style: TextStyle(
                                  color: balanceIsZero
                                      ? _kThemeBlue
                                      : Colors.red.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          value: _PaymentMode.reservation,
                          groupValue: _mode,
                          onChanged: (val) =>
                              setState(() => _mode = val!),
                          activeColor: _kThemeBlue,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // 3) Full payment online
                      Card(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        color: _isFullOnline
                            ? _kThemeBlue.withOpacity(0.1)
                            : Colors.white,
                        child: RadioListTile<_PaymentMode>(
                          title: const Text('Pay Full Amount Now',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _kThemeBlue)),
                          subtitle: Text(
                            'Pay ${_fmtMoney(_fullTotal)} now. No remaining balance.',
                          ),
                          value: _PaymentMode.full,
                          groupValue: _mode,
                          onChanged: (val) =>
                              setState(() => _mode = val!),
                          activeColor: _kThemeBlue,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // CTA
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _onPrimaryPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kThemeBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 3),
                        )
                      : Text(_ctaLabel()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
