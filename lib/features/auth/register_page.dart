import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../theme.dart';
import '../../app_router.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController firstNameCtrl = TextEditingController();
  final TextEditingController lastNameCtrl  = TextEditingController();
  final TextEditingController emailCtrl     = TextEditingController();
  final TextEditingController passCtrl      = TextEditingController();
  final TextEditingController confirmCtrl   = TextEditingController();

  bool _showPass = false;
  bool _showConfirm = false;
  bool _submitting = false;

  String? _validate() {
    if (firstNameCtrl.text.trim().isEmpty) return 'Please enter first name';
    if (lastNameCtrl.text.trim().isEmpty)  return 'Please enter last name';

    final email = emailCtrl.text.trim();
    if (email.isEmpty) return 'Please enter email';
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!re.hasMatch(email)) return 'Please enter a valid email';

    if (passCtrl.text.length < 6) {
      return 'Password must be at least 6 characters';
    }
    if (confirmCtrl.text != passCtrl.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  Future<void> _register() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    setState(() => _submitting = true);

    final email = emailCtrl.text.trim();
    final pass  = passCtrl.text.trim();
    final first = firstNameCtrl.text.trim();
    final last  = lastNameCtrl.text.trim();
    final displayName = '$first $last'.trim();

    try {
      // 1️⃣ Create user
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pass);

      final user = cred.user;
      if (user == null) throw Exception('Registration failed');

      await user.updateDisplayName(displayName);

      // 2️⃣ Firestore profile
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'firstName': first,
        'lastName': last,
        'email': email,
        'emailVerified': false,
        'profileCompleted': false,
        'onboardingCompleted': false,
        'isDriver': false,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 3️⃣ Send verification email
      await user.sendEmailVerification();

      // 4️⃣ Local flags
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('logged_in', false);
      await prefs.setBool('is_guest', false);
      await prefs.setBool('email_verified', false);
      await prefs.setBool('profile_completed', false);
      await prefs.setBool('onboarding_completed', false);

      if (!mounted) return;

      Navigator.pushReplacementNamed(
        context,
        Routes.emailVerify,
        arguments: {
          'email': email,
          'nextRoute': Routes.onboardingStart,
          'nextArgs': null,
        },
      );

    } on FirebaseAuthException catch (e) {
      String message = 'Registration failed';

      if (e.code == 'email-already-in-use') {
        try {
          // 🔥 IMPORTANT FIX
          final cred = await FirebaseAuth.instance
              .signInWithEmailAndPassword(email: email, password: pass);

          final user = cred.user;

          if (user != null && !user.emailVerified) {
            await user.sendEmailVerification();

            if (!mounted) return;

            Navigator.pushReplacementNamed(
              context,
              Routes.emailVerify,
              arguments: {
                'email': email,
                'nextRoute': Routes.onboardingStart,
                'nextArgs': null,
              },
            );
            return;
          } else {
            message = 'This email is already registered. Please sign in.';
          }
        } catch (_) {
          message = 'This email is already registered. Please sign in.';
        }
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email address.';
      } else if (e.code == 'weak-password') {
        message = 'Choose a stronger password.';
      } else if (e.code == 'operation-not-allowed') {
        message = 'Email/password sign-in is not enabled.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Unexpected error: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.green,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 26),
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, Routes.welcome),
                ),
              ),

              const SizedBox(height: 12),

              const Image(
                image: AssetImage('assets/logo_white.png'),
                height: 90,
              ),

              const SizedBox(height: 12),

              const Text(
                "DoraRide",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: firstNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'First name',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: lastNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Last name',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),

              const SizedBox(height: 14),

              TextField(
                controller: passCtrl,
                obscureText: !_showPass,
                decoration: InputDecoration(
                  hintText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_showPass
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _showPass = !_showPass),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              TextField(
                controller: confirmCtrl,
                obscureText: !_showConfirm,
                decoration: InputDecoration(
                  hintText: 'Confirm password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_showConfirm
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _showConfirm = !_showConfirm),
                  ),
                ),
              ),

              const SizedBox(height: 26),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _register,
                  child: _submitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Create account"),
                ),
              ),

              const SizedBox(height: 14),

              OutlinedButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, Routes.login),
                child: const Text("Back to Sign in"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
