// lib/features/onboarding/pages/profile_notifications_page.dart

import 'package:flutter/material.dart';
import '../../../app_router.dart'; // For Routes.profileSetupCompleted

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56); // App Green

class ProfileNotificationsPage extends StatefulWidget {
  const ProfileNotificationsPage({super.key});

  @override
  State<ProfileNotificationsPage> createState() => _ProfileNotificationsPageState();
}

class _ProfileNotificationsPageState extends State<ProfileNotificationsPage> {
  bool _push = true;
  bool _email = true;
  bool _sms = false;

  void _onNext() {
    // Add persistence if needed; for now just continue
    Navigator.of(context).pushNamed(Routes.profileSetupCompleted);
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
                'Stay in the loop',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
              ),
              const SizedBox(height: 10),

              // ✅ Second line: blue, bold, medium
              const Text(
                'Choose how you’d like to hear from DoraRide.',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _kThemeBlue,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),

              // Centered illustration (placeholder)
              const Center(child: _BellIllustrationPlaceholder()),
              const SizedBox(height: 30),

              // Toggles (styled for dark-on-green)
              _notifyTile(
                title: 'Push notifications',
                subtitle: 'Trip reminders, messages, and updates',
                value: _push,
                onChanged: (v) => setState(() => _push = v),
              ),
              const SizedBox(height: 8),
              _notifyTile(
                title: 'Email notifications',
                subtitle: 'Booking receipts and account notices',
                value: _email,
                onChanged: (v) => setState(() => _email = v),
              ),
              const SizedBox(height: 8),
              _notifyTile(
                title: 'SMS notifications',
                subtitle: 'Time-critical alerts (optional)',
                value: _sms,
                onChanged: (v) => setState(() => _sms = v),
              ),

              const SizedBox(height: 30),

              // Next button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _onNext,
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

  Widget _notifyTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        activeColor: Colors.white,
        activeTrackColor: Colors.white54,
        inactiveThumbColor: Colors.white70,
        inactiveTrackColor: Colors.white24,
        value: value,
        onChanged: onChanged,
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

class _BellIllustrationPlaceholder extends StatelessWidget {
  const _BellIllustrationPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      width: 220,
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(Icons.notifications_active, size: 80, color: Colors.white),
      ),
    );
  }
}
