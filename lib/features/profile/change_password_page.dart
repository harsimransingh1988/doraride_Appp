// lib/features/profile/change_password_page.dart

import 'package:flutter/material.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  static const kGreen = Color(0xFF279C56);
  static const kNavy = Color(0xFF180D3B);

  final current = TextEditingController(text: '********');

  // ✅ FIX: these must start blank so user can type their own password
  final newPass = TextEditingController();
  final confirm = TextEditingController();

  bool show = false;

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white, // White fill for text input contrast
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kGreen, // App Green background
      appBar: AppBar(
        title: const Text('Change password'),
        backgroundColor: kGreen, // App Green AppBar
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: current,
            obscureText: !show,
            decoration: _dec('Current password'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: newPass,
            obscureText: !show,
            decoration: _dec('New password'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirm,
            obscureText: !show,
            decoration: _dec('Confirm new password'),
          ),
          Row(
            children: [
              Checkbox(
                value: show,
                onChanged: (v) => setState(() => show = v ?? false),
              ),
              const Text(
                'Show passwords',
                style: TextStyle(color: Colors.white), // White text
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Password changed successfully')),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: kNavy, // App Navy text
            ),
            child: const Text('Save password'),
          ),
        ],
      ),
    );
  }
}
