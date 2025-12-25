// lib/features/onboarding/pages/profile_age_page.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:country_picker/country_picker.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../app_router.dart'; // For Routes.profileSetupGender

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56); // App Green

// NEW: Data model to carry state through setup pages
class ProfileSetupArgs {
  final DateTime? dob;
  final String? gender;
  final String? usage;

  // ✅ NEW: country + currency (optional, also saved to Firestore)
  final String? countryCode;
  final String? countryName;
  final String? currencyCode;
  final String? currencySymbol;
  final String? currencyName;

  const ProfileSetupArgs({
    this.dob,
    this.gender,
    this.usage,
    this.countryCode,
    this.countryName,
    this.currencyCode,
    this.currencySymbol,
    this.currencyName,
  });
}

/// Small internal model for currency lookup
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

class ProfileAgePage extends StatefulWidget {
  const ProfileAgePage({super.key});

  @override
  State<ProfileAgePage> createState() => _ProfileAgePageState();
}

class _ProfileAgePageState extends State<ProfileAgePage> {
  // Default to a date that is definitely 18+ (safe initial)
  DateTime _selectedDate = DateTime(2000, 1, 1);

  // Must be at least 18 years old
  DateTime get _minLegalDate =>
      DateTime(DateTime.now().year - 18, DateTime.now().month, DateTime.now().day);

  // ✅ Country selection
  Country? _selectedCountry;
  _CurrencyInfo? _currency;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Ensure initial value is valid (>= 18)
    if (_selectedDate.isAfter(_minLegalDate)) {
      _selectedDate = _minLegalDate;
    }
  }

  Future<void> _pickDate() async {
    final DateTime initialDate =
        _selectedDate.isBefore(_minLegalDate) ? _selectedDate : _minLegalDate;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: _minLegalDate, // must be at least 18
      helpText: 'Verify Your Date of Birth',
      errorInvalidText: 'You must be at least 18 years old.',
    );

    if (picked != null && picked != _selectedDate) {
      if (picked.isAfter(_minLegalDate)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be 18 years or older to proceed.')),
        );
      } else {
        setState(() => _selectedDate = picked);
      }
    }
  }

  Future<_CurrencyInfo?> _lookupCurrencyForCountryCode(String countryCode) async {
    try {
      final uri = Uri.https(
        'restcountries.com',
        '/v3.1/alpha/$countryCode',
        {'fields': 'currencies,name'},
      );

      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
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

  Future<void> _pickCountry() async {
    showCountryPicker(
      context: context,
      showPhoneCode: false,
      onSelect: (c) async {
        setState(() {
          _selectedCountry = c;
          _currency = null;
        });

        final info = await _lookupCurrencyForCountryCode(c.countryCode);
        if (!mounted) return;

        setState(() {
          _currency = info;
        });

        if (info == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not detect currency. Try again.')),
          );
        }
      },
    );
  }

  Future<void> _saveCountryCurrencyToFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No user signed in');
    }
    if (_selectedCountry == null) {
      throw Exception('No country selected');
    }
    if (_currency == null) {
      throw Exception('Currency not detected');
    }

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      {
        'countryCode': _selectedCountry!.countryCode, // e.g. IN
        'countryName': _selectedCountry!.name,        // e.g. India
        'currencyCode': _currency!.code,              // e.g. INR
        'currencySymbol': _currency!.symbol,          // e.g. ₹
        'currencyName': _currency!.name,              // e.g. Indian rupee
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _onNext() async {
    if (_saving) return;

    if (_selectedDate.isAfter(_minLegalDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a valid date of birth (min. 18 years).')),
      );
      return;
    }

    if (_selectedCountry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your country to continue.')),
      );
      return;
    }

    if (_currency == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Currency not detected yet. Please wait or pick again.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      // ✅ Save to Firestore (wallet will read this everywhere)
      await _saveCountryCurrencyToFirestore();

      if (!mounted) return;

      // Pass DOB + country/currency to the next page (optional)
      final args = ProfileSetupArgs(
        dob: _selectedDate,
        countryCode: _selectedCountry!.countryCode,
        countryName: _selectedCountry!.name,
        currencyCode: _currency!.code,
        currencySymbol: _currency!.symbol,
        currencyName: _currency!.name,
      );

      Navigator.of(context).pushNamed(Routes.profileSetupGender, arguments: args);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not continue: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chosenCountryText = _selectedCountry == null
        ? 'Tap to choose'
        : '${_selectedCountry!.flagEmoji} ${_selectedCountry!.name} (${_selectedCountry!.countryCode})';

    final currencyText = _currency == null
        ? 'Currency will be detected automatically'
        : 'Currency: ${_currency!.symbol} ${_currency!.code} (${_currency!.name})';

    return Scaffold(
      // Green background per DoraRide theme
      backgroundColor: _kThemeGreen,
      appBar: AppBar(
        backgroundColor: _kThemeGreen,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Profile set-up', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ First line: white, bold, large
              Text(
                'How old are you?',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
              ),
              const SizedBox(height: 10),

              // ✅ Second line: blue, bold, medium
              const Text(
                'You must be 18 or older to use DoraRide. Please select your date of birth.',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _kThemeBlue,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // ✅ NEW: Choose country
              Text(
                'Select your country (for wallet currency)',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.92),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),

              InkWell(
                onTap: _pickCountry,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 56,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.public, color: _kThemeBlue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          chosenCountryText,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: _kThemeBlue,
                                fontWeight: FontWeight.w800,
                              ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down, color: _kThemeBlue),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              Text(
                currencyText,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 18),

              // ✅ Illustration icon
              const Center(child: _AgeIllustrationIcon()),
              const SizedBox(height: 18),

              // DOB field (white background)
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  height: 56,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white),
                  ),
                  child: Text(
                    DateFormat('MMMM d, yyyy').format(_selectedDate),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),

              const Spacer(), // Push button to bottom

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kThemeBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Next',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Small illustration to match the rest of the flow
class _AgeIllustrationIcon extends StatelessWidget {
  const _AgeIllustrationIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 180,
      decoration: const BoxDecoration(
        color: Colors.white10,
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Icon(
          Icons.calendar_month_rounded, // calendar icon for DOB
          color: Colors.white,
          size: 84,
        ),
      ),
    );
  }
}
