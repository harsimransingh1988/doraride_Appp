import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';

import '../../../app_router.dart';
// Import the ProfileSetupArgs model
import 'profile_age_page.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class ProfileReviewPage extends StatefulWidget {
  const ProfileReviewPage({super.key});

  @override
  State<ProfileReviewPage> createState() => _ProfileReviewPageState();
}

class _ProfileReviewPageState extends State<ProfileReviewPage> {
  Uint8List? _imageBytes;
  String _fileName = 'profile.jpg';
  bool _saving = false;
  
  // NEW: Holds DOB, Gender, and Usage from previous steps
  ProfileSetupArgs _profileData = const ProfileSetupArgs();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    
    if (args is Map) {
      final maybeBytes = args['imageBytes'];
      if (maybeBytes is Uint8List) {
        _imageBytes = maybeBytes;
      }
      final fn = args['fileName'];
      if (fn is String && fn.isNotEmpty) _fileName = fn;
      
      // Safely retrieve ProfileSetupArgs passed through the flow
      if (args['profileData'] is ProfileSetupArgs) {
        _profileData = args['profileData'] as ProfileSetupArgs;
      }
    } else if (args is ProfileSetupArgs) {
      _profileData = args;
    }
  }

  String _guessContentType(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg'; // default
  }

  Future<void> _confirmAndSave() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw 'No user is signed in.';
      }

      String? downloadUrl;

      // 1. Upload Profile Photo to Storage (if selected)
      if (_imageBytes != null && _imageBytes!.isNotEmpty) {
        // ✅ MUST match Storage rules: users/{uid}/profile.jpg
        const fixedFileName = 'profile.jpg';
        final storagePath = 'users/${user.uid}/$fixedFileName';
        final ref = FirebaseStorage.instance.ref(storagePath);

        final metadata = SettableMetadata(
          contentType: _guessContentType(_fileName),
        );

        await ref
            .putData(_imageBytes!, metadata)
            .timeout(const Duration(seconds: 30));

        downloadUrl = await ref.getDownloadURL();

        // Update Auth profile photo URL
        await user.updatePhotoURL(downloadUrl);
      }

      // 2. Persist ALL Profile Data to Firestore
      final doc = FirebaseFirestore.instance.collection('users').doc(user.uid);
      
      final Map<String, dynamic> updateData = {
        // Data from previous steps
        'dob': _profileData.dob != null
            ? DateFormat('yyyy-MM-dd').format(_profileData.dob!)
            : null,
        'gender': _profileData.gender,
        'usageRole': _profileData.usage,
        
        // Data from this step (Photo URL)
        'photoUrl': downloadUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      await doc.set(updateData, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved successfully!')),
      );

      // 3. Move to next onboarding step
      Navigator.pushReplacementNamed(context, Routes.profileSetupNotifications);
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Upload timed out. Check your Storage rules/connection.'),
          ),
        );
      }
    } on FirebaseException catch (e) {
      // Will catch permission-denied from Storage rules, etc.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: ${e.code}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _onChooseAnother() {
    Navigator.pop(context);
  }

  // Helper to display the collected data for review
  Widget _buildReviewDetail(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          Text(value ?? 'Not Set', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _imageBytes != null && _imageBytes!.isNotEmpty;

    return Scaffold(
      backgroundColor: _kThemeGreen,
      appBar: AppBar(
        backgroundColor: _kThemeGreen,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Profile set-up', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Review your profile',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Confirm all details before saving.',
                style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 28),

              Center(
                child: CircleAvatar(
                  radius: 72,
                  backgroundColor: Colors.white,
                  backgroundImage: hasImage ? MemoryImage(_imageBytes!) : null,
                  child: hasImage
                      ? null
                      : const Icon(Icons.person, size: 72, color: _kThemeBlue),
                ),
              ),
              const SizedBox(height: 24),
              
              // Display Collected Data
              _buildReviewDetail(
                'Date of Birth',
                _profileData.dob != null
                    ? DateFormat('MMM d, yyyy').format(_profileData.dob!)
                    : null,
              ),
              _buildReviewDetail('Gender', _profileData.gender),
              _buildReviewDetail('Usage Role', _profileData.usage),
              
              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _confirmAndSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kThemeBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Confirm & save'),
                ),
              ),
              const SizedBox(height: 10),

              Center(
                child: TextButton(
                  onPressed: _saving ? null : _onChooseAnother,
                  child: const Text(
                    'Choose another picture',
                    style: TextStyle(fontSize: 16, color: Colors.white),
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
