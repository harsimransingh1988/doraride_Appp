// lib/features/home/pages/report_driver_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class ReportDriverPage extends StatefulWidget {
  final String driverId;
  final String driverName;
  final String? tripId;

  const ReportDriverPage({
    super.key,
    required this.driverId,
    required this.driverName,
    this.tripId,
  });

  @override
  State<ReportDriverPage> createState() => _ReportDriverPageState();
}

class _ReportDriverPageState extends State<ReportDriverPage> {
  final _formKey = GlobalKey<FormState>();

  String _category = 'Rude behaviour';
  final _detailsCtrl = TextEditingController();
  bool _submitting = false;

  final List<String> _categories = const [
    'Rude behaviour',
    'Unsafe driving',
    'Late or no-show',
    'Overcharging / payment issues',
    'Inappropriate messages',
    'Other',
  ];

  @override
  void dispose() {
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to report.')),
      );
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);

    try {
      // 🔥 MUST match security rules:
      // status == "pending"
      // fields: driverId, driverName, reporterId, category, message, status, createdAt
      await FirebaseFirestore.instance.collection('driver_reports').add({
        'driverId': widget.driverId,
        'driverName': widget.driverName,
        'reporterId': user.uid,
        'category': _category,
        'message': _detailsCtrl.text.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted. Our team will review it soon.'),
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit report: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F5),
      appBar: AppBar(
        backgroundColor: _kThemeBlue,
        foregroundColor: Colors.white,
        title: const Text('Report driver'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      Text(
                        'Report ${widget.driverName}',
                        style: const TextStyle(
                          color: _kThemeBlue,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Please tell us what happened. Your report is sent to the DoraRide team.',
                        style: TextStyle(
                          color: _kThemeBlue.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Category
                      DropdownButtonFormField<String>(
                        value: _category,
                        items: _categories
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(c),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _category = v);
                        },
                        decoration: _dec('Reason'),
                      ),
                      const SizedBox(height: 16),

                      // Details
                      TextFormField(
                        controller: _detailsCtrl,
                        maxLines: 5,
                        maxLength: 1000,
                        decoration: _dec('Describe what happened'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Please describe the issue';
                          }
                          if (v.trim().length < 10) {
                            return 'Please provide a bit more detail';
                          }
                          return null;
                        },
                      ),

                      if (widget.tripId != null &&
                          widget.tripId!.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Trip ID: ${widget.tripId}',
                          style: TextStyle(
                            color: _kThemeBlue.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _submitting ? null : _submit,
                          icon: const Icon(Icons.flag_outlined),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          label: Text(
                            _submitting ? 'Sending…' : 'Submit report',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'We take your safety seriously. Repeated or very serious reports may lead to account review or suspension.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
