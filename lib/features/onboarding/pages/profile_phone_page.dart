// lib/features/onboarding/pages/profile_phone_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:country_picker/country_picker.dart';

import '../../../app_router.dart';
import 'profile_age_page.dart'; // ProfileSetupArgs

const _kBlue = Color(0xFF180D3B);
const _kGreen = Color(0xFF279C56);

class ProfilePhonePage extends StatefulWidget {
  final ProfileSetupArgs? initialArgs;
  const ProfilePhonePage({super.key, this.initialArgs});

  @override
  State<ProfilePhonePage> createState() => _ProfilePhonePageState();
}

class _ProfilePhonePageState extends State<ProfilePhonePage> {
  // Default country = India
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

  final TextEditingController _phoneCtrl = TextEditingController();
  bool _saving = false;

  // carry flow arguments (dob, gender, usage)
  ProfileSetupArgs? _flowArgs;

  String get _fullDialCode => '+${_selectedCountry.phoneCode}';

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_flowArgs != null) return;

    if (widget.initialArgs != null) {
      _flowArgs = widget.initialArgs;
      return;
    }

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is ProfileSetupArgs) {
      _flowArgs = args;
    }
  }

  Future<void> _onNext() async {
    final raw = _phoneCtrl.text.trim();

    // basic validation – digits only, min length
    if (raw.isEmpty || raw.length < 5 || int.tryParse(raw) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid phone number')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in again.')),
      );
      return;
    }

    final fullNumber = '$_fullDialCode$raw';

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'phone': fullNumber,
          'phoneCountryCode': _fullDialCode,
          'phoneVerified': true, // manually true (no SMS yet)
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // forward same args (dob, gender, usage) to picture screen
      final argsToSend = _flowArgs;

      Navigator.pushNamed(
        context,
        Routes.profileSetupPicture,
        arguments: argsToSend,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save phone: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kGreen,
      appBar: AppBar(
        backgroundColor: _kGreen,
        foregroundColor: Colors.white,
        title: const Text('Profile set-up'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add your phone number',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'We’ll use this to help riders and drivers stay in touch about trips.',
                style: TextStyle(
                  fontSize: 18,
                  color: _kBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 40),

              Center(
                child: CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.white24,
                  child: const Icon(
                    Icons.phone_iphone,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 48),

              const Text(
                'Phone number',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  // Country picker button
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
                        border: Border.all(color: _kBlue),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _selectedCountry.flagEmoji,
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _fullDialCode,
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

                  // Phone input
                  Expanded(
                    child: TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      style: const TextStyle(
                        color: Colors.black, // visible on white bg
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: '9876543210',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade600,
                        ),
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
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Next',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
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
