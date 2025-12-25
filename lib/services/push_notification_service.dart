// lib/services/push_notification_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  // ----------------------------------------------------------
  // 🔑 YOUR WEB VAPID KEY (from Firebase console – Web Push)
  // ----------------------------------------------------------
  static const String _kWebVapidKey =
      'BO4Ct3x9uEhsPJHXO34-AFOrB92IFDQfONeW_nha0899ealiIxnzsyNkqIKc5n0RzFagGq8xUvC1h7t-x-xdLWY';

  // ----------------------------------------------------------
  // 🚀 INITIALIZE PUSH NOTIFICATIONS
  // ----------------------------------------------------------
  static Future<void> initialize() async {
    print("🔔 Initializing Push Notification Service...");

    // 1. Request notification permission (Web + Mobile)
    final NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    print("🔔 FCM permission: ${settings.authorizationStatus}");

    // 2. Get token for current user & save to Firestore
    await _printAndSaveToken();

    // 3. Listener for incoming foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("📩 Foreground FCM received:");
      print("➡️ Title: ${message.notification?.title}");
      print("➡️ Body: ${message.notification?.body}");
      print("➡️ Data: ${message.data}");
    });

    // 4. Listener when user taps notification (opens app)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print("📲 Notification clicked!");
      print("➡️ Data: ${message.data}");
    });
  }

  // ----------------------------------------------------------
  // 🧪 Get token & save into Firestore
  //  - fcm_token  : single latest token (easy to inspect)
  //  - fcmTokens[]: array used by backend Cloud Functions
  // ----------------------------------------------------------
  static Future<void> _printAndSaveToken() async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      print("⚠️ No Firebase Auth user logged in. Skipping FCM token save.");
      return;
    }

    final String? token = await _messaging.getToken(
      vapidKey: kIsWeb ? _kWebVapidKey : null,
    );

    if (token == null) {
      print("❌ Failed to get FCM token (null).");
      return;
    }

    print("📬 FCM token = $token");

    await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .set({
          // latest token (string)
          "fcm_token": token,
          // array of tokens (what backend reads)
          "fcmTokens": FieldValue.arrayUnion([token]),
        }, SetOptions(merge: true));

    print("📨 Saved FCM token for ${user.uid}");
  }

  // ----------------------------------------------------------
  // 🔁 Token refresh stream
  // ----------------------------------------------------------
  static void listenTokenRefresh() {
    _messaging.onTokenRefresh.listen((String newToken) async {
      print("♻️ FCM token refreshed: $newToken");

      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print("⚠️ No user during token refresh; skipping Firestore update.");
        return;
      }

      await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .set({
            "fcm_token": newToken,
            "fcmTokens": FieldValue.arrayUnion([newToken]),
          }, SetOptions(merge: true));

      print("💾 Updated refreshed token in Firestore for ${user.uid}");
    });
  }
}
