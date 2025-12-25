// lib/main.dart
import 'dart:async';
import 'dart:ui' show PlatformDispatcher; // ✅ ADDED (needed for global error capture)
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_router.dart';
import 'theme.dart';
import 'features/auth/landing_page.dart';
import 'features/home/home_shell.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter_stripe/flutter_stripe.dart';
import 'services/user_sync_service.dart';

// 🔔 Notifications
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/push_notification_service.dart';

// ⭐ Referrals
import 'common/repos/referral_repository.dart';

// ⭐ Guest Guard
import 'services/guest_guard.dart';

// 🔒 Banned user gate (global wrapper)
import 'widgets/banned_user_gate.dart';

// ✅ ADD THESE IMPORTS HERE (at the top with other imports)
import 'features/auth/email_verification_page.dart';
import 'features/onboarding/pages/onboard_intro_page.dart';

// ✅ Crashlytics (mobile only)
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; // ✅ ADDED

const String kStripePublishableKey =
    'pk_live_51RmOQ602QRDPjVXD4KPxyI3jYNwgGcSfr9qK37P02yRrhAXPmy4L7EjeuUBK7LGIuh5rUPsdWzhQmOIvYEO277vl00pjaY5AB0';

// Background handler (mobile only)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

Future<void> main() async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // ✅ FIRST: Firebase init (so any later error can safely log to Crashlytics)
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Stripe + background handler only on mobile
    if (!kIsWeb) {
      Stripe.publishableKey = kStripePublishableKey;
      await Stripe.instance.applySettings();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }

    // ✅ Crashlytics setup (MOBILE ONLY)
    // Crashlytics is not supported on web, so we guard it.
    if (!kIsWeb) {
      // Capture Flutter framework errors
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;

      // Capture async/platform errors
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(
          error,
          stack,
          fatal: true,
        );
        return true;
      };
    }

    // ⭐ Start UI immediately!
    runApp(const DoraRideApp());

    // ⭐ Run heavy/slow tasks AFTER UI shows
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runBackgroundStartupTasks();
    });
  }, (error, stack) async {
    print('❌ Uncaught error: $error\n$stack');

    // ✅ Send uncaught zone errors to Crashlytics (MOBILE ONLY)
    if (!kIsWeb) {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        fatal: true,
      );
    }
  });
}

/// ⭐ Moves everything heavy OUT of main()
Future<void> _runBackgroundStartupTasks() async {
  try {
    // ⭐ Load guest mode flag
    await GuestGuard.initialize();

    await PushNotificationService.initialize();
    PushNotificationService.listenTokenRefresh();

    // Optional – Firestore check (not required for launch)
    await FirebaseFirestore.instance.collection('trips').limit(1).get();

    // Start syncing user data
    UserSyncService.instance.start();
  } catch (e) {
    print('⚠️ Startup background error: $e');
  }
}

/// ⭐ Just wait for Firebase to restore auth state.
/// IMPORTANT: No anonymous sign-in here anymore.
Future<void> _ensureAuthReady() async {
  final auth = FirebaseAuth.instance;

  // Wait for the first auth state event (could be null or a real user)
  await auth.authStateChanges().firstWhere((_) => true);
}

/// ⭐ Referral logic handled after auth
Future<void> _handleReferralIfPresent() async {
  final uri = Uri.base;
  final code = uri.queryParameters['code'];
  if (code == null || code.isEmpty) return;

  final repo = ReferralRepository();
  await repo.redeemInstall(code);
}

class DoraRideApp extends StatelessWidget {
  const DoraRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DoraRide',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      onGenerateRoute: AppRouter.onGenerateRoute,
      // ✅ GLOBAL ban gate – wraps EVERY screen
      builder: (context, child) =>
          BannedUserGate(child: child ?? const SizedBox.shrink()),
      home: const _LaunchDecider(),
    );
  }
}

class _LaunchDecider extends StatefulWidget {
  const _LaunchDecider({super.key});
  @override
  State<_LaunchDecider> createState() => _LaunchDeciderState();
}

class _LaunchDeciderState extends State<_LaunchDecider> {
  bool _loading = true;
  bool _loggedInFlag = false;
  bool _emailVerifiedFlag = false;
  bool _profileSetupCompleteFlag = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final prefs = await SharedPreferences.getInstance();

    // ⭐ Read guest flag
    final isGuest = prefs.getBool('is_guest') ?? false;

    // ⭐ Let Firebase restore auth state
    await _ensureAuthReady();
    await _handleReferralIfPresent();

    final auth = FirebaseAuth.instance;
    final currentUser = auth.currentUser;

    // ✅ Check if user is logged in (not guest, not anonymous)
    final bool isLoggedIn =
        !isGuest && currentUser != null && !currentUser.isAnonymous;

    if (isLoggedIn) {
      // Check email verification status
      final bool isEmailVerified = currentUser?.emailVerified ?? false;

      // Check profile setup completion from Firestore
      bool isProfileSetupComplete = false;

      try {
        if (currentUser != null) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();

          if (userDoc.exists) {
            final data = userDoc.data() ?? {};
            final bool profileCompleted =
                (data['profileCompleted'] as bool?) ?? false;
            final bool onboardingCompleted =
                (data['onboardingCompleted'] as bool?) ?? false;
            isProfileSetupComplete = profileCompleted && onboardingCompleted;
          }
        }
      } catch (e) {
        print('⚠️ Error checking Firestore profile: $e');
        // Fallback to SharedPreferences if Firestore fails
        isProfileSetupComplete = prefs.getBool('profile_setup_complete') ?? false;
      }

      // Update flags in SharedPreferences
      await prefs.setBool('logged_in', true);
      await prefs.setBool('email_verified', isEmailVerified);
      await prefs.setBool('profile_setup_complete', isProfileSetupComplete);

      if (!mounted) return;
      setState(() {
        _loggedInFlag = true;
        _emailVerifiedFlag = isEmailVerified;
        _profileSetupCompleteFlag = isProfileSetupComplete;
        _loading = false;
      });
    } else {
      // Not logged in - clear flags
      await prefs.setBool('logged_in', false);
      await prefs.setBool('email_verified', false);
      await prefs.setBool('profile_setup_complete', false);

      if (!mounted) return;
      setState(() {
        _loggedInFlag = false;
        _emailVerifiedFlag = false;
        _profileSetupCompleteFlag = false;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.green,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    // ✅ Decision tree based on authentication state
    if (!_loggedInFlag) {
      // Not logged in → landing / login / guest selection
      return const LandingPage();
    } else if (!_emailVerifiedFlag) {
      // Logged in but email not verified → email verification page
      // Pass email to verification page
      final currentUser = FirebaseAuth.instance.currentUser;
      final email = currentUser?.email ?? '';

      // Use EmailVerificationPage widget directly
      return EmailVerificationPage(
        email: email,
        nextRoute: Routes.onboardingStart,
      );
    } else if (!_profileSetupCompleteFlag) {
      // Email verified but profile not set up → onboarding flow
      return const OnboardIntroPage();
    } else {
      // All conditions met → HomeShell (ban check happens in BannedUserGate)
      return const HomeShell();
    }
  }
}
