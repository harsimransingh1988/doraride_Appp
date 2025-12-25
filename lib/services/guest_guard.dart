// lib/services/guest_guard.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:doraride_appp/app_router.dart';

/// Central helper to block guests from doing certain actions.
class GuestGuard {
  static const _loggedInKey = 'logged_in';
  static const _isGuestKey = 'is_guest';

  /// Optional: called once on startup (we already do this in main).
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    // Just ensure keys exist; no heavy logic needed
    prefs.getBool(_loggedInKey);
    prefs.getBool(_isGuestKey);
  }

  /// Returns true if this run is a guest session.
  static Future<bool> isGuest() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool(_loggedInKey) ?? false;
    final isGuest = prefs.getBool(_isGuestKey) ?? false;
    // In your flow: guest => logged_in = true, is_guest = true
    return loggedIn && isGuest;
  }

  /// Returns true if user is logged in with a real account (not guest).
  static Future<bool> isRegisteredUser() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool(_loggedInKey) ?? false;
    final isGuest = prefs.getBool(_isGuestKey) ?? false;
    return loggedIn && !isGuest;
  }

  /// Internal helper: show popup and optionally send to welcome/register.
  static Future<void> _showGuestDialog(BuildContext context) async {
    final goToAuth = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Sign in required'),
            content: const Text(
              'You’re currently browsing as a guest.\n\n'
              'Please create an account or sign in to use this feature.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not now'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Register / Sign in'),
              ),
            ],
          ),
        ) ??
        false;

    if (goToAuth) {
      // Send them to the welcome/auth entry
      Navigator.of(context).pushNamed(Routes.welcome);
    }
  }

  /// Main API: run [onAllowed] only if user is a registered (non-guest) account.
  /// Otherwise show the guest popup.
  static Future<void> requireRegistered(
    BuildContext context, {
    required VoidCallback onAllowed,
  }) async {
    final ok = await isRegisteredUser();
    if (ok) {
      onAllowed();
      return;
    }
    await _showGuestDialog(context);
  }
}
