// lib/features/profile/driver_setup_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const _kThemeBlue = Color(0xFF180D3B);

class DriverSetupPage extends StatefulWidget {
  final String userId;

  const DriverSetupPage({super.key, required this.userId});

  @override
  State<DriverSetupPage> createState() => _DriverSetupPageState();
}

class _DriverSetupPageState extends State<DriverSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  
  bool _isLoading = false;

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.userId).set(
        {
          'displayName': _nameCtrl.text.trim(),
          'carModel': _modelCtrl.text.trim(),
          'carColor': _colorCtrl.text.trim(),
          'rating': 5.0, // Default starting rating
          'isSetupComplete': true, // Flag to prevent repeated setup
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true), // Merge to keep existing user data
      );

      if (mounted) {
        // Navigate the user back or to the home screen
        Navigator.pop(context); 
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _modelCtrl.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Driver Profile'),
        backgroundColor: _kThemeBlue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('We need a few details to display your trips correctly.', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 24),

              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Your Full Name'),
                validator: (v) => (v == null || v.isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _modelCtrl,
                decoration: const InputDecoration(labelText: 'Car Model (e.g., Toyota Corolla)'),
                validator: (v) => (v == null || v.isEmpty) ? 'Car model is required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _colorCtrl,
                decoration: const InputDecoration(labelText: 'Car Color'),
                validator: (v) => (v == null || v.isEmpty) ? 'Car color is required' : null,
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kThemeBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Save and Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}