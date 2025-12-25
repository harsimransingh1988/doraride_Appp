import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../theme.dart';
import '../../app_router.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailCtrl = TextEditingController();
  final TextEditingController passCtrl = TextEditingController();
  bool _showPass = false;
  bool _submitting = false;
  bool _resetting = false;

  Future<void> _login() async {
    final email = emailCtrl.text.trim();
    final pass = passCtrl.text;

    if (email.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      // 1) Sign in with Firebase
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );

      // 2) Refresh & check verified
      await cred.user?.reload();
      final user = FirebaseAuth.instance.currentUser;

      if (user?.emailVerified != true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('logged_in', false);
        await prefs.setBool('is_guest', false);
        await prefs.setBool('email_verified', false);

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
      }

      // 3) Verified user → upsert/read Firestore profile
      final docRef =
          FirebaseFirestore.instance.collection('users').doc(user!.uid);
      final snap = await docRef.get();

      if (!snap.exists) {
        // Create a basic profile if missing
        await docRef.set({
          'uid': user.uid,
          'email': user.email,
          'firstName': '',
          'lastName': '',
          'emailVerified': true,
          'profileCompleted': false,
          'onboardingCompleted': false, // 👈 ensure explicit flag exists
          'isDriver': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Ensure emailVerified is in sync
        await docRef.set(
          {
            'emailVerified': true,
          },
          SetOptions(merge: true),
        );
      }

      final profile = await docRef.get();
      final data = profile.data() ?? {};

      final bool profileCompleted =
          (data['profileCompleted'] as bool?) ?? false;
      final bool onboardingCompleted =
          (data['onboardingCompleted'] as bool?) ?? profileCompleted;

      // 4) Local flags
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('logged_in', true);
      await prefs.setBool('is_guest', false);
      await prefs.setBool('email_verified', true);
      await prefs.setBool('profile_completed', profileCompleted);
      await prefs.setBool('onboarding_completed', onboardingCompleted);

      if (!mounted) return;

      // 5) Route
      //    🚫 If onboarding/profile not completed → force onboarding
      if (!profileCompleted || !onboardingCompleted) {
        Navigator.pushReplacementNamed(context, Routes.onboardingStart);
      } else {
        Navigator.pushReplacementNamed(context, Routes.home);
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Sign in failed';
      switch (e.code) {
        case 'invalid-email':
          message = 'Invalid email address.';
          break;
        case 'user-not-found':
          message = 'No user found for that email.';
          break;
        case 'wrong-password':
          message = 'Incorrect password.';
          break;
        case 'user-disabled':
          message = 'This user account has been disabled.';
          break;
        case 'too-many-requests':
          message = 'Too many attempts. Try again later.';
          break;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = emailCtrl.text.trim();
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

    if (email.isEmpty || !re.hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a valid email above to reset your password.',
          ),
        ),
      );
      return;
    }

    setState(() => _resetting = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset link sent to $email')),
      );
    } on FirebaseAuthException catch (e) {
      String message = 'Could not send reset email';
      switch (e.code) {
        case 'invalid-email':
          message = 'Invalid email address.';
          break;
        case 'user-not-found':
          message = 'No user found for that email.';
          break;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error: $e')),
      );
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blackTextTheme = Theme.of(context)
        .textTheme
        .apply(bodyColor: Colors.black, displayColor: Colors.black);

    return Scaffold(
      backgroundColor: AppColors.green,
      body: SafeArea(
        child: Theme(
          data: Theme.of(context).copyWith(textTheme: blackTextTheme),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // back
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    onPressed: () => Navigator.pushReplacementNamed(
                      context,
                      Routes.welcome,
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // header
                Column(
                  children: const [
                    Image(
                      image: AssetImage('assets/logo_white.png'),
                      height: 90,
                    ),
                    SizedBox(height: 8),
                    Text(
                      "DoraRide",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      "Welcome back! Let’s get you on the road again.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

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
                      icon: Icon(
                        _showPass
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.grey[700],
                      ),
                      onPressed: () =>
                          setState(() => _showPass = !_showPass),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Forgot password
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _resetting ? null : _forgotPassword,
                    icon: _resetting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.lock_reset_rounded),
                    label: const Text('Forgot password?'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _login,
                    child: _submitting
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text("Signing in…"),
                            ],
                          )
                        : const Text("Continue"),
                  ),
                ),
                const SizedBox(height: 14),

                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pushReplacementNamed(
                      context,
                      Routes.register,
                    ),
                    child: const Text("Create an account"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
