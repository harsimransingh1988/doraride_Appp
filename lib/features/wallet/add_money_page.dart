// lib/features/wallet/add_money_page.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app_router.dart';
import '../../common/repos/wallet_repository.dart';

class AddMoneyPage extends StatefulWidget {
  const AddMoneyPage({super.key});

  @override
  State<AddMoneyPage> createState() => _AddMoneyPageState();
}

class _AddMoneyPageState extends State<AddMoneyPage> {
  static const kGreen = Color(0xFF279C56);

  final _amount = TextEditingController(text: '25.00');
  final repo = WalletRepository();
  bool loading = false;

  // 🌍 Default currency; will auto-change using profile/locale
  String _currencyCode = 'INR';
  String _currencySymbol = '₹';
  String _currencyName = 'Indian rupee';

  @override
  void initState() {
    super.initState();
    _initCurrencyFromProfileOrLocale();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Try to read user.countryCode (or country) from Firestore first,
  /// then fall back to platform locale (works web + mobile).
  Future<void> _initCurrencyFromProfileOrLocale() async {
    try {
      String? countryCode;

      // 1) Try current Firebase user profile (users/{uid})
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        final data = snap.data();
        if (data != null) {
          final cc = (data['countryCode'] ?? data['country']) as String?;
          if (cc != null && cc.trim().isNotEmpty) {
            final trimmed = cc.trim();
            if (trimmed.length == 2) {
              countryCode = trimmed.toUpperCase();
            } else {
              final lower = trimmed.toLowerCase();
              if (lower.contains('india')) countryCode = 'IN';
              if (lower.contains('canada')) countryCode = 'CA';
              if (lower.contains('united states') || lower == 'usa') {
                countryCode = 'US';
              }
            }
          }
        }
      }

      // 2) Fall back to device / browser locale if still unknown
      countryCode ??= WidgetsBinding.instance
          .platformDispatcher
          .locale
          .countryCode;

      if (countryCode == null || countryCode.isEmpty) return;

      final info = await _lookupCurrencyForCountryCode(countryCode);
      if (!mounted || info == null) return;

      setState(() {
        _currencyCode = info.code;
        _currencySymbol = info.symbol;
        _currencyName = info.name;
      });
    } catch (e) {
      debugPrint('AddMoney currency init failed: $e');
    }
  }

  /// REST Countries: https://restcountries.com/v3.1/alpha/{code}?fields=currencies,name
  Future<_CurrencyInfo?> _lookupCurrencyForCountryCode(String countryCode) async {
    try {
      final uri = Uri.https(
        'restcountries.com',
        '/v3.1/alpha/$countryCode',
        {'fields': 'currencies,name'},
      );

      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        debugPrint('REST Countries error (${resp.statusCode}): ${resp.body}');
        return null;
      }

      final decoded = jsonDecode(resp.body);
      Map<String, dynamic>? firstCountry;

      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        firstCountry = (decoded.first as Map).cast<String, dynamic>();
      } else if (decoded is Map<String, dynamic>) {
        firstCountry = decoded;
      }

      if (firstCountry == null) return null;

      final currenciesRaw = firstCountry['currencies'];
      if (currenciesRaw is! Map) return null;

      final currencies = currenciesRaw.cast<String, dynamic>();
      if (currencies.isEmpty) return null;

      final entry = currencies.entries.first;
      final code = entry.key;
      final data = (entry.value as Map).cast<String, dynamic>();

      final name = (data['name'] as String?) ?? code;
      final symbol = (data['symbol'] as String?) ?? code;

      return _CurrencyInfo(code: code, symbol: symbol, name: name);
    } catch (e) {
      debugPrint('Currency lookup failed (add money): $e');
      return null;
    }
  }

  Future<void> _add() async {
    final val = double.tryParse(_amount.text.replaceAll(',', ''));
    if (val == null || val <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enter a valid amount in $_currencyCode')),
      );
      return;
    }

    setState(() => loading = true);

    try {
      // 1) Open Stripe payment screen
      final result = await Navigator.of(context).pushNamed(
        Routes.paymentGateway,
        arguments: {
          'amount': val, // in main currency units (e.g. 25.00)
          'currency': _currencyCode,
          'tripTitle': 'Wallet top-up',
          'subtitle':
              'Add funds to your DoraRide wallet ($_currencyCode)',
        },
      ) as Map<String, dynamic>?;

      if (!mounted) return;

      // User closed / cancelled
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment cancelled, no money added.'),
          ),
        );
        return;
      }

      final status = (result['status'] ?? 'error').toString();
      if (status != 'success') {
        final msg = (result['errorMessage'] ??
                result['message'] ??
                'Payment was not successful. Please try again.')
            .toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        return;
      }

      // 2) Stripe success → credit wallet (store in cents)
      await repo.addMoney(
        (val * 100).round(),
        note: 'Top-up via payment gateway ($_currencyCode)',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Money added to wallet ($_currencyCode)')),
      );
      Navigator.of(context).pop(true); // back to wallet page, can reload
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add money: $e')),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle =
        _currencyName.isEmpty ? _currencyCode : '$_currencyCode · $_currencyName';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add money ($_currencyCode)'),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText:
                    'Amount in $_currencyCode (e.g. $_currencySymbol 25.00)',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : _add,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  loading ? 'Processing…' : 'Add money ($_currencyCode)',
                ),
              ),
            ),
          ],
        ),
      ),
      backgroundColor: const Color(0xFFF4F7F5),
    );
  }
}

/// Private helper for currency info (file-local)
class _CurrencyInfo {
  final String code;
  final String symbol;
  final String name;

  const _CurrencyInfo({
    required this.code,
    required this.symbol,
    required this.name,
  });
}
