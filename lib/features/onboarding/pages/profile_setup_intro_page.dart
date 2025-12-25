// lib/features/onboarding/pages/profile_setup_intro_page.dart

import 'package:flutter/material.dart';
import 'package:doraride_appp/features/onboarding/widgets/onboarding_scaffold.dart';
import '../../../app_router.dart';

const _kThemeBlue = Color(0xFF180D3B);

class ProfileSetupIntroPage extends StatelessWidget {
  const ProfileSetupIntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      showBackButton: true,

      // Top (white, bold, large)
      title: "Let’s set up your profile!",
      subtitle: null,

      // Below title (blue, bold, medium) + centered image
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "This only takes a minute and helps build trust in the community.\n"
            "Tap Next to get started!",
            style: const TextStyle(
              fontSize: 22,          // medium
              fontWeight: FontWeight.bold,
              color: _kThemeBlue,    // DoraRide blue
              height: 1.4,
            ),
          ),
          const SizedBox(height: 36),

          Center(
            child: Image.asset(
              'assets/profile_setup_intro.png',
              height: 230,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  height: 180,
                  width: 280,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Icon(Icons.verified_user, size: 72, color: Colors.white),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),

      buttonText: "Next",
      onNext: () => Navigator.of(context).pushNamed(Routes.profileSetupAge),
    );
  }
}
