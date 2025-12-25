// lib/features/onboarding/pages/profile_gender_page.dart

import 'package:flutter/material.dart';
import '../../../app_router.dart'; // For Routes.profileSetupUse
import 'profile_age_page.dart'; // Import ProfileSetupArgs

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56); // App Green

class ProfileGenderPage extends StatefulWidget {
  const ProfileGenderPage({super.key});

  @override
  State<ProfileGenderPage> createState() => _ProfileGenderPageState();
}

class _ProfileGenderPageState extends State<ProfileGenderPage> {
  String? _selectedGender;
  final List<String> _options = const ['Male', 'Female', 'Other'];

  ProfileSetupArgs? _prevArgs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is ProfileSetupArgs) {
      _prevArgs = args;
    }
  }

  void _onOptionSelected(String option) {
    setState(() {
      _selectedGender = option;
    });
  }

  void _onNext() {
    if (_selectedGender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your gender to continue.'),
        ),
      );
      return;
    }

    final args = ProfileSetupArgs(
      dob: _prevArgs?.dob,
      gender: _selectedGender,
    );
    Navigator.of(context).pushNamed(
      Routes.profileSetupUse,
      arguments: args,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kThemeGreen,
      appBar: AppBar(
        backgroundColor: _kThemeGreen,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          'Profile set-up',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Text(
                'What is your gender?',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
              ),
              const SizedBox(height: 10),

              // Subtitle
              const Text(
                "DoraRide members feel more comfortable knowing a bit about "
                "who they're sharing a ride with.",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _kThemeBlue,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),

              // Illustration
              const Center(child: _ShapeIllustrationPlaceholder()),
              const SizedBox(height: 20),

              // Options
              ..._options.map(
                (option) => _GenderOptionButton(
                  label: option,
                  isSelected: _selectedGender == option,
                  onTap: () => _onOptionSelected(option),
                ),
              ),

              const SizedBox(height: 24),

              // Next button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _selectedGender != null ? _onNext : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kThemeBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'Next',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// Reusable widget for the Male/Female/Other buttons
class _GenderOptionButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _GenderOptionButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          side: BorderSide(
            color: isSelected ? Colors.white : Colors.white54,
            width: isSelected ? 2 : 1,
          ),
          backgroundColor:
              isSelected ? _kThemeBlue.withOpacity(0.9) : Colors.white12,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// Placeholder for the custom shape illustration
class _ShapeIllustrationPlaceholder extends StatelessWidget {
  const _ShapeIllustrationPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(100),
      ),
      child: const Center(
        child: Icon(Icons.person, size: 72, color: Colors.white),
      ),
    );
  }
}
