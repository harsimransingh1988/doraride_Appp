// lib/features/profile/preferences_page.dart

import 'package:flutter/material.dart';

class PreferencesPage extends StatefulWidget {
  const PreferencesPage({super.key});

  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  static const kGreen = Color(0xFF279C56);
  static const kNavy = Color(0xFF180D3B); // Added Navy for consistent button styling

  bool smokingAllowed = false;
  bool chatty = true;
  bool petsAllowed = true;
  bool musicOk = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kGreen, // App Green background
      appBar: AppBar(
        title: const Text('Preferences'),
        backgroundColor: kGreen, // App Green AppBar
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Your travel preferences help match you with better rides.',
            style: TextStyle(color: Colors.white, fontSize: 16), // White text
          ),
          const SizedBox(height: 20),
          _switch('Allow smoking', smokingAllowed, (v) => setState(() => smokingAllowed = v)),
          _switch('Chatty driver/passenger', chatty, (v) => setState(() => chatty = v)),
          _switch('Pets allowed', petsAllowed, (v) => setState(() => petsAllowed = v)),
          _switch('Play music during rides', musicOk, (v) => setState(() => musicOk = v)),
          const SizedBox(height: 20),
          _saveBtn(context),
        ],
      ),
    );
  }

  Widget _switch(String title, bool value, ValueChanged<bool> onChanged) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15), // Subtle white tint for contrast
          borderRadius: BorderRadius.circular(12),
        ),
        child: SwitchListTile(
          value: value,
          onChanged: onChanged,
          title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)), // White text
          activeColor: kNavy, // Using Navy for active switch color
        ),
      );

  Widget _saveBtn(BuildContext context) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Preferences saved successfully'))),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: kNavy, // App Navy text
          ),
          child: const Text('Save preferences'),
        ),
      );
}