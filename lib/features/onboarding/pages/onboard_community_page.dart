// lib/features/onboarding/pages/onboard_community_page.dart

import 'package:flutter/material.dart';
import 'package:doraride_appp/features/onboarding/widgets/onboarding_scaffold.dart';
import '../../../app_router.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class OnboardCommunityPage extends StatelessWidget {
  const OnboardCommunityPage({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ Responsive helpers
    final size = MediaQuery.of(context).size;
    final screenHeight = size.height;
    final screenWidth = size.width;

    // Limit content width on big screens (web / tablet)
    final maxContentWidth = screenWidth > 600 ? 600.0 : screenWidth;

    // Responsive image height
    final imageHeight =
        (screenHeight * 0.25).clamp(170.0, 230.0); // min 170, max 230

    // Dynamic spacing (small screens get smaller gaps)
    final topSpacing = screenHeight * 0.015; // ~1.5% of height
    final middleSpacing = screenHeight * 0.025;
    final bottomSpacing = screenHeight * 0.03;

    return OnboardingScaffold(
      showBackButton: true,

      // ✅ First line (white, bold, large)
      title: "We’re a community — not a taxi service",

      subtitle: null,

      content: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ Second line (blue, bold, slightly smaller for mobile)
              Text(
                "DoraRide connects real people to share rides and split travel costs fairly. "
                "It’s about trust, respect, and making travel better together.",
                style: const TextStyle(
                  fontSize: 18, // was 22
                  fontWeight: FontWeight.bold,
                  color: _kThemeBlue,
                  height: 1.4,
                ),
              ),
              SizedBox(height: middleSpacing),

              // Image section (responsive)
              Center(
                child: Image.asset(
                  'assets/onboard_community.png',
                  height: imageHeight,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 200,
                      width: 200,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.people_alt_rounded,
                          size: 70,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: bottomSpacing),
            ],
          ),
        ),
      ),

      buttonText: "Next",
      onNext: () {
        Navigator.of(context).pushNamed(Routes.onboardPayments);
      },
    );
  }
}
