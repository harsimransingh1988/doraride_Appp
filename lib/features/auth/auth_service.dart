import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // -----------------------------
  // Google Sign-In
  // -----------------------------
  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      provider.addScope('email');
      return _auth.signInWithPopup(provider); // ✅ Web
    }

    final GoogleSignInAccount? user = await GoogleSignIn().signIn();
    if (user == null) throw Exception('Google sign-in cancelled');

    final googleAuth = await user.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return _auth.signInWithCredential(credential); // ✅ Android / iOS
  }

  // -----------------------------
  // 🍎 Apple Sign-In
  // -----------------------------
  Future<UserCredential> signInWithApple() async {
    final provider = OAuthProvider('apple.com');
    provider.addScope('email');
    provider.addScope('name');

    if (kIsWeb) {
      // Web uses popup
      return await _auth.signInWithPopup(provider);
    }

    // iOS / Android
    return await _auth.signInWithProvider(provider);
  }
}
