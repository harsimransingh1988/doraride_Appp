// lib/features/home/pages/help_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:doraride_appp/app_router.dart';

// CORRECTED IMPORT PATH
import 'package:doraride_appp/common/ui_bits.dart';

// From theme.dart, AppColors.blue is 0xFF180D3B. Defined here for clarity.
const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _subjectCtrl = TextEditingController();
  final TextEditingController _detailsCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();

  bool _isSubmitting = false; // NEW: loading state

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _detailsCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  // NEW: Guest check function
  Future<bool> _isGuest() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_guest') ?? false;
  }

  // NEW: Standardized Restriction Dialog
  void _showRegisterPrompt() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Account Required'),
        content: const Text(
          'Please register or sign in to submit a request for support. As a guest, you can only browse the app.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // Navigate to the registration page
              Navigator.of(context).pushNamed('/register');
            },
            child: const Text('Register Now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitComplaint() async {
    // 💡 GUEST CHECK
    if (await _isGuest()) {
      _showRegisterPrompt(); // Show standardized prompt
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    final subject = _subjectCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final details = _detailsCtrl.text.trim();

    try {
      final user = FirebaseAuth.instance.currentUser;

      // Save support ticket to Firestore
      await FirebaseFirestore.instance
          .collection('support_tickets')
          .add({
        'subject': subject,
        'details': details,
        'fromEmail': email,
        'userId': user?.uid,
        'userName': user?.displayName,
        'platform': 'flutter_app',
        'status': 'open',
        'toEmail': 'support@doraride.com', // so backend knows where to send
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      // Show confirmation pop-up
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Complaint Submitted'),
          content: Text(
            'Your request "$subject" has been received successfully. '
            'We will review your submission and contact you at $email shortly.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Clear the form fields after submission
                _subjectCtrl.clear();
                _detailsCtrl.clear();
                _emailCtrl.clear();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Failed to submit your request. Please try again.\n$e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Help & Support',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
        ),
        automaticallyImplyLeading: false,
        backgroundColor: _kThemeBlue,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // NEW: Introductory Text Block
              Text(
                'Need assistance? Tell us about your issue.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
              ),
              const SizedBox(height: 16),

              // NEW: Form Container (The "Good Box")
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Submit a Request',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _kThemeBlue,
                          ),
                    ),
                    const SizedBox(height: 16),

                    // Email Field
                    LabeledField(
                      label: 'Your Contact Email',
                      icon: Icons.email_outlined,
                      child: TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          hintText: 'e.g., jane.doe@example.com',
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Email is required';
                          }
                          if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                              .hasMatch(v)) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Subject Field
                    LabeledField(
                      label: 'Subject / Briefly summarize the issue',
                      icon: Icons.title_outlined,
                      child: TextFormField(
                        controller: _subjectCtrl,
                        decoration: const InputDecoration(
                          hintText:
                              'e.g., Trip not showing or Payment error',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Subject is required'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Details Field
                    LabeledField(
                      label: 'Detailed Description',
                      icon: Icons.notes_outlined,
                      child: TextFormField(
                        controller: _detailsCtrl,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          hintText:
                              'Please describe your problem or request in detail (min. 10 characters)',
                        ),
                        validator: (v) =>
                            (v == null || v.trim().length < 10)
                                ? 'Description must be at least 10 characters'
                                : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submitComplaint,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(
                    _isSubmitting
                        ? 'Submitting...'
                        : 'Submit Complaint',
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: _kThemeBlue,
                    foregroundColor: Colors.white,
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

// NOTE: The redundant _Labeled widget was DELETED from here.
