// lib/features/auth/phone_verification_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_router.dart';

const _kThemeGreen = Color(0xFF279C56);
const _kThemeBlue = Color(0xFF180D3B);

class PhoneVerificationPage extends StatefulWidget {
  final String? initialPhone;
  final String? nextRoute;
  final Object? nextArgs;

  const PhoneVerificationPage({
    super.key,
    this.initialPhone,
    this.nextRoute,
    this.nextArgs,
  });

  @override
  State<PhoneVerificationPage> createState() => _PhoneVerificationPageState();
}

class _PhoneVerificationPageState extends State<PhoneVerificationPage> {
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();

  bool _sendingCode = false;
  bool _verifying = false;
  bool _codeSent = false;
  String? _verificationId;
  int? _resendToken;

  @override
  void initState() {
    super.initState();

    // Prefill phone from argument, or from Auth user if available
    if (widget.initialPhone != null && widget.initialPhone!.isNotEmpty) {
      _phoneCtrl.text = widget.initialPhone!;
    } else {
      final user = FirebaseAuth.instance.currentUser;
      if (user?.phoneNumber != null && user!.phoneNumber!.isNotEmpty) {
        _phoneCtrl.text = user.phoneNumber!;
      }
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  /// Decide where to go AFTER phone is verified.
  Map<String, Object?> _resolveArgs() {
    final routeArgs = ModalRoute.of(context)?.settings.arguments;

    String? nextRoute = widget.nextRoute;
    Object? nextArgs = widget.nextArgs;

    if (routeArgs is Map<String, dynamic>) {
      if (routeArgs['nextRoute'] is String) {
        nextRoute ??= routeArgs['nextRoute'] as String;
      }
      if (routeArgs.containsKey('nextArgs')) {
        nextArgs ??= routeArgs['nextArgs'];
      }
      if (routeArgs['initialPhone'] is String &&
          (_phoneCtrl.text.isEmpty || _phoneCtrl.text.trim().isEmpty)) {
        _phoneCtrl.text = routeArgs['initialPhone'] as String;
      }
    }

    nextRoute ??= Routes.home;

    return {
      'nextRoute': nextRoute,
      'nextArgs': nextArgs,
    };
  }

  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a phone number.')),
      );
      return;
    }

    // Simple sanity check: must start with + and be at least ~8–10 digits
    if (!phone.startsWith('+') || phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter phone in full international format, e.g. +1 647-123-4567'),
        ),
      );
      return;
    }

    setState(() {
      _sendingCode = true;
      _codeSent = false;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // On Android this can auto-complete; on Web it usually won’t.
          await _linkOrUpdatePhone(credential, auto: true);
        },
        verificationFailed: (FirebaseAuthException e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Verification failed: ${e.message}')),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _codeSent = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('OTP code sent. Please check your SMS.')),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send code: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _sendingCode = false);
      }
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();

    if (!_codeSent || _verificationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please request an OTP first.')),
      );
      return;
    }

    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit OTP you received.')),
      );
      return;
    }

    setState(() => _verifying = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );

      await _linkOrUpdatePhone(credential, auto: false);
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OTP verification failed: ${e.message}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error: $e')),
      );
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  /// Link the phone credential to the current user (or update if already linked),
  /// then set phoneVerified: true in Firestore + local prefs, then go to nextRoute.
  Future<void> _linkOrUpdatePhone(
    PhoneAuthCredential credential, {
    required bool auto,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw 'No signed-in user.';
    }

    // 1) Link or update on the Auth user
    if (user.phoneNumber == null || user.phoneNumber!.isEmpty) {
      await user.linkWithCredential(credential);
    } else {
      await user.updatePhoneNumber(credential);
    }

    // Reload to be sure phoneNumber is populated
    await user.reload();
    final reloaded = FirebaseAuth.instance.currentUser;
    final phoneAfter = reloaded?.phoneNumber ?? _phoneCtrl.text.trim();

    // 2) Update Firestore user doc
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      {
        'phoneNumber': phoneAfter,
        'phoneVerified': true,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    // 3) Local preference (optional flag)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('phone_verified', true);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Phone number verified successfully ✅')),
    );

    // 4) Navigate to the "next" page (usually home)
    final resolved = _resolveArgs();
    final String nextRoute = resolved['nextRoute'] as String;
    final Object? nextArgs = resolved['nextArgs'];

    Navigator.of(context).pushNamedAndRemoveUntil(
      nextRoute,
      (route) => false,
      arguments: nextArgs,
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolveArgs();

    return Scaffold(
      backgroundColor: _kThemeGreen,
      appBar: AppBar(
        backgroundColor: _kThemeGreen,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Verify your phone'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add your phone number',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'We use this to keep your account secure and help riders/drivers reach you.',
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 20),

              // PHONE INPUT
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.phone_android),
                  hintText: '+1 647-123-4567',
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kThemeBlue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _sendingCode ? null : _sendCode,
                  icon: _sendingCode
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.sms_rounded),
                  label: Text(
                    _sendingCode
                        ? 'Sending OTP…'
                        : (_codeSent ? 'Resend OTP' : 'Send OTP'),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'Enter the 6-digit code',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),

              // OTP INPUT
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  counterText: '',
                  prefixIcon: Icon(Icons.lock_outline),
                  hintText: '••••••',
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _kThemeBlue,
                  ),
                  onPressed: _verifying ? null : _verifyCode,
                  child: _verifying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Verify phone',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),

              const Spacer(),
              Text(
                'Next: ${resolved['nextRoute']}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
