// lib/features/onboarding/pages/onboard_payments_page.dart

import 'package:flutter/material.dart';
import 'package:doraride_appp/features/onboarding/widgets/onboarding_scaffold.dart';
import '../../../app_router.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class OnboardPaymentsPage extends StatelessWidget {
  const OnboardPaymentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      showBackButton: true,

      // ✅ First line (white, bold, large)
      title: "Payments are simple and transparent",

      subtitle: null, // nothing above headline

      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Second line (blue, bold, medium)
          Text(
            "Riders and drivers share the cost of each trip fairly. "
            "DoraRide makes payments secure, simple, and clear for everyone.",
            style: const TextStyle(
              fontSize: 22, // medium
              fontWeight: FontWeight.bold,
              color: _kThemeBlue,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 40),

          // Image / Illustration
          Center(
            child: Image.asset(
              'assets/onboard_payments.png',
              height: 230,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  height: 200,
                  width: 200,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Icon(Icons.attach_money_rounded,
                        size: 70, color: Colors.white),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),

      buttonText: "Next",
      onNext: () {
        Navigator.of(context).pushNamed(Routes.onboardEarly);
      },
    );
  }
}
