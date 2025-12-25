// lib/services/logout_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_router.dart';

class LogoutService {
  static Future<void> fullLogout(BuildContext context) async {
    try {
      // Clear local login flags
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('logged_in', false);
      await prefs.setBool('is_guest', false);
      await prefs.setBool('email_verified', false);
      await prefs.setBool('profile_completed', false);
      await prefs.setBool('onboarding_completed', false);

      // Firebase sign-out
      await FirebaseAuth.instance.signOut();

      // Go to Landing and clear stack
      if (!context.mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        Routes.landing,
        (route) => false,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to log out: $e')),
      );
    }
  }
}
