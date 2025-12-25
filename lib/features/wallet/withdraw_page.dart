// lib/features/wallet/withdraw_page.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app_router.dart';
import '../../common/repos/wallet_repository.dart';
import '../../common/models/wallet_models.dart';

class WithdrawPage extends StatefulWidget {
  const WithdrawPage({super.key});

  @override
  State<WithdrawPage> createState() => _WithdrawPageState();
}

class _WithdrawPageState extends State<WithdrawPage> {
  static const kGreen = Color(0xFF279C56);
  static const kNavy = Color(0xFF180D3B);

  final _amount = TextEditingController(text: '10.00');
  final repo = WalletRepository();

  BankInfo? bank;
  bool loading = true;

  // 🌍 Currency (same default as wallet)
  String _currencyCode = 'INR';
  String _currencySymbol = '₹';
  String _currencyName = 'Indian rupee';

  @override
  void initState() {
    super.initState();
    _load();
    _initCurrencyFromProfileOrLocale();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    bank = await repo.getBankInfo();
    if (mounted) setState(() => loading = false);
  }

  /// Try to read user.countryCode/country from Firestore first,
  /// then fall back to platform locale (works on web + mobile).
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
      countryCode ??=
          WidgetsBinding.instance.platformDispatcher.locale.countryCode;

      if (countryCode == null || countryCode.isEmpty) return;

      final info = await _lookupCurrencyForCountryCode(countryCode);
      if (!mounted || info == null) return;

      setState(() {
        _currencyCode = info.code;
        _currencySymbol = info.symbol;
        _currencyName = info.name;
      });
    } catch (e) {
      debugPrint('Withdraw currency init failed: $e');
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
      debugPrint('Currency lookup failed (withdraw): $e');
      return null;
    }
  }

  Future<void> _withdraw() async {
    if (bank == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add bank details first')),
      );
      return;
    }

    final val = double.tryParse(_amount.text.replaceAll(',', ''));
    if (val == null || val <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enter a valid amount in $_currencyCode')),
      );
      return;
    }

    setState(() => loading = true);
    try {
      // This uses Option B: only subtract on admin approval.
      await repo.requestWithdraw((val * 100).round());
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Withdrawal requested ($_currencyCode)'),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  InputDecoration _fieldDec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );

  @override
  Widget build(BuildContext context) {
    final subtitle =
        _currencyName.isEmpty ? _currencyCode : '$_currencyCode · $_currencyName';

    return Scaffold(
      backgroundColor: kGreen,
      appBar: AppBar(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Withdraw ($_currencyCode)'),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.account_balance, color: kNavy),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Payout account',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              bank == null
                                  ? 'No bank linked'
                                  : '${bank!.accountHolder} • ${bank!.accountNumberMasked}\n'
                                      '${bank!.email} • ${bank!.phone}',
                              style: const TextStyle(color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context)
                            .pushNamed(Routes.walletBank)
                            .then((_) => _load()),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: kGreen),
                          foregroundColor: kGreen,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: Text(bank == null ? 'Add' : 'Edit'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _fieldDec(
                    'Amount in $_currencyCode (e.g. $_currencySymbol 10.00)',
                  ),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: loading ? null : _withdraw,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kNavy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      loading ? 'Submitting…' : 'Withdraw ($_currencyCode)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Simple internal model to match Wallet/AddMoney currency helper.
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
