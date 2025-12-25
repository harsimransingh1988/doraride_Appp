import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A tiny reusable avatar that updates everywhere.
/// - Reads SharedPreferences('profile_photo_url') for instant load
/// - Listens to Firestore users/{uid}.photoUrl for live updates
class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({
    super.key,
    this.size = 20,
    this.fallback,
    this.photoUrl, // ✅ ADDED: Allow parent widget to pass the URL directly
  });

  final double size;
  final Widget? fallback;
  final String? photoUrl; // ✅ ADDED: URL parameter

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  static const _kPhoto = 'profile_photo_url';

  // Internal state is only used if photoUrl is NOT passed via widget
  String? _internalPhotoUrl;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _stream;

  // The effective URL to use, prioritizing widget.photoUrl
  String? get _effectivePhotoUrl => widget.photoUrl ?? _internalPhotoUrl;

  @override
  void initState() {
    super.initState();
    // Only load from cache/stream if the parent is NOT supplying the URL
    if (widget.photoUrl == null) {
      _load();
    }
  }
  
  // This method ensures that if the parent changes the photoUrl property, 
  // we reset our internal loading status.
  @override
  void didUpdateWidget(covariant ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.photoUrl != oldWidget.photoUrl) {
      // If parent starts or stops supplying a URL, we may need to reload or stop streaming.
      if (widget.photoUrl == null) {
        _load();
      } else {
        // Parent supplied a URL, so we cancel internal streaming if active.
        _stream = null;
        _internalPhotoUrl = null;
      }
    }
  }

  Future<void> _load() async {
    // read cache first
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_kPhoto);
    if (mounted) setState(() => _internalPhotoUrl = cached);

    // subscribe to Firestore for live updates
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _stream = FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();
      _stream!.listen((doc) async {
        if (!doc.exists) return;
        final url = (doc.data()?['photoUrl'] ?? '').toString();
        if (url.isEmpty) return;
        if (mounted) setState(() => _internalPhotoUrl = url);
        await prefs.setString(_kPhoto, url);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double r = widget.size;
    final fallback = widget.fallback ??
        CircleAvatar(
          radius: r,
          backgroundColor: const Color(0xFF279C56),
          child: const Icon(Icons.person, color: Colors.white, size: 16),
        );

    final url = _effectivePhotoUrl; // Use the derived effective URL

    if (url == null || url.isEmpty) return fallback;

    return CircleAvatar(
      radius: r,
      backgroundColor: const Color(0xFF279C56),
      backgroundImage: NetworkImage(url),
    );
  }
}