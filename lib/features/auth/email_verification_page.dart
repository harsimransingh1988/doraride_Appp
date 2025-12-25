// lib/features/auth/email_verification_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app_router.dart';

const _kThemeGreen = Color(0xFF279C56);
const _kThemeBlue = Color(0xFF180D3B);

class VerifyEmailArgs {
  final String? email;
  final String? nextRoute;
  final Object? nextArgs;
  const VerifyEmailArgs({this.email, this.nextRoute, this.nextArgs});
}

class EmailVerificationPage extends StatefulWidget {
  final String? email;
  final String? nextRoute;
  final Object? nextArgs;

  const EmailVerificationPage({
    super.key,
    this.email,
    this.nextRoute,
    this.nextArgs,
  });

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  static const int _initialSeconds = 60;
  static const Duration _pollInterval = Duration(seconds: 3);

  int _secondsLeft = _initialSeconds;
  bool _resending = false;
  bool _autoChecking = true;
  Timer? _countdownTimer;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    _startPolling();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _secondsLeft = _initialSeconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer =
        Timer.periodic(_pollInterval, (_) => _checkVerified(auto: true));
  }

  /// ✅ Back button behaviour: go back to Register page (for wrong email)
  Future<void> _goBackToRegister() async {
    // Stop timers to avoid any extra calls
    _countdownTimer?.cancel();
    _pollTimer?.cancel();

    // Sign out so register page doesn't get confused with current session
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(Routes.register);
  }

  /// Helper to read email / nextRoute / nextArgs from route arguments OR widget props.
  Map<String, Object?> _resolveArgs() {
    final routeArgs = ModalRoute.of(context)?.settings.arguments;

    String? email = widget.email;
    String? nextRoute = widget.nextRoute;
    Object? nextArgs = widget.nextArgs;

    if (routeArgs is VerifyEmailArgs) {
      email ??= routeArgs.email;
      nextRoute ??= routeArgs.nextRoute;
      nextArgs ??= routeArgs.nextArgs;
    } else if (routeArgs is Map<String, dynamic>) {
      if (routeArgs['email'] is String) {
        email ??= routeArgs['email'] as String;
      }
      if (routeArgs['nextRoute'] is String) {
        nextRoute ??= routeArgs['nextRoute'] as String;
      }
      if (routeArgs.containsKey('nextArgs')) {
        nextArgs ??= routeArgs['nextArgs'];
      }
    }

    // Defaults
    email ??= 'your@email.com';
    nextRoute ??= Routes.onboardingStart;

    return {
      'email': email,
      'nextRoute': nextRoute,
      'nextArgs': nextArgs,
    };
  }

  Future<void> _checkVerified({bool auto = false}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.reload();
      final verified = FirebaseAuth.instance.currentUser?.emailVerified == true;

      if (verified) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('email_verified', true);
        await prefs.setBool('logged_in', true);

        // ✅ Also mark emailVerified in Firestore
        if (user != null) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
            {'emailVerified': true},
            SetOptions(merge: true),
          );

          // ✅ If profile already complete -> go home
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (userDoc.exists) {
            final data = userDoc.data() ?? {};
            final bool profileCompleted =
                (data['profileCompleted'] as bool?) ?? false;
            final bool onboardingCompleted =
                (data['onboardingCompleted'] as bool?) ?? false;

            if (profileCompleted && onboardingCompleted) {
              await prefs.setBool('profile_setup_complete', true);
              final resolved = _resolveArgs();
              final String currentNextRoute =
                  resolved['nextRoute'] as String? ?? Routes.onboardingStart;

              if (currentNextRoute == Routes.onboardingStart) {
                if (!mounted) return;
                Navigator.of(context).pushReplacementNamed(
                  Routes.home,
                  arguments: resolved['nextArgs'],
                );
                return;
              }
            } else {
              await prefs.setBool('profile_setup_complete', false);
            }
          }
        }

        _pollTimer?.cancel();
        if (!mounted) return;

        final resolved = _resolveArgs();
        final String nextRoute = resolved['nextRoute'] as String;
        final Object? nextArgs = resolved['nextArgs'];

        Navigator.of(context).pushReplacementNamed(
          nextRoute,
          arguments: nextArgs,
        );
      } else {
        if (!mounted) return;
        if (!auto) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your email is not verified yet. Please tap the link we sent.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (!auto) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not check verification: $e')),
        );
      }
    } finally {
      if (mounted && auto && _autoChecking == true) {
        Future.delayed(const Duration(seconds: 6), () {
          if (mounted) setState(() => _autoChecking = false);
        });
      }
    }
  }

  Future<void> _resendEmail() async {
    if (_secondsLeft > 0 || _resending) return;
    setState(() => _resending = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.sendEmailVerification();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("We've sent you a new verification email.")),
        );
        _startCountdown();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session expired. Please sign in again.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not resend email: $e')),
      );
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolveArgs();
    final String email = resolved['email'] as String;

    return Scaffold(
      backgroundColor: _kThemeGreen,
      appBar: AppBar(
        title: const Text('Verify your email'),
        backgroundColor: _kThemeGreen,
        elevation: 0,
        foregroundColor: Colors.white,

        // ✅ Always show a back button that returns to Register (wrong email case)
        leading: IconButton(
          tooltip: 'Change email',
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: _goBackToRegister,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const SizedBox(height: 6),
            const Icon(Icons.mark_email_unread_rounded,
                size: 72, color: Colors.white),
            const SizedBox(height: 16),

            Text(
              'Check your inbox',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'We\'ve sent a verification link to:',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.95),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              email,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'Open the link to verify your email. If you don\'t see it, check your spam or junk folder.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.85)),
            ),

            if (_autoChecking) ...[
              const SizedBox(height: 10),
              Text(
                'We\'ll detect your verification automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.8)),
              ),
            ],

            const SizedBox(height: 24),

            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _kThemeBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed:
                  (_secondsLeft == 0 && !_resending) ? _resendEmail : null,
              icon: _resending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(
                _resending
                    ? 'Sending…'
                    : (_secondsLeft == 0
                        ? 'Resend verification email'
                        : 'Resend in ${_secondsLeft}s'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),

            const SizedBox(height: 12),

            FilledButton.icon(
              icon: const Icon(Icons.verified_rounded),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _kThemeBlue,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => _checkVerified(auto: false),
              label: const Text(
                'I\'ve verified my email',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),

            const SizedBox(height: 12),

            // ✅ Extra helper line for wrong email
            TextButton(
              onPressed: _goBackToRegister,
              child: const Text(
                'Wrong email? Go back and change it',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),

            const SizedBox(height: 6),
            Text(
              'Tip: Leave this screen open. After you verify, we\'ll continue automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.85)),
            ),
          ],
        ),
      ),
    );
  }
}
