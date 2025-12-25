import 'package:cloud_functions/cloud_functions.dart';

// ... inside your payment flow:
final callable = FirebaseFunctions.instance.httpsCallable('createPaymentIntent');
final resp = await callable.call({
  'amount':  _fullTotal, // e.g. 23.50 (DOLLARS)
  'currency': 'CAD',
  'description': 'DoraRide: ${widget.from} → ${widget.to}',
  'tripId': widget.tripId,
  'riderId': FirebaseAuth.instance.currentUser?.uid,
});
final clientSecret = (resp.data as Map)['clientSecret'] as String;
