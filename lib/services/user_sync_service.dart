import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Keeps the `users/{uid}` doc in Firestore up to date with the
/// Firebase Auth profile (displayName, photoURL, email).
///
/// Usage:
///   In main.dart *after* Firebase.initializeApp():
///     UserSyncService.instance.start();
///
/// That’s it. Whenever the user logs in / updates their profile,
/// Firestore will have `displayName` so your Messages page can show it.
class UserSyncService {
  UserSyncService._();
  static final UserSyncService instance = UserSyncService._();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  /// Call once on app start (after Firebase.initializeApp()).
  void start() {
    // Run immediately for current user
    _syncCurrentUser();

    // Keep in sync on every auth state change or profile change.
    _auth.userChanges().listen((_) => _syncCurrentUser());
  }

  /// Ensures users/{uid} exists and has displayName/email/photoUrl.
  Future<void> _syncCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final ref = _db.collection('users').doc(user.uid);
    final snap = await ref.get();

    // Build data from Auth
    final data = <String, dynamic>{
      'uid': user.uid,
      'email': user.email ?? '',
      'displayName': user.displayName ?? '',   // 👈 critical for Messages list
      'photoUrl': user.photoURL ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (snap.exists) {
      // Merge so we don't overwrite any app-specific fields.
      await ref.set(data, SetOptions(merge: true));
    } else {
      await ref.set({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Optional helper you can call from your profile edit flow.
  Future<void> updateDisplayName(String name) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Update Auth profile
    await user.updateDisplayName(name);

    // Mirror to Firestore
    await _db.collection('users').doc(user.uid).set(
      {
        'displayName': name,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Optional helper to update photo URL everywhere.
  Future<void> updatePhotoUrl(String url) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await user.updatePhotoURL(url);

    await _db.collection('users').doc(user.uid).set(
      {
        'photoUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
