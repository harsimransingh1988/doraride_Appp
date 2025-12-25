// lib/features/profile/profile_settings_page.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app_router.dart';

import 'phone_number_page.dart'; // phone edit page

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  static const Color kGreen = Color(0xFF279C56);
  bool _isUploading = false;

  // ---- Phone state (read-only display) ----
  String? _phoneNumber;
  bool _loadingPhone = true;

  @override
  void initState() {
    super.initState();
    _loadPhoneNumber();
  }

  Future<void> _loadPhoneNumber() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _loadingPhone = false);
        return;
      }
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (snap.exists) {
        final data = snap.data();
        _phoneNumber = data?['phone'] as String?;
      }
    } catch (_) {
      // ignore, just show "Not set"
    } finally {
      if (mounted) {
        setState(() => _loadingPhone = false);
      }
    }
  }

  Future<void> _pickAndUploadPhoto(BuildContext context) async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please sign in to update your photo.'),
          ),
        );
      }
      return;
    }

    // -------- 1) Choose source (no spinner yet) --------
    ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Photo Source'),
        content: const Text('Where would you like to get your photo from?'),
        actions: [
          if (!kIsWeb)
            TextButton(
              onPressed: () => Navigator.pop(context, ImageSource.camera),
              child: const Text('Camera'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: const Text('Gallery'),
          ),
        ],
      ),
    );

    if (source == null) {
      // cancelled
      return;
    }

    // On web, always use gallery
    if (kIsWeb && source == ImageSource.camera) {
      source = ImageSource.gallery;
    }

    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 800,
      maxHeight: 800,
    );

    if (picked == null) {
      // cancelled
      return;
    }

    // -------- 2) Now actually uploading -> show spinner --------
    setState(() => _isUploading = true);

    try {
      final Uint8List bytes = await picked.readAsBytes();
      final String uid = authUser.uid;

      final ref = FirebaseStorage.instance
          .ref()
          .child('user_uploads/$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg');

      // Upload file
      final uploadTask = ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      await uploadTask;

      // Get public URL
      final String url = await ref.getDownloadURL();

      // ✅ At this point, upload is done → stop spinner immediately
      if (!mounted) return;
      setState(() => _isUploading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Photo uploaded! Saving to profile...'),
          duration: Duration(seconds: 2),
        ),
      );

      // -------- 3) Save to Auth + Firestore IN BACKGROUND --------
      _savePhotoToUser(authUser, url);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Upload failed: ${e.message ?? e.code}'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Upload failed: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Runs *after* spinner is stopped. If this is a bit slow, the UI
  /// will still feel fast. Profile / View Profile will see the new URL.
  Future<void> _savePhotoToUser(User authUser, String url) async {
    try {
      final uid = authUser.uid;

      await Future.wait([
        authUser.updatePhotoURL(url),
        FirebaseFirestore.instance.collection('users').doc(uid).set(
          {
            'photoUrl': url,
            'updatedAt': FieldValue.serverTimestamp(),
            'lastPhotoUpdate': DateTime.now().millisecondsSinceEpoch,
          },
          SetOptions(merge: true),
        ),
      ]);

      await authUser.reload();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Profile photo saved.'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // Photo is already in Storage; worst case we just failed to link it.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Saved in storage but profile update failed: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _logout() async {
    try {
      // Clear local flags
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('logged_in', false);
      await prefs.setBool('is_guest', false);
      await prefs.setBool('email_verified', false);
      await prefs.setBool('profile_completed', false);
      await prefs.setBool('onboarding_completed', false);

      // Firebase sign-out
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      // Go to landing and clear all previous routes
      Navigator.of(context).pushNamedAndRemoveUntil(
        Routes.landing,
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to log out: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kGreen,
      appBar: AppBar(
        title: const Text('Profile Settings'),
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          // Change profile photo
          ListTile(
            leading: _isUploading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.camera_alt_outlined, color: Colors.white),
            title: Text(
              _isUploading ? 'Uploading...' : 'Change Profile Photo',
              style: const TextStyle(color: Colors.white),
            ),
            trailing:
                _isUploading ? null : const Icon(Icons.upload, color: Colors.white),
            tileColor: const Color(0xFF2EAB61).withOpacity(0.35),
            onTap: _isUploading ? null : () => _pickAndUploadPhoto(context),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          ),

          // Phone number: show value, open dedicated page
          ListTile(
            leading:
                const Icon(Icons.phone_iphone_outlined, color: Colors.white),
            title: const Text(
              'Phone number',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              _loadingPhone
                  ? 'Loading...'
                  : (_phoneNumber != null && _phoneNumber!.isNotEmpty
                      ? _phoneNumber!
                      : 'Not set'),
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white),
            tileColor: const Color(0xFF2EAB61).withOpacity(0.35),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PhoneNumberPage(),
                ),
              );
              _loadPhoneNumber();
            },
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          ),

          _NavTile(
            icon: Icons.person_outline,
            title: 'Personal details (name, phone number, …)',
            routeName: '/personal_details',
          ),
          _NavTile(
            icon: Icons.tune,
            title: 'Preferences (smoking, chattiness, …)',
            routeName: '/preferences',
          ),
          _NavTile(
            icon: Icons.directions_car_outlined,
            title: 'Vehicles',
            routeName: '/vehicles',
          ),
          _NavTile(
            icon: Icons.email_outlined,
            title: 'Email address',
            routeName: '/email_address',
          ),
          _NavTile(
            icon: Icons.lock_outline,
            title: 'Change password',
            routeName: '/change_password',
          ),
          _NavTile(
            icon: Icons.language_outlined,
            title: 'Language',
            routeName: '/language',
          ),

          const SizedBox(height: 16),

          // 🔴 LOG OUT
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text(
              'Log out',
              style: TextStyle(color: Colors.redAccent),
            ),
            tileColor: Colors.white.withOpacity(0.1),
            onTap: _logout,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String routeName;

  const _NavTile({
    required this.icon,
    required this.title,
    required this.routeName,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white),
      tileColor: const Color(0xFF2EAB61).withOpacity(0.35),
      onTap: () => Navigator.of(context).pushNamed(routeName),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}
