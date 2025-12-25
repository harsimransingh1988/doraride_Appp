// lib/services/notification_service.dart

// Note: This is a MOCK implementation to resolve compilation errors 
// due to missing 'firebase_messaging' dependency.
// For production, you must add firebase_messaging to pubspec.yaml and 
// use the actual Firebase code.

import 'package:flutter/material.dart';

// Stub for FirebaseMessaging types
class RemoteMessage {
  final Map<String, dynamic> data;
  const RemoteMessage({required this.data});
}

// Stub for FirebaseMessaging class
class FirebaseMessaging {
  static FirebaseMessaging get instance => FirebaseMessaging._();
  FirebaseMessaging._();

  static final Stream<RemoteMessage> onMessage = const Stream.empty();
  static final Stream<RemoteMessage> onMessageOpenedApp = const Stream.empty();

  Future<String?> getToken() async => 'MOCK_FCM_TOKEN';
}


class NotificationService {
  // Mock internal state for the compiler
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  
  static Future<void> initialize() async {
    debugPrint("NotificationService: Initialized (MOCK)");
    // Mock listeners to prevent compilation errors
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);
  }

  // NOTE: The main fix is here, ensuring all called methods exist.
  static Future<void> sendBookingNotification({
    required String recipientId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    // MOCK: In a real app, this sends a notification via a backend Cloud Function
    debugPrint('MOCK NOTIFICATION SENT: To $recipientId. Title: $title, Body: $body');
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('MOCK FOREGROUND MESSAGE RECEIVED: ${message.data}');
  }

  static void _handleBackgroundMessage(RemoteMessage message) {
    debugPrint('MOCK BACKGROUND MESSAGE RECEIVED: ${message.data}');
  }
}