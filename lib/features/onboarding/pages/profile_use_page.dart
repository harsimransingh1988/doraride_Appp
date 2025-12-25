// lib/features/onboarding/pages/profile_use_page.dart

import 'package:flutter/material.dart';
import '../../../app_router.dart'; // For Routes.profileSetupPicture
import 'profile_age_page.dart'; // Import ProfileSetupArgs

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56); // App Green

class ProfileUsePage extends StatefulWidget {
  const ProfileUsePage({super.key});

  @override
  State<ProfileUsePage> createState() => _ProfileUsePageState();
}

class _ProfileUsePageState extends State<ProfileUsePage> {
  String? _selectedUse;
  final List<String> _options = const [
    'Mostly as a driver',
    'Mostly as a passenger'
  ];
  
  // Field to hold arguments passed from the previous page
  ProfileSetupArgs? _prevArgs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Retrieve arguments safely
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is ProfileSetupArgs) {
      _prevArgs = args;
    }
  }

  void _onOptionSelected(String option) {
    setState(() => _selectedUse = option);
  }

  void _onNext() {
    if (_selectedUse == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your primary usage role to continue.'),
        ),
      );
      return;
    }

    // Build updated args with usage
    final updatedArgs = ProfileSetupArgs(
      dob: _prevArgs?.dob,
      gender: _prevArgs?.gender,
      usage: _selectedUse, // keep full label text
    );

    if (_selectedUse == 'Mostly as a driver') {
      // 🔐 Driver must complete licence verification first
      Navigator.of(context).pushNamed(
        Routes.driverLicense,
        arguments: updatedArgs,
      );
    } else {
      // 🧍 Passenger: now also goes to phone page before picture
      Navigator.of(context).pushNamed(
        Routes.profileSetupPhone,
        arguments: updatedArgs,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kThemeGreen,
      appBar: AppBar(
        backgroundColor: _kThemeGreen,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Profile set-up', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ First line: white, bold, large
              Text(
                'How will you use DoraRide?',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
              ),
              const SizedBox(height: 10),

              // ✅ Second line: blue, bold, medium
              const Text(
                'Are you mostly driving or riding as a passenger? '
                'This helps us send you the most relevant info!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _kThemeBlue,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),

              // Centered illustration (placeholder)
              const Center(child: _UseIllustrationPlaceholder()),
              const SizedBox(height: 30),

              // Option Buttons
              ..._options.map(
                (option) => _UsageOptionButton(
                  label: option,
                  isSelected: _selectedUse == option,
                  onTap: () => _onOptionSelected(option),
                ),
              ),

              const SizedBox(height: 30),

              // Next Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _selectedUse != null ? _onNext : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kThemeBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'Next',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Reusable option button
class _UsageOptionButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _UsageOptionButton({
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

// Placeholder for the custom car/city illustration
class _UseIllustrationPlaceholder extends StatelessWidget {
  const _UseIllustrationPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      width: 240,
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(Icons.directions_car, size: 80, color: Colors.white),
      ),
    );
  }
}
