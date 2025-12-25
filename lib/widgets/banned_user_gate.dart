// lib/widgets/banned_user_gate.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../app_router.dart';

// DoraRide brand colors
const _kThemeGreen = Color(0xFF279C56);
const _kThemeBlue = Color(0xFF180D3B);

/// Global gate:
/// In MaterialApp we already have:
///   builder: (context, child) => BannedUserGate(child: child ?? SizedBox.shrink());
class BannedUserGate extends StatelessWidget {
  final Widget child;

  const BannedUserGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // 🔁 Listen to auth changes (login / logout / switch user)
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        final user = authSnap.data;

        // Not logged in → no ban check, just show whatever screen (Landing/Login/etc.)
        if (user == null) return child;

        final uid = user.uid;

        final stream = FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots();

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              // Small loader while we check status
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final doc = snap.data;

            // No user profile doc yet → treat as normal user
            if (doc == null || !doc.exists) {
              return child;
            }

            final data = doc.data() ?? {};
            final status =
                (data['status'] ?? 'active').toString().toLowerCase().trim();

            // 🚫 If banned → show banned screen instead of whole app
            if (status == 'banned') {
              return const _BannedUserScreen();
            }

            // ✅ Anything else (active, pending, etc.) → allow app
            return child;
          },
        );
      },
    );
  }
}

class _BannedUserScreen extends StatefulWidget {
  const _BannedUserScreen();

  @override
  State<_BannedUserScreen> createState() => _BannedUserScreenState();
}

class _BannedUserScreenState extends State<_BannedUserScreen> {
  bool _sending = false;
  bool _sentOnce = false;
  final TextEditingController _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendReviewRequest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _sending = true;
    });

    try {
      final docRef =
          FirebaseFirestore.instance.collection('ban_appeals').doc(user.uid);

      await docRef.set({
        'uid': user.uid,
        'email': user.email,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'message': _reasonCtrl.text.trim(),
      }, SetOptions(merge: true));

      setState(() {
        _sentOnce = true;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Review request sent to admin.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send request: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _goToStart() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;

    // Clear whole stack and go to Landing
    Navigator.of(context).pushNamedAndRemoveUntil(
      Routes.landing,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // 🔒 Disable back button (Android / browser)
      onWillPop: () async {
        await _goToStart();
        return false;
      },
      child: Scaffold(
        backgroundColor: _kThemeGreen.withOpacity(0.06),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircleAvatar(
                      radius: 40,
                      backgroundColor: _kThemeGreen,
                      child: Icon(
                        Icons.block,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Account under review',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: _kThemeBlue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your DoraRide account has been banned by the admin.\n'
                      'You cannot book or offer rides until this review is completed.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.black54,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 🔔 Optional message field for appeal
                    TextField(
                      controller: _reasonCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Tell us why we should review your ban (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 👉 Request review button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.mark_email_read),
                        label: Text(
                          _sentOnce ? 'Review request sent' : 'Request review',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kThemeGreen,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed:
                            _sentOnce || _sending ? null : _sendReviewRequest,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 👉 Go to start (sign out)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.logout, color: _kThemeBlue),
                        label: const Text(
                          'Go to start',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _kThemeBlue,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: _kThemeBlue),
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: _goToStart,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
