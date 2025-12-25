// lib/features/onboarding/pages/profile_picture_page.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app_router.dart'; // For Routes.profileSetupReview
import 'profile_age_page.dart';    // ✅ for ProfileSetupArgs

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class ProfilePicturePage extends StatefulWidget {
  const ProfilePicturePage({super.key});

  @override
  State<ProfilePicturePage> createState() => _ProfilePicturePageState();
}

class _ProfilePicturePageState extends State<ProfilePicturePage> {
  final ImagePicker _picker = ImagePicker();

  Uint8List? _imageBytes;
  String? _fileName; // for storage naming hint
  bool _picking = false;

  // ✅ carry the data from age/gender/usage steps
  ProfileSetupArgs _profileData = const ProfileSetupArgs();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;

    if (args is ProfileSetupArgs) {
      _profileData = args;
    } else if (args is Map && args['profileData'] is ProfileSetupArgs) {
      _profileData = args['profileData'] as ProfileSetupArgs;
    }
  }

  // ---------- image picking helpers (camera + gallery) ----------

  Future<void> _pickImage(ImageSource source) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final XFile? x = await _picker.pickImage(
        source: source,
        maxWidth: 1500,
        maxHeight: 1500,
        imageQuality: 88,
      );
      if (x == null) {
        // cancelled
        return;
      }
      final bytes = await x.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _fileName = x.name;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo selected')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _openPickSheet() async {
    if (_picking) return;

    await showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // On web we only show "upload" (gallery)
            if (kIsWeb) ...[
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('Upload from device'),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickImage(ImageSource.gallery);
                },
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take photo'),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickImage(ImageSource.camera);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------

  void _onNext() {
    // Navigate to review with selected image bytes (or null if skipped)
    Navigator.pushNamed(
      context,
      Routes.profileSetupReview,
      arguments: {
        'imageBytes': _imageBytes, // Uint8List? ok for route arguments
        'fileName': _fileName ?? 'profile.jpg',
        'profileData': _profileData, // ✅ pass along
      },
    );
  }

  void _onSkip() {
    Navigator.pushNamed(
      context,
      Routes.profileSetupReview,
      arguments: {
        'imageBytes': null,
        'fileName': 'profile.jpg',
        'profileData': _profileData, // ✅ still pass data
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _imageBytes != null;

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
              // Headline
              Text(
                'Add a profile picture',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 10),
              const Text(
                'A clear photo helps riders and drivers recognize you.',
                style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 28),

              // Avatar preview
              Center(
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 64,
                      backgroundColor: Colors.white,
                      backgroundImage:
                          hasImage ? MemoryImage(_imageBytes!) : null,
                      child: hasImage
                          ? null
                          : const Icon(Icons.person, size: 64, color: _kThemeBlue),
                    ),
                    // Camera button
                    Material(
                      color: _kThemeBlue,
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: _openPickSheet,
                        customBorder: const CircleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: _picking
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.photo_camera_rounded,
                                  color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // Upload button (alternative to tapping the camera)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _picking ? null : _openPickSheet,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _kThemeBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.upload_rounded),
                  label: Text(_picking ? 'Selecting…' : 'Upload a photo'),
                ),
              ),

              const Spacer(),

              // Continue
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kThemeBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Continue'),
                ),
              ),
              const SizedBox(height: 10),

              Center(
                child: TextButton(
                  onPressed: _onSkip,
                  child: const Text(
                    'Skip for now',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
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
