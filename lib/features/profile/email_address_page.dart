// lib/features/profile/email_address_page.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EmailAddressPage extends StatefulWidget {
  const EmailAddressPage({super.key});

  @override
  State<EmailAddressPage> createState() => _EmailAddressPageState();
}

class _EmailAddressPageState extends State<EmailAddressPage> {
  static const kGreen = Color(0xFF279C56);
  static const kNavy = Color(0xFF180D3B);

  final TextEditingController currentEmail = TextEditingController();
  final TextEditingController newEmail = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  @override
  void initState() {
    super.initState();
    _loadCurrentEmail();
  }

  Future<void> _loadCurrentEmail() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return;
      }

      String? email = user.email;

      // Fallback to Firestore if Auth email missing
      if (email == null || email.isEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (snap.exists) {
          final data = snap.data();
          final fsEmail = data?['email'] as String?;
          if (fsEmail != null && fsEmail.isNotEmpty) {
            email = fsEmail;
          }
        }
      }

      currentEmail.text = email ?? '';
    } catch (_) {
      // ignore; leave empty
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _looksLikeEmail(String v) {
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return re.hasMatch(v.trim());
  }

  Future<bool> _reauthenticateWithPassword(User user) async {
    final pwController = TextEditingController();
    bool submitting = false;
    String? errorText;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: !submitting,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            return AlertDialog(
              title: const Text('Confirm your password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'For security, please enter your password to change your email.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pwController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () {
                          Navigator.of(ctx).pop(false);
                        },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          final pw = pwController.text;
                          if (pw.isEmpty) {
                            setLocalState(() {
                              errorText = 'Please enter your password.';
                            });
                            return;
                          }
                          setLocalState(() {
                            submitting = true;
                            errorText = null;
                          });
                          try {
                            final email =
                                user.email ?? currentEmail.text.trim();
                            final cred = EmailAuthProvider.credential(
                              email: email,
                              password: pw,
                            );
                            await user.reauthenticateWithCredential(cred);
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop(true);
                            }
                          } on FirebaseAuthException catch (e) {
                            String msg = 'Incorrect password. Please try again.';
                            if (e.code == 'user-mismatch') {
                              msg =
                                  'This password does not match the current user.';
                            }
                            setLocalState(() {
                              submitting = false;
                              errorText = msg;
                            });
                          } catch (_) {
                            setLocalState(() {
                              submitting = false;
                              errorText =
                                  'Could not re-authenticate. Please try again.';
                            });
                          }
                        },
                  child: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );

    return result == true;
  }

  Future<void> _onUpdateEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in again.')),
      );
      return;
    }

    final newVal = newEmail.text.trim();

    if (newVal.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a new email address.')),
      );
      return;
    }

    if (!_looksLikeEmail(newVal)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That doesn’t look like a valid email.')),
      );
      return;
    }

    if (newVal == currentEmail.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New email is the same as current email.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      // 1) Re-authenticate with password popup
      final ok = await _reauthenticateWithPassword(user);
      if (!ok) {
        if (mounted) {
          setState(() => _saving = false);
        }
        return;
      }

      // 2) Ask Firebase to send verification & change email after verification
      await user.verifyBeforeUpdateEmail(newVal);

      // 3) Optionally mirror new email in Firestore (mark as not yet verified)
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'email': newVal,
          'emailVerified': false,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;

      currentEmail.text = newVal;
      newEmail.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'We sent a verification link to $newVal. Please verify to finish updating your email.',
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      String msg = 'Could not update email: ${e.code}';
      if (e.code == 'requires-recent-login') {
        msg =
            'For security reasons, please sign in again and then try changing your email.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    currentEmail.dispose();
    newEmail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kGreen,
      appBar: AppBar(
        title: const Text('Email address'),
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: currentEmail,
                  readOnly: true,
                  decoration: _dec('Current email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newEmail,
                  decoration: _dec('New email address'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _onUpdateEmail,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: kNavy,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: kNavy,
                            ),
                          )
                        : const Text('Update email'),
                  ),
                ),
              ],
            ),
    );
  }
}
