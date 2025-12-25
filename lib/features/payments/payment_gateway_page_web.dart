// lib/features/payments/payment_gateway_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:js/js_util.dart' as jsu;

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

// ====== LIVE publishable key (safe in frontend) ======
const _kStripePk =
    'pk_live_51RmOQ602QRDPjVXD4KPxyI3jYNwgGcSfr9qK37P02yRrhAXPmy4L7EjeuUBK7LGIuh5rUPsdWzhQmOIvYEO277vl00pjaY5AB0';

// DOM IDs for the Stripe Elements hosts (no wallet button)
const _idNumber = 'stripe-card-number';
const _idExpiry = 'stripe-card-expiry';
const _idCvc = 'stripe-card-cvc';

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

  // Ensure we only register each platform view once per app lifetime.
  static final Set<String> _registeredViews = {};

  @override
  void initState() {
    super.initState();

    // 1) Register platform views (Flutter will inject <div id="...">)
    _registerStripeHost(_idNumber);
    _registerStripeHost(_idExpiry);
    _registerStripeHost(_idCvc);

    // 2) After the first frame, wait for hosts and mount Stripe Elements
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareStripe());
  }

  // Creates <div id="{id}"> via platform view. Must use dart:ui_web registry.
  void _registerStripeHost(String id) {
    if (_registeredViews.contains(id)) return;
    ui_web.platformViewRegistry.registerViewFactory(id, (int _) {
      final el = html.DivElement()
        ..id = id
        ..style.setProperty('width', '100%')
        ..style.setProperty('height', '100%');
      return el;
    });
    _registeredViews.add(id);
  }

  Future<void> _prepareStripe() async {
    try {
      // Wait until all host DIVs exist in DOM
      await _waitForHosts();

      // Access window.dorarideStripe from index.html
      final stripeShim = jsu.getProperty(html.window, 'dorarideStripe');
      if (stripeShim == null) {
        _toast('Stripe init error: shim not found on window.dorarideStripe');
        return;
      }

      // Init Stripe with wallets disabled
      try {
        jsu.callMethod(stripeShim, 'init', [_kStripePk, true]);
      } catch (e) {
        _toast('Stripe init() threw: $e');
      }

      // Mount Elements (guard each call)
      try {
        jsu.callMethod(stripeShim, 'mountNumber', [_idNumber]);
      } catch (_) {}
      try {
        jsu.callMethod(stripeShim, 'mountExpiry', [_idExpiry]);
      } catch (_) {}
      try {
        jsu.callMethod(stripeShim, 'mountCvc', [_idCvc]);
      } catch (_) {}

      // ❌ No wallet Payment Request button here anymore
    } catch (e) {
      _toast('Stripe init error: $e');
    }
  }

  Future<void> _waitForHosts() async {
    const ids = [_idNumber, _idExpiry, _idCvc];
    for (int i = 0; i < 40; i++) {
      final ok = ids.every((id) => html.document.getElementById(id) != null);
      if (ok) return;
      await Future.delayed(const Duration(milliseconds: 75));
    }
    throw StateError('Stripe hosts did not render in time.');
  }

  String _fmtAmount() =>
      '${widget.currency} ${widget.amount.toStringAsFixed(2)}';

  Future<void> _payNow() async {
    if (_processing) return;

    // 🔴 NAME ON CARD REQUIRED
    final name = _nameOnCard.text.trim();
    if (name.isEmpty) {
      _toast('Please enter the name on card.');
      return;
    }

    setState(() => _processing = true);

    try {
      // 1) Create PaymentIntent on backend
      final amountCents = (widget.amount * 100).round();
      final resp = await http.post(
        Uri.parse('$_apiBase/createPaymentIntent'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': amountCents,
          // 🔑 send currency code as lower-case to match Stripe + backend
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

      // 2) Confirm with Stripe.js (uses mounted Elements)
      final stripeShim = jsu.getProperty(html.window, 'dorarideStripe');

      final result = await jsu.promiseToFuture(
        jsu.callMethod(stripeShim, 'confirmCard', [clientSecret, name]),
      );

      final ok = jsu.getProperty(result, 'ok') == true;
      final status = (jsu.getProperty(result, 'status') ?? '').toString();
      if (!ok || status != 'succeeded') {
        final err =
            (jsu.getProperty(result, 'error') ?? 'Payment not completed')
                .toString();
        throw Exception(err);
      }

      final txnId = (jsu.getProperty(result, 'id') ?? '').toString();

      if (!mounted) return;
      Navigator.pop(context, {
        'status': 'success',
        'txnId': txnId,
        'paidAmount': widget.amount,
        'currency': widget.currency,
        'clientSecret': clientSecret,
      });
    } catch (e) {
      // 🔴 RETURN ERROR TO CALLER (FinalPaymentPage) SO IT CAN SHOW POPUP
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

  Widget _stripeBox(String label, String viewType) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _kThemeGreen),
            borderRadius: BorderRadius.circular(8),
          ),
          height: 48,
          child: HtmlElementView(viewType: viewType),
        ),
      ],
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
                Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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

                // Name on card (NOW REQUIRED)
                _tf(_nameOnCard, 'Name on card'),
                const SizedBox(height: 12),

                // Card number
                _stripeBox('Card number', _idNumber),
                const SizedBox(height: 12),

                // Expiry + CVC
                Row(
                  children: [
                    Expanded(child: _stripeBox('MM/YY', _idExpiry)),
                    const SizedBox(width: 12),
                    Expanded(child: _stripeBox('CVV', _idCvc)),
                  ],
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
