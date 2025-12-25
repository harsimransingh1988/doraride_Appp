// lib/features/profile/phone_number_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:country_picker/country_picker.dart';

const _kGreen = Color(0xFF279C56);
const _kBlue = Color(0xFF180D3B);

class PhoneNumberPage extends StatefulWidget {
  const PhoneNumberPage({super.key});

  @override
  State<PhoneNumberPage> createState() => _PhoneNumberPageState();
}

class _PhoneNumberPageState extends State<PhoneNumberPage> {
  final TextEditingController _currentPhoneCtrl = TextEditingController();
  final TextEditingController _newPhoneCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  // Default = India
  Country _selectedCountry = Country(
    phoneCode: '91',
    countryCode: 'IN',
    e164Sc: 0,
    geographic: true,
    level: 1,
    name: 'India',
    example: '9123456789',
    displayName: 'India',
    displayNameNoCountryCode: 'India',
    e164Key: '',
  );

  String get _dialCode => '+${_selectedCountry.phoneCode}';

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  @override
  void initState() {
    super.initState();
    _loadCurrentPhone();
  }

  Future<void> _loadCurrentPhone() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return;
      }

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (snap.exists) {
        final data = snap.data();
        final phone = data?['phone'] as String?;
        final phoneCode = data?['phoneCountryCode'] as String?;

        if (phone != null && phone.isNotEmpty) {
          _currentPhoneCtrl.text = phone;
        }

        if (phoneCode != null && phoneCode.startsWith('+')) {
          final dial = phoneCode.substring(1); // remove '+'
          _selectedCountry = Country(
            phoneCode: dial,
            countryCode: _selectedCountry.countryCode,
            e164Sc: 0,
            geographic: true,
            level: 1,
            name: _selectedCountry.name,
            example: _selectedCountry.example,
            displayName: _selectedCountry.displayName,
            displayNameNoCountryCode:
                _selectedCountry.displayNameNoCountryCode,
            e164Key: '',
          );
        }
      }
    } catch (_) {
      // ignore, just show empty
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pickCountry() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      searchAutofocus: true,
      countryListTheme: CountryListThemeData(
        flagSize: 24,
        backgroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 16),
        bottomSheetHeight: 500,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        inputDecoration: InputDecoration(
          labelText: 'Search country',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      onSelect: (Country c) {
        setState(() => _selectedCountry = c);
      },
    );
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in again.')),
      );
      return;
    }

    final raw = _newPhoneCtrl.text.trim();

    if (raw.isEmpty || raw.length < 5 || int.tryParse(raw) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid new phone number.')),
      );
      return;
    }

    final full = '$_dialCode$raw';

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'phone': full,
          'phoneCountryCode': _dialCode,
          'phoneVerified': true, // still treating it as verified for now
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;

      _currentPhoneCtrl.text = full;
      _newPhoneCtrl.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number updated.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update phone: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _currentPhoneCtrl.dispose();
    _newPhoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kGreen,
      appBar: AppBar(
        title: const Text('Phone number'),
        backgroundColor: _kGreen,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Current phone (read-only)
                TextField(
                  controller: _currentPhoneCtrl,
                  readOnly: true,
                  decoration: _dec('Current phone number'),
                ),
                const SizedBox(height: 12),

                const Text(
                  'New phone number',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),

                // New phone row: country picker + number
                Row(
                  children: [
                    InkWell(
                      onTap: _pickCountry,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _kBlue,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              _selectedCountry.flagEmoji,
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _dialCode,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _newPhoneCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          hintText: 'New phone number',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _kBlue),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _kBlue),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: _kBlue,
                              width: 2,
                            ),
                          ),
                        ),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _kBlue,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _kBlue,
                            ),
                          )
                        : const Text('Update phone'),
                  ),
                ),
              ],
            ),
    );
  }
}
