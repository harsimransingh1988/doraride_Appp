// lib/features/auth/welcome_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app_router.dart';
import '../../theme.dart';
import 'auth_service.dart'; // ✅ NEW

// Accent
const Color _kThemeBlue = Color(0xFF180D3B);

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ac, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, .08),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ac, curve: Curves.easeOutCubic));

  final _authService = AuthService(); // ✅ NEW

  bool _loadingGoogle = false;
  bool _loadingGuest = false;

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  // ---------------------------
  // Shared post-login handling
  // ---------------------------
  Future<void> _afterLogin(UserCredential cred, String method) async {
    final prefs = await SharedPreferences.getInstance();

    // Mark logged-in (not guest)
    await prefs.setBool('logged_in', true);
    await prefs.setBool('is_guest', false);

    // Initialize profile_completed if not present
    final bool hasProfileFlag = prefs.containsKey('profile_completed');
    if (!hasProfileFlag) {
      await prefs.setBool('profile_completed', false); // first time -> onboarding
    }
    final bool profileCompleted = prefs.getBool('profile_completed') ?? false;

    // Create / update user doc
    final user = cred.user;
    if (user != null) {
      final uid = user.uid;
      final displayName = (user.displayName ?? '').trim();
      final email = (user.email ?? '').trim();
      final photo = user.photoURL;

      // Split name (rough best-effort)
      String? firstName;
      String? lastName;
      if (displayName.isNotEmpty) {
        final parts = displayName.split(' ');
        if (parts.isNotEmpty) firstName = parts.first;
        if (parts.length > 1) lastName = parts.sublist(1).join(' ');
      }

      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final existing = await docRef.get();

      await docRef.set({
        // identity
        if (firstName != null && firstName.isNotEmpty) 'firstName': firstName,
        if (lastName != null && lastName.isNotEmpty) 'lastName': lastName,
        if (displayName.isNotEmpty) 'displayName': displayName,
        if (email.isNotEmpty) 'email': email,
        if (photo != null) 'photoUrl': photo,

        // verification hints
        'emailVerified': user.emailVerified,
        'phoneVerified': user.phoneNumber != null && user.phoneNumber!.isNotEmpty,

        // bookkeeping
        'lastLoginAt': FieldValue.serverTimestamp(),
        if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
        if (!existing.exists) 'authProvider': method,
      }, SetOptions(merge: true));
    }

    if (!mounted) return;
    if (!profileCompleted) {
      Navigator.pushReplacementNamed(context, Routes.onboardingStart);
    } else {
      Navigator.pushReplacementNamed(context, Routes.home);
    }
  }

  // --------------------------------
  // Google OAuth (Android + Web)
  // --------------------------------
  Future<void> _signInWithGoogle() async {
    if (_loadingGoogle) return;
    setState(() => _loadingGoogle = true);

    try {
      // ✅ FIX: Works on Android/iOS + Web (no signInWithPopup crash on Android)
      final cred = await _authService.signInWithGoogle();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in with Google')),
        );
      }

      await _afterLogin(cred, 'google');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google sign-in failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  // ---------------------------
  // Guest (no auth)
  // ---------------------------
  Future<void> _continueAsGuest() async {
    if (_loadingGuest) return;
    setState(() => _loadingGuest = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('logged_in', true);
      await prefs.setBool('is_guest', true);

      // Guests skip onboarding and go straight to Home shell
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, Routes.home);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Guest entry failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingGuest = false);
    }
  }

  // Email login/registration page
  void _navigateToLogin() {
    Navigator.pushReplacementNamed(context, Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.green,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 26),
                  onPressed: () => Navigator.pushReplacementNamed(
                      context, Routes.landing),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Welcome to DoraRide!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'We’re thrilled to have you here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Let’s get you on the road —',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose an option below to sign in.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),

              Expanded(
                child: Center(
                  child: FadeTransition(
                    opacity: _fade,
                    child: SlideTransition(
                      position: _slide,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(25),
                        child: Image.asset(
                          'assets/welcome_image.png',
                          height: 250,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              _BottomButtons(
                onGoogleTap: _loadingGoogle ? null : _signInWithGoogle,
                onEmailTap: _navigateToLogin,
                onGuestTap: _loadingGuest ? null : _continueAsGuest,
                loadingGoogle: _loadingGoogle,
                loadingGuest: _loadingGuest,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------
// Buttons (Google / Email / Guest only)
// --------------------------------------
class _BottomButtons extends StatelessWidget {
  final VoidCallback? onGoogleTap;
  final VoidCallback onEmailTap;
  final VoidCallback? onGuestTap;

  final bool loadingGoogle;
  final bool loadingGuest;

  const _BottomButtons({
    required this.onGoogleTap,
    required this.onEmailTap,
    required this.onGuestTap,
    required this.loadingGoogle,
    required this.loadingGuest,
  });

  @override
  Widget build(BuildContext context) {
    const double btnHeight = 50;
    const double radius = 40;

    ButtonStyle filledBlue() => ElevatedButton.styleFrom(
          backgroundColor: AppColors.blue,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(btnHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          elevation: 4,
          shadowColor: Colors.black26,
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        );
    ButtonStyle filledWhiteBlueText() => ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.blue,
          minimumSize: const Size.fromHeight(btnHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          elevation: 2,
          shadowColor: Colors.black12,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        );
    ButtonStyle outlinedWhite() => OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(btnHeight),
          side: const BorderSide(color: Colors.white, width: 2),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        );

    Row row(IconData icon, String label, {Color? iconColor}) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 10),
            Text(label),
          ],
        );

    Widget maybeSpinner(bool loading) => loading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Google
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onGoogleTap,
                style: filledWhiteBlueText(),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    row(Icons.g_translate, 'Continue with Google',
                        iconColor: _kThemeBlue),
                    Positioned(right: 16, child: maybeSpinner(loadingGoogle)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Email
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onEmailTap,
                style: filledBlue(),
                child: row(Icons.mail_outline, 'Continue with Email',
                    iconColor: Colors.white),
              ),
            ),
            const SizedBox(height: 12),

            // Guest
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onGuestTap,
                style: outlinedWhite(),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    row(Icons.person_outline, 'Continue as Guest',
                        iconColor: Colors.white),
                    Positioned(right: 16, child: maybeSpinner(loadingGuest)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
