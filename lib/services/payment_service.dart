// lib/services/payment_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Key used to store mock payment secret
const String _kPaymentSecretKey = 'payment_client_secret';
// Mock value for a client secret/token
const String _kMockClientSecret = 'mock_stripe_cs_12345ABCDEF';

class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  // --- Initialization and Security ---
  
  /// Ensures the mock client secret is securely stored (simulating setup).
  Future<void> initializeMockPaymentGateway() async {
    // Only store if it doesn't exist (simulates first-time setup)
    final existing = await _secureStorage.read(key: _kPaymentSecretKey);
    if (existing == null) {
      await _secureStorage.write(key: _kPaymentSecretKey, value: _kMockClientSecret);
      if (kDebugMode) {
        print('🔐 Mock payment secret stored securely.');
      }
    }
  }

  /// Retrieves the mock client secret.
  Future<String?> getClientSecret() async {
    return _secureStorage.read(key: _kPaymentSecretKey);
  }
  
  // --- Payment Execution (Mock) ---

  /// Simulates payment processing using the mock secret and returns success/failure.
  /// 
  /// In a real app, this would involve calling a backend endpoint which then 
  /// interacts with Stripe/PayPal using the client token.
  /// 
  /// [amount] is the amount in dollars to charge the user now.
  Future<bool> processPayment(double amount, {String? paymentMethodId}) async {
    final clientSecret = await getClientSecret();
    
    if (clientSecret == null) {
      throw Exception('Payment gateway not initialized.');
    }
    
    if (amount <= 0.0) {
      // Free booking (e.g., balance covers it)
      return true;
    }
    
    // Simulate network delay and payment success based on amount
    await Future.delayed(const Duration(seconds: 1));

    if (amount < 1.0) {
      // Simulate failure for tiny payments (Mock logic)
      return false;
    }

    if (kDebugMode) {
       print('✅ PAYMENT SUCCESS: Charged \$${amount.toStringAsFixed(2)} using secret: $clientSecret');
    }
    
    return true;
  }
}