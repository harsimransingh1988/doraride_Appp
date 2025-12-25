// lib/features/onboarding/pages/driver_license_page.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app_router.dart';
import 'profile_age_page.dart'; // ProfileSetupArgs

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class DriverLicensePage extends StatefulWidget {
  final ProfileSetupArgs? initialArgs;

  const DriverLicensePage({super.key, this.initialArgs});

  @override
  State<DriverLicensePage> createState() => _DriverLicensePageState();
}

class _DriverLicensePageState extends State<DriverLicensePage> {
  final TextEditingController _licenseNumberCtrl = TextEditingController();

  Uint8List? _frontBytes;
  Uint8List? _backBytes;

  String? _frontFileName;
  String? _backFileName;

  bool _saving = false;
  ProfileSetupArgs? _profileData;

  final ImagePicker _picker = ImagePicker();

  bool get _isOnboarding => _profileData != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        widget.initialArgs ?? ModalRoute.of(context)?.settings.arguments;
    if (args is ProfileSetupArgs) {
      _profileData = args;
    }
  }

  @override
  void dispose() {
    _licenseNumberCtrl.dispose();
    super.dispose();
  }

  // ---------- IMAGE PICK HELPERS (camera + gallery) ----------

  Future<void> _pickLicenseImage({
    required bool isFront,
    required ImageSource source,
  }) async {
    final XFile? x =
        await _picker.pickImage(source: source, imageQuality: 85);
    if (x == null) return;

    final bytes = await x.readAsBytes();
    setState(() {
      if (isFront) {
        _frontBytes = bytes;
        _frontFileName = x.name;
      } else {
        _backBytes = bytes;
        _backFileName = x.name;
      }
    });
  }

  Future<void> _pickFront() async {
    // bottom sheet: camera / gallery
    await showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose front from gallery'),
              onTap: () async {
                Navigator.pop(context);
                await _pickLicenseImage(
                  isFront: true,
                  source: ImageSource.gallery,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take photo (front side)'),
              onTap: () async {
                Navigator.pop(context);
                await _pickLicenseImage(
                  isFront: true,
                  source: ImageSource.camera,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickBack() async {
    // bottom sheet: camera / gallery
    await showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose back from gallery'),
              onTap: () async {
                Navigator.pop(context);
                await _pickLicenseImage(
                  isFront: false,
                  source: ImageSource.gallery,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take photo (back side)'),
              onTap: () async {
                Navigator.pop(context);
                await _pickLicenseImage(
                  isFront: false,
                  source: ImageSource.camera,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------

  String _normalizeLicense(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  }

  String _guessContentType(String? name) {
    final n = (name ?? '').toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  void _openZoom(Uint8List bytes) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(child: Image.memory(bytes)),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_saving) return;

    final rawLicense = _licenseNumberCtrl.text.trim();
    if (rawLicense.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter license number')));
      return;
    }
    if (_frontBytes == null || _backBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload both front & back photos')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No user is signed in.')),
      );
      return;
    }

    setState(() => _saving = true);
    final normalizedLicense = _normalizeLicense(rawLicense);

    try {
      final firestore = FirebaseFirestore.instance;
      final licenseDoc =
          firestore.collection('license_numbers').doc(normalizedLicense);

      // ❌ Prevent same licence being used on multiple accounts
      await firestore.runTransaction((tx) async {
        final snap = await tx.get(licenseDoc);
        if (snap.exists) {
          final String? existingUid = snap.data()?['uid'];
          if (existingUid != null && existingUid != user.uid) {
            throw 'LICENSE_IN_USE';
          }
        }

        tx.set(
          licenseDoc,
          {
            'uid': user.uid,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      // Upload photos
      final storage = FirebaseStorage.instance;
      final frontRef = storage.ref('driver_licenses/${user.uid}/front.jpg');
      final backRef = storage.ref('driver_licenses/${user.uid}/back.jpg');

      await frontRef.putData(
        _frontBytes!,
        SettableMetadata(contentType: _guessContentType(_frontFileName)),
      );
      await backRef.putData(
        _backBytes!,
        SettableMetadata(contentType: _guessContentType(_backFileName)),
      );

      final frontUrl = await frontRef.getDownloadURL();
      final backUrl = await backRef.getDownloadURL();

      // Save to Firestore
      await firestore.collection('users').doc(user.uid).set(
        {
          'usageRole': 'driver',
          'licenseNumber': normalizedLicense,
          'licenseFrontUrl': frontUrl,
          'licenseBackUrl': backUrl,

          /// 👇 IMPORTANT: Driver is NOT verified yet
          'driverStatus': 'pending',

          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;

      // If came from onboarding → continue next
      if (_isOnboarding) {
        final nextArgs = ProfileSetupArgs(
          dob: _profileData?.dob,
          gender: _profileData?.gender,
          usage: 'driver',
        );

        Navigator.of(context).pushNamed(
          Routes.profileSetupPhone,
          arguments: nextArgs,
        );
      } else {
        // Came from OfferRide or profile → just pop back
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;

      if (e.toString().contains('LICENSE_IN_USE')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('This licence number is already used by another account.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save licence: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _skipForNow() async {
    if (!_isOnboarding) return;

    final nextArgs = ProfileSetupArgs(
      dob: _profileData?.dob,
      gender: _profileData?.gender,
      usage: _profileData?.usage ?? 'driver',
    );

    Navigator.of(context).pushNamed(
      Routes.profileSetupPhone,
      arguments: nextArgs,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kThemeGreen,
      appBar: AppBar(
        backgroundColor: _kThemeGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Profile set-up'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Verify your driver status',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              const Text(
                'Upload your driving licence. We’ll review it before you start offering rides.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 24),

              // Licence number field
              TextField(
                controller: _licenseNumberCtrl,
                decoration: InputDecoration(
                  labelText: 'Licence number',
                  labelStyle: const TextStyle(color: Colors.white),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white54),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: _LicenseImageTile(
                      label: 'Front side',
                      hasImage: _frontBytes != null,
                      bytes: _frontBytes,
                      onTap: _pickFront,
                      onZoom: _frontBytes != null
                          ? () => _openZoom(_frontBytes!)
                          : null,
                      onDelete: () {
                        setState(() => _frontBytes = null);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LicenseImageTile(
                      label: 'Back side',
                      hasImage: _backBytes != null,
                      bytes: _backBytes,
                      onTap: _pickBack,
                      onZoom:
                          _backBytes != null ? () => _openZoom(_backBytes!) : null,
                      onDelete: () {
                        setState(() => _backBytes = null);
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kThemeBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        )
                      : const Text(
                          'Submit & continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              if (_isOnboarding) ...[
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _saving ? null : _skipForNow,
                    child: const Text(
                      'Skip for now',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LicenseImageTile extends StatelessWidget {
  final String label;
  final bool hasImage;
  final Uint8List? bytes;

  final VoidCallback onTap;
  final VoidCallback? onZoom;
  final VoidCallback? onDelete;

  const _LicenseImageTile({
    required this.label,
    required this.hasImage,
    required this.onTap,
    required this.bytes,
    this.onZoom,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // tap: if image present, zoom; else pick
      onTap: hasImage ? onZoom : onTap,
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasImage ? Colors.white : Colors.white38,
            width: hasImage ? 2 : 1,
          ),
        ),
        child: hasImage
            ? Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      bytes!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: InkWell(
                      onTap: onDelete,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black54,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.upload_file,
                        color: Colors.white, size: 32),
                    const SizedBox(height: 8),
                    Text('Upload $label',
                        style: const TextStyle(color: Colors.white)),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap to choose or take photo',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
