import 'package:flutter/material.dart';

class RefundAndPaymentPolicyPage extends StatelessWidget {
  const RefundAndPaymentPolicyPage({super.key});

  static const Color _kNavy = Color(0xFF180D3B);
  static const Color _kGreen = Color(0xFF279C56);

  static const String _text = '''
REFUND & PAYMENT POLICY
Last updated: December 14, 2025

This Refund & Payment Policy (“Policy”) explains how payments, wallet balances, cancellations, refunds, and chargebacks work on DoraRide (“DoraRide”, “we”, “our”, “us”). This Policy applies to our mobile apps (Android/iOS), website, and related services (collectively, the “Services”).

1) Payments & Processing
• DoraRide may offer payments through third-party providers (for example, Stripe) and may also offer in-app wallet features.
• You authorize DoraRide and our payment partners to process payments you make through the Services.
• We do not store your full card details. Card processing is handled by our payment partners.

2) Pricing, Fees & Taxes
• Ride prices, platform fees, and other charges (if any) are shown before you confirm a booking or payment.
• Taxes or government charges may apply depending on your location and the nature of the transaction.
• If pricing is clearly displayed incorrectly due to a technical error, DoraRide may cancel the affected transaction and refund eligible amounts.

3) Wallet (If Available)
• Wallet balance (if enabled) may be used to pay for eligible Services.
• Wallet “top-ups” may be subject to verification, limits, and anti-fraud checks.
• Wallet balance is not a bank account and does not earn interest.

4) Cancellations & Refund Eligibility (General Rules)
Refund eligibility depends on:
• Whether the ride was cancelled (and by whom),
• Timing of cancellation,
• Whether the ride started or was completed,
• Applicable cancellation or no-show policies,
• Payment status and provider rules.

Important:
• Some fees may be non-refundable (for example: platform fees, payment processing fees) where allowed by law.

5) Rider Cancellations
• If a rider cancels before the ride starts, a refund may be issued depending on the cancellation timing and policy rules.
• Late cancellations and repeated cancellations may result in reduced refunds, additional fees, or account limits.

6) Driver Cancellations
• If a driver cancels, DoraRide may issue a full or partial refund to the rider depending on the ride status.
• Drivers with excessive cancellations may face reduced visibility, temporary suspension, or deactivation (see Driver Cancellation Policy).

7) No-Show & Missed Pickup
A “no-show” may be recorded when:
• A rider does not arrive within a reasonable time and cannot be reached, or
• A driver does not arrive within a reasonable time and cannot be reached.
Refund decisions for no-shows depend on trip evidence, communication logs (if available), and applicable policy rules.

8) Completed Rides / Disputes
• If a ride is completed, refunds are not guaranteed.
• If you believe you were charged incorrectly, contact support with trip details. We may request evidence and review logs.

9) Chargebacks & Payment Disputes
• If you file a chargeback with your bank/card provider, DoraRide may pause your account while we investigate.
• Fraudulent or abusive chargebacks may lead to account suspension or termination.
• If a chargeback is decided in DoraRide’s favor, you may remain responsible for the amount owed.

10) Refund Method & Timing
• Approved refunds are usually returned to the original payment method when possible.
• Some refunds may be issued to wallet balance (where supported), especially if the original method is unavailable.
• Timing depends on payment provider and bank processing (often several business days).

11) Fraud, Abuse, and Violations
We may deny refunds if we detect:
• Fraudulent activity,
• Platform manipulation,
• Abuse of refund requests,
• Violations of Terms & Conditions.

12) Contact Support
If you have questions or want to request a refund review, contact:
Email: support@doraride.com
(Optionally add your company address here)
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kGreen,
      appBar: AppBar(
        title: const Text('Refund & Payment Policy'),
        backgroundColor: _kNavy,
        foregroundColor: Colors.white,
      ),
      body: SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                _text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.65,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
