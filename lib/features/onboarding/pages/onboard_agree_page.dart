// lib/features/onboarding/pages/onboard_agree_page.dart

import 'package:flutter/material.dart';
import 'package:doraride_appp/features/onboarding/widgets/onboarding_scaffold.dart';
import '../../../app_router.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class OnboardAgreePage extends StatelessWidget {
  const OnboardAgreePage({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ Responsive helpers
    final size = MediaQuery.of(context).size;
    final screenHeight = size.height;
    final screenWidth = size.width;

    // Limit content width on big screens
    final maxContentWidth = screenWidth > 600 ? 600.0 : screenWidth;

    // Illustration size relative to height
    final illustrationSize =
        (screenHeight * 0.22).clamp(120.0, 180.0); // min 120, max 180

    // Dynamic spacing based on height
    final topSpacing = screenHeight * 0.015; // ~1.5% of height
    final middleSpacing = screenHeight * 0.02;
    final bottomSpacing = screenHeight * 0.03;

    return OnboardingScaffold(
      showBackButton: true,
      title: "Got it? Awesome!",
      subtitle: null,

      content: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top description (slightly smaller for mobile)
              const Text(
                "Here’s what makes DoraRide work best for everyone:",
                style: TextStyle(
                  fontSize: 18, // was 22
                  fontWeight: FontWeight.bold,
                  color: _kThemeBlue,
                  height: 1.4,
                ),
              ),
              SizedBox(height: topSpacing),

              // Bullet points
              _bullet(Icons.groups_rounded, "We’re carpoolers, not taxis or Uber"),
              SizedBox(height: middleSpacing),
              _bullet(Icons.attach_money_rounded,
                  "Payments go through DoraRide — no cash"),
              SizedBox(height: middleSpacing),
              _bullet(Icons.access_time_rounded,
                  "Arrive a little early to keep things running smoothly"),

              SizedBox(height: middleSpacing * 1.6),

              // Illustration in center
              Center(
                child: SizedBox(
                  width: illustrationSize,
                  height: illustrationSize,
                  child: const _AgreeIllustrationIcon(),
                ),
              ),

              SizedBox(height: bottomSpacing),

              // “I agree” text near bottom, wrapped nicely
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text.rich(
                    TextSpan(
                      text:
                          'By tapping "I agree," you’re joining a trusted carpool community and agreeing to our ',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13, // slightly smaller
                        height: 1.4,
                      ),
                      children: const [
                        TextSpan(
                          text: 'Terms of service',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                            color: Colors.white,
                          ),
                        ),
                        TextSpan(text: ' and '),
                        TextSpan(
                          text: 'Privacy Policy',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                            color: Colors.white,
                          ),
                        ),
                        TextSpan(text: '.'),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      buttonText: "Next",
      onNext: () => Navigator.of(context).pushNamed(Routes.profileSetupIntro),
    );
  }

  Widget _bullet(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32, // was 36
          height: 32,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: _kThemeBlue, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 16, // was 18
              color: Colors.white,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

// ✅ Centered illustration icon (size controlled from parent)
class _AgreeIllustrationIcon extends StatelessWidget {
  const _AgreeIllustrationIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white10,
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Icon(
          Icons.verified_rounded,
          color: Colors.white,
          size: 84,
        ),
      ),
    );
  }
}
