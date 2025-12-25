// lib/features/payments/payment_gateway_page_mobile.dart
// Mobile (Android/iOS) payment page using flutter_stripe.
// Same feature set as web version:
//  - Uses the same backend endpoint: $_apiBase/createPaymentIntent
//  - Uses the same publishable key (_kStripePk)
//  - Returns the same Navigator.pop() payloads:
//      success: {status, txnId, paidAmount, currency, clientSecret}
//      error:   {status: 'error', errorMessage}
//      cancel:  {status: 'cancelled'}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_stripe/flutter_stripe.dart';

// Keep same colors and Stripe publishable key as web file
const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

// SAME publishable key as web – safe on client
const _kStripePk =
    'pk_live_51RmOQ602QRDPjVXD4KPxyI3jYNwgGcSfr9qK37P02yRrhAXPmy4L7EjeuUBK7LGIuh5rUPsdWzhQmOIvYEO277vl00pjaY5AB0';

// ---------- API base (prod vs emulator) ----------
const _cloudBase = 'https://us-central1-doraride-af3ec.cloudfunctions.net';
const _emuBase = 'http://127.0.0.1:5001/doraride-af3ec/us-central1';

// Force PROD even in debug so you don't need the emulator running locally.
const bool _forceProdInDebug = true;

String get _apiBase =>
    (kReleaseMode || _forceProdInDebug) ? _cloudBase : _emuBase;
// -----------------------------------------------

class PaymentGatewayPage extends StatefulWidget {
  const PaymentGatewayPage({
    super.key,
    required this.amount, // dollars
    required this.currency, // 'CAD'
    required this.tripTitle,
    required this.subtitle,
  });

  final double amount;
  final String currency;
  final String tripTitle;
  final String subtitle;

  static PaymentGatewayPage fromArgs(Map a) {
    return PaymentGatewayPage(
      amount: (a['amount'] is num) ? (a['amount'] as num).toDouble() : 0.0,
      currency: (a['currency'] ?? 'CAD').toString(),
      tripTitle: (a['tripTitle'] ?? '').toString(),
      subtitle: (a['subtitle'] ?? '').toString(),
    );
  }

  @override
  State<PaymentGatewayPage> createState() => _PaymentGatewayPageState();
}

class _PaymentGatewayPageState extends State<PaymentGatewayPage> {
  final _nameOnCard = TextEditingController();
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    // Initialize flutter_stripe for mobile.
    // If you already set this in main.dart, setting the same key again is safe.
    Stripe.publishableKey = _kStripePk;
  }

  @override
  void dispose() {
    _nameOnCard.dispose();
    super.dispose();
  }

  String _fmtAmount() =>
      '${widget.currency} ${widget.amount.toStringAsFixed(2)}';

  Future<void> _payNow() async {
    if (_processing) return;

    final name = _nameOnCard.text.trim();
    if (name.isEmpty) {
      _toast('Please enter the name on card.');
      return;
    }

    // Ensure card field is complete
    if (_cardComplete == false) {
      _toast('Please enter complete card details.');
      return;
    }

    setState(() => _processing = true);

    try {
      // 1) Create PaymentIntent on backend (same endpoint as web)
      final amountCents = (widget.amount * 100).round();
      final resp = await http.post(
        Uri.parse('$_apiBase/createPaymentIntent'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': amountCents,
          'currency': widget.currency.toLowerCase(),
          'metadata': {'trip': widget.tripTitle},
        }),
      );

      if (resp.statusCode != 200) {
        String msg = '';
        try {
          final d = jsonDecode(resp.body);
          msg = (d['error'] ?? d['message'] ?? '').toString();
        } catch (_) {
          msg = resp.body;
        }
        throw Exception(
          'createPaymentIntent failed: ${msg.isEmpty ? 'HTTP ${resp.statusCode}' : msg}',
        );
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final clientSecret = (data['clientSecret'] ?? '').toString();
      if (clientSecret.isEmpty) {
        throw Exception('createPaymentIntent returned no clientSecret');
      }

      // 2) Confirm PaymentIntent with flutter_stripe (card from CardField)
      final billingDetails = BillingDetails(
        name: name,
      );

      final paymentIntent = await Stripe.instance.confirmPayment(
        paymentIntentClientSecret: clientSecret,
        data: PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(
            billingDetails: billingDetails,
          ),
        ),
      );

      final status = paymentIntent.status;
      final txnId = paymentIntent.id;

      if (status != PaymentIntentsStatus.Succeeded) {
        throw Exception(
          'Payment not completed (status: $status)',
        );
      }

      if (!mounted) return;
      Navigator.pop(context, {
        'status': 'success',
        'txnId': txnId,
        'paidAmount': widget.amount,
        'currency': widget.currency,
        'clientSecret': clientSecret,
      });
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context, {
        'status': 'error',
        'errorMessage': e.toString(),
      });
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _cancel() {
    if (_processing) return;
    Navigator.pop(context, {'status': 'cancelled'});
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  bool _cardComplete = false;

  Widget _tf(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      decoration: InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kThemeGreen),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kThemeGreen, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _cardTile() {
    return const ListTile(
      leading: Icon(Icons.credit_card, color: Colors.white),
      title: Text(
        'Credit / Debit Card',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
      subtitle:
          Text('Visa, Mastercard', style: TextStyle(color: Colors.white70)),
      trailing: Icon(Icons.check_circle, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: const Text('Checkout'), backgroundColor: _kThemeBlue),
      backgroundColor: _kThemeGreen,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              children: [
                // Replaced Card widget with Container to avoid Stripe Card conflict
                Container(
                  color: Colors.white,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.3),
                        spreadRadius: 1,
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: _kThemeGreen.withOpacity(.15),
                          child: const Icon(Icons.lock, color: _kThemeGreen),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.tripTitle,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _kThemeBlue,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.subtitle,
                                style: TextStyle(
                                  color: Colors.black.withOpacity(.6),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _fmtAmount(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: _kThemeBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                _cardTile(),
                const SizedBox(height: 8),

                // Name on card (REQUIRED)
                _tf(_nameOnCard, 'Name on card'),
                const SizedBox(height: 12),

                // Card field (number + expiry + CVC) via flutter_stripe
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: _kThemeGreen),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: CardField(
                    onCardChanged: (details) {
                      setState(() {
                        _cardComplete = details?.complete ?? false; 
                      });
                    },
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _processing ? null : _cancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _processing ? null : _payNow,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kThemeBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: _processing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            )
                          : Text('Pay ${_fmtAmount()}'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}