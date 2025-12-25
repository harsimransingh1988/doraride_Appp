// lib/features/wallet/wallet_page.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app_router.dart';
import '../../common/models/wallet_models.dart';
import '../../common/repos/wallet_repository.dart';

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

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  static const kGreen = Color(0xFF279C56);
  static const kNavy = Color(0xFF180D3B);

  final repo = WalletRepository();
  int balance = 0;
  List<WalletTransaction> txns = [];

  // Default fallback
  String _currencyCode = 'USD';
  String _currencySymbol = r'$';
  String _currencyName = 'United States dollar';

  // Offline quick map (fast + avoids web issues)
  static const Map<String, _CurrencyInfo> _countryToCurrency = {
    'IN': _CurrencyInfo(code: 'INR', symbol: '₹', name: 'Indian rupee'),
    'US': _CurrencyInfo(code: 'USD', symbol: r'$', name: 'United States dollar'),
    'CA': _CurrencyInfo(code: 'CAD', symbol: r'$', name: 'Canadian dollar'),
    'GB': _CurrencyInfo(code: 'GBP', symbol: '£', name: 'British pound'),
    'AE': _CurrencyInfo(code: 'AED', symbol: 'د.إ', name: 'UAE dirham'),
    'SA': _CurrencyInfo(code: 'SAR', symbol: 'ر.س', name: 'Saudi riyal'),
    'PK': _CurrencyInfo(code: 'PKR', symbol: '₨', name: 'Pakistani rupee'),
    'AU': _CurrencyInfo(code: 'AUD', symbol: r'$', name: 'Australian dollar'),
    'NZ': _CurrencyInfo(code: 'NZD', symbol: r'$', name: 'New Zealand dollar'),
    'SG': _CurrencyInfo(code: 'SGD', symbol: r'$', name: 'Singapore dollar'),
    'MY': _CurrencyInfo(code: 'MYR', symbol: 'RM', name: 'Malaysian ringgit'),
    'ID': _CurrencyInfo(code: 'IDR', symbol: 'Rp', name: 'Indonesian rupiah'),
    'BD': _CurrencyInfo(code: 'BDT', symbol: '৳', name: 'Bangladeshi taka'),
    'LK': _CurrencyInfo(code: 'LKR', symbol: 'Rs', name: 'Sri Lankan rupee'),
  };

  // Code -> currency (fallback if countryCode missing)
  static const Map<String, _CurrencyInfo> _codeToCurrency = {
    'INR': _CurrencyInfo(code: 'INR', symbol: '₹', name: 'Indian rupee'),
    'USD': _CurrencyInfo(code: 'USD', symbol: r'$', name: 'United States dollar'),
    'CAD': _CurrencyInfo(code: 'CAD', symbol: r'$', name: 'Canadian dollar'),
    'GBP': _CurrencyInfo(code: 'GBP', symbol: '£', name: 'British pound'),
    'EUR': _CurrencyInfo(code: 'EUR', symbol: '€', name: 'Euro'),
    'AED': _CurrencyInfo(code: 'AED', symbol: 'د.إ', name: 'UAE dirham'),
    'SAR': _CurrencyInfo(code: 'SAR', symbol: 'ر.س', name: 'Saudi riyal'),
    'PKR': _CurrencyInfo(code: 'PKR', symbol: '₨', name: 'Pakistani rupee'),
    'AUD': _CurrencyInfo(code: 'AUD', symbol: r'$', name: 'Australian dollar'),
    'NZD': _CurrencyInfo(code: 'NZD', symbol: r'$', name: 'New Zealand dollar'),
    'SGD': _CurrencyInfo(code: 'SGD', symbol: r'$', name: 'Singapore dollar'),
    'MYR': _CurrencyInfo(code: 'MYR', symbol: 'RM', name: 'Malaysian ringgit'),
    'IDR': _CurrencyInfo(code: 'IDR', symbol: 'Rp', name: 'Indonesian rupiah'),
    'BDT': _CurrencyInfo(code: 'BDT', symbol: '৳', name: 'Bangladeshi taka'),
    'LKR': _CurrencyInfo(code: 'LKR', symbol: 'Rs', name: 'Sri Lankan rupee'),
  };

  @override
  void initState() {
    super.initState();
    _load();
    _initCurrencyFromFirestoreFirst();
  }

  Future<void> _load() async {
    final b = await repo.getBalanceCents();
    final t = await repo.getTransactions();
    if (!mounted) return;
    setState(() {
      balance = b;
      txns = t;
    });
  }

  String _money(int cents) {
    final f = NumberFormat.currency(
      name: _currencyCode,
      symbol: _currencySymbol,
    );
    return f.format(cents / 100);
  }

  void _applyCurrency(_CurrencyInfo info) {
    setState(() {
      _currencyCode = info.code.toUpperCase().trim();
      _currencySymbol = info.symbol.trim();
      _currencyName = info.name.trim();
    });
  }

  bool _isConsistentCurrency(String code, String symbol, String name) {
    final c = code.toUpperCase().trim();
    final s = symbol.trim();
    final n = name.toLowerCase().trim();

    if (c.isEmpty || s.isEmpty || c.length != 3) return false;

    // Strict known checks (prevents "₹ USD (Indian rupee)")
    if (c == 'INR') return s.contains('₹') && n.contains('rupee');
    if (c == 'USD') return s.contains(r'$') && n.contains('dollar');
    if (c == 'EUR') return s.contains('€') && n.contains('euro');
    if (c == 'GBP') return s.contains('£') && (n.contains('pound') || n.contains('sterling'));

    // For other codes: at least require 3-letter currency code
    return true;
  }

  Future<void> _initCurrencyFromFirestoreFirst() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await docRef.get();
      final data = snap.data() ?? {};

      final savedCode = (data['currencyCode'] as String?)?.trim();
      final savedSymbol = (data['currencySymbol'] as String?)?.trim();
      final savedName = (data['currencyName'] as String?)?.trim();
      final savedCountry = (data['countryCode'] as String?)?.trim();

      final hasAll = savedCode != null &&
          savedSymbol != null &&
          savedName != null &&
          savedCode.isNotEmpty &&
          savedSymbol.isNotEmpty &&
          savedName.isNotEmpty;

      // ✅ Use saved values ONLY if fully consistent
      if (hasAll && _isConsistentCurrency(savedCode!, savedSymbol!, savedName!)) {
        if (!mounted) return;
        _applyCurrency(_CurrencyInfo(code: savedCode!, symbol: savedSymbol!, name: savedName!));
        return;
      }

      // ❗ Otherwise rebuild a correct set (never allow mixed)
      String? cc = savedCountry?.toUpperCase();
      cc ??= WidgetsBinding.instance.platformDispatcher.locale.countryCode;

      _CurrencyInfo? info;

      // 1) Prefer countryCode mapping
      if (cc != null && cc.isNotEmpty) {
        info = _countryToCurrency[cc];
        info ??= await _lookupCurrencyForCountryCode(cc);
      }

      // 2) If still null, try currencyCode mapping (if it exists)
      final codeUpper = savedCode?.toUpperCase();
      if (info == null && codeUpper != null && codeUpper.isNotEmpty) {
        info = _codeToCurrency[codeUpper];
      }

      // 3) Final fallback
      info ??= const _CurrencyInfo(code: 'USD', symbol: r'$', name: 'United States dollar');

      if (!mounted) return;
      _applyCurrency(info);

      // ✅ Save corrected values so this user is fixed forever
      await docRef.set(
        {
          if (cc != null && cc.isNotEmpty) 'countryCode': cc,
          'currencyCode': info.code.toUpperCase(),
          'currencySymbol': info.symbol,
          'currencyName': info.name,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Wallet currency init failed: $e');
    }
  }

  Future<_CurrencyInfo?> _lookupCurrencyForCountryCode(String countryCode) async {
    try {
      final uri = Uri.https(
        'restcountries.com',
        '/v3.1/alpha/$countryCode',
        {'fields': 'currencies'},
      );

      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;

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
    } catch (_) {
      return null;
    }
  }

  Color _chipColor(WalletTxnType t) {
    switch (t) {
      case WalletTxnType.add:
        return Colors.green.shade50;
      case WalletTxnType.ridePayment:
        return Colors.blue.shade50;
      case WalletTxnType.withdraw:
        return Colors.red.shade50;
    }
  }

  String _chipLabel(WalletTxnType t) {
    switch (t) {
      case WalletTxnType.add:
        return 'Top-up';
      case WalletTxnType.ridePayment:
        return 'Ride';
      case WalletTxnType.withdraw:
        return 'Withdraw';
    }
  }

  String _amountPrefix(WalletTransaction t) {
    if (t.type == WalletTxnType.withdraw) {
      return t.status == WalletTxnStatus.success ? '-' : '';
    }
    return '+';
  }

  Color _amountColor(WalletTransaction t) {
    if (t.type == WalletTxnType.withdraw) {
      if (t.status == WalletTxnStatus.pending) return Colors.orange.shade700;
      if (t.status == WalletTxnStatus.failed) return Colors.red.shade300;
      return Colors.red;
    }
    return Colors.green;
  }

  String? _statusText(WalletTransaction t) {
    switch (t.status) {
      case WalletTxnStatus.pending:
        return 'Pending approval';
      case WalletTxnStatus.failed:
        return 'Failed';
      case WalletTxnStatus.success:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F5),
      appBar: AppBar(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        title: const Text('Wallet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context)
                  .pushNamed(Routes.walletBank)
                  .then((_) => _load()),
              icon: const Icon(Icons.account_balance, color: Colors.white, size: 18),
              label: const Text(
                'Add bank details',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current balance',
                    style: TextStyle(color: kNavy, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _money(balance),
                    style: const TextStyle(
                      color: kNavy,
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      const Icon(Icons.payments_outlined, size: 18, color: kNavy),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Currency: $_currencySymbol $_currencyCode'
                          '${_currencyName.isNotEmpty ? ' ($_currencyName)' : ''}',
                          style: TextStyle(
                            color: kNavy.withOpacity(0.8),
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context)
                              .pushNamed(Routes.walletAdd)
                              .then((_) => _load()),
                          icon: const Icon(Icons.add),
                          label: const Text('Add money'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kGreen,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context)
                              .pushNamed(Routes.walletWithdraw)
                              .then((_) => _load()),
                          icon: const Icon(Icons.arrow_downward, color: kNavy),
                          label: const Text('Withdraw'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kNavy,
                            side: BorderSide(color: kNavy.withOpacity(0.2)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Text(
              'Transactions',
              style: TextStyle(
                color: kNavy,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),

            if (txns.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'No transactions yet.',
                  style: TextStyle(color: kNavy, fontWeight: FontWeight.w600),
                ),
              )
            else
              ...txns.map((t) {
                final statusText = _statusText(t);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: _chipColor(t.type),
                        child: Icon(
                          t.type == WalletTxnType.withdraw
                              ? Icons.call_made
                              : Icons.call_received,
                          color: kNavy,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _chipLabel(t.type),
                              style: const TextStyle(
                                color: kNavy,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              t.note.isEmpty
                                  ? DateFormat('MMM d, yyyy h:mm a').format(t.createdAt)
                                  : t.note,
                              style: TextStyle(color: kNavy.withOpacity(0.7)),
                            ),
                            if (statusText != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                statusText,
                                style: TextStyle(
                                  color: t.status == WalletTxnStatus.pending
                                      ? Colors.orange.shade700
                                      : Colors.red.shade400,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text(
                        _amountPrefix(t) + _money(t.amountCents),
                        style: TextStyle(
                          color: _amountColor(t),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
