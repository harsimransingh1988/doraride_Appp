// lib/features/onboarding/pages/onboard_early_page.dart

import 'package:flutter/material.dart';
import 'package:doraride_appp/features/onboarding/widgets/onboarding_scaffold.dart';
import '../../../app_router.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class OnboardEarlyPage extends StatelessWidget {
  const OnboardEarlyPage({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ Responsive sizing
    final screenHeight = MediaQuery.of(context).size.height;
    final imageHeight = screenHeight * 0.28; // ~28% of screen
    final clampedImageHeight =
        imageHeight.clamp(150.0, 240.0); // min 150, max 240

    return OnboardingScaffold(
      showBackButton: true,

      // First line (white, bold, large) – handled by scaffold
      title: "Arrive a little early for a smooth trip",
      subtitle: null,

      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Second line – slightly smaller for better fit
          Text(
            "Showing up a few minutes before departure makes for a stress-free ride. "
            "It helps keep things running smoothly and avoids unnecessary delays.",
            style: const TextStyle(
              fontSize: 18, // was 22
              fontWeight: FontWeight.bold,
              color: _kThemeBlue,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),

          // Responsive image
          Center(
            child: SizedBox(
              height: clampedImageHeight,
              child: Image.asset(
                'assets/onboard_early.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: clampedImageHeight,
                    width: clampedImageHeight,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.access_time_filled,
                        size: 70,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),

      buttonText: "Next",
      onNext: () {
        Navigator.of(context).pushNamed(Routes.onboardAgree);
      },
    );
  }
}
