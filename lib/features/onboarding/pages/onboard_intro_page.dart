// lib/features/onboarding/pages/onboard_intro_page.dart

import 'package:flutter/material.dart';
import 'package:doraride_appp/features/onboarding/widgets/onboarding_scaffold.dart';
import '../../../app_router.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class OnboardIntroPage extends StatelessWidget {
  const OnboardIntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ Responsive image size based on device height
    final screenHeight = MediaQuery.of(context).size.height;
    final imageHeight = screenHeight * 0.30; // ~30% of screen
    final clampedImageHeight =
        imageHeight.clamp(150.0, 260.0); // min 150, max 260

    return OnboardingScaffold(
      showBackButton: false,

      // ✅ First line (white, bold, large) – shown by scaffold
      title: "Before you get started, here are 3 things to know",
      subtitle: null,

      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Second line – slightly smaller & more compact for mobiles
          Text(
            "We believe in making shared journeys easy and enjoyable! "
            "As you prepare to join, keep these important guidelines in mind.",
            style: const TextStyle(
              fontSize: 18, // a bit smaller for small screens
              fontWeight: FontWeight.bold,
              color: _kThemeBlue,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),

          // Image – responsive height
          Center(
            child: SizedBox(
              height: clampedImageHeight,
              child: Image.asset(
                'assets/onboard_intro1.png',
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
                        Icons.playlist_add_check,
                        size: 60,
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
        Navigator.of(context).pushNamed(Routes.onboardCommunity);
      },
    );
  }
}
