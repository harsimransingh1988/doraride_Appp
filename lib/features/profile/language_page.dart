// lib/features/profile/language_page.dart

import 'package:flutter/material.dart';

class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key});

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
  static const kGreen = Color(0xFF279C56);
  static const kNavy = Color(0xFF180D3B);

  String lang = 'English';
  final langs = const ['English', 'French', 'Hindi', 'Punjabi', 'Spanish'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kGreen, // App Green background
      appBar: AppBar(
        title: const Text('Language'),
        backgroundColor: kGreen, // App Green AppBar
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: lang,
              items: langs.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
              onChanged: (v) => setState(() => lang = v ?? lang),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white, // White fill for text input contrast
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Language set to $lang successfully'))),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: kNavy, // App Navy text
              ),
              child: const Text('Save language'),
            ),
          ],
        ),
      ),
    );
  }
}