// lib/features/home/pages/offer_ride_gate_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../app_router.dart';
import 'offer_ride_page.dart';

/// Dialog result
enum DriverPopupAction { ok, upload }

Future<DriverPopupAction?> _showDriverPopup(
  BuildContext context, {
  required String title,
  required String message,
  bool showUpload = false,
}) {
  final theme = Theme.of(context);

  return showDialog<DriverPopupAction>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.35),
    builder: (ctx) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 320,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              color: theme.dialogBackgroundColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: IntrinsicHeight(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: showUpload
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(ctx).pop(DriverPopupAction.ok),
                                child: const Text('CANCEL'),
                              ),
                              const SizedBox(width: 4),
                              FilledButton(
                                onPressed: () => Navigator.of(ctx)
                                    .pop(DriverPopupAction.upload),
                                child: const Text('UPLOAD NOW'),
                              ),
                            ],
                          )
                        : TextButton(
                            onPressed: () =>
                                Navigator.of(ctx).pop(DriverPopupAction.ok),
                            child: const Text('OK'),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// ✅ Gate page widget (THIS WAS MISSING)
/// Push this page, it will auto-check and then route to:
/// - OfferRidePage OR
/// - DriverLicense page OR show dialog
class OfferRideGatePage extends StatefulWidget {
  final String? tripIdToEdit;

  const OfferRideGatePage({super.key, this.tripIdToEdit});

  @override
  State<OfferRideGatePage> createState() => _OfferRideGatePageState();
}

class _OfferRideGatePageState extends State<OfferRideGatePage> {
  bool _ran = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ran) return;
    _ran = true;

    // Run after first frame (safe context)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      await checkDriverAndOpenOfferRide(
        context,
        tripIdToEdit: widget.tripIdToEdit,
        replaceCurrent: true, // important: remove gate from back stack
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Simple professional loader screen
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      ),
    );
  }
}

/// ✅ Call this from the "Offer a ride" button.
/// If admin toggle is OFF → go straight to OfferRidePage (no checks).
/// If toggle is ON → require licence (pending/approved/rejected logic).
Future<void> checkDriverAndOpenOfferRide(
  BuildContext context, {
  String? tripIdToEdit,
  bool replaceCurrent = false, // ✅ added (doesn't affect other calls)
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    // Not logged in – you can redirect to login if you want.
    return;
  }

  final firestore = FirebaseFirestore.instance;

  void _goToOfferRide() {
    final route = MaterialPageRoute(
      builder: (_) => OfferRidePage(tripIdToEdit: tripIdToEdit),
    );
    if (replaceCurrent) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  void _goToDriverLicense() {
    if (replaceCurrent) {
      Navigator.of(context).pushReplacementNamed(Routes.driverLicense);
    } else {
      Navigator.of(context).pushNamed(Routes.driverLicense);
    }
  }

  // 1) 🔁 Check admin toggle: /admin_settings/driver_verification.enabled
  bool licenceEnforced = false;
  try {
    final cfgSnap = await firestore
        .collection('admin_settings')
        .doc('driver_verification')
        .get();

    final data = cfgSnap.data();
    licenceEnforced = (data?['enabled'] as bool?) ?? false;
  } catch (_) {
    // On error → be safe for UX and allow posting (no hard block)
    licenceEnforced = false;
  }

  // 🔓 If NOT enforced → driver can post without any approval
  if (!licenceEnforced) {
    _goToOfferRide();
    return;
  }

  // 2) 🔒 When enforced → apply licence verification logic
  try {
    final snap = await firestore.collection('users').doc(user.uid).get();

    final data = snap.data() ?? {};
    final usageRole = data['usageRole'] as String?;
    final driverStatus = data['driverStatus'] as String?;
    final isDriverVerified = data['isDriverVerified'] as bool? ?? false;
    final hasLicenceNumber =
        (data['licenseNumber'] as String?)?.trim().isNotEmpty ?? false;

    // ✅ Approved driver: allow posting
    if (usageRole == 'driver' &&
        driverStatus == 'approved' &&
        isDriverVerified) {
      _goToOfferRide();
      return;
    }

    // ❌ Rejected
    if (driverStatus == 'rejected') {
      final action = await _showDriverPopup(
        context,
        title: 'Driver verification required',
        message:
            'Your driving licence was reviewed and could not be approved.\n\n'
            'Please upload clear photos of your licence again so we can re-check it.',
        showUpload: true,
      );

      if (action == DriverPopupAction.upload) {
        _goToDriverLicense();
      } else {
        // If this is the gate page and user cancels, go back
        if (replaceCurrent && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
      return;
    }

    // 🟡 No licence uploaded yet
    if (!hasLicenceNumber) {
      final action = await _showDriverPopup(
        context,
        title: 'Add your driving licence',
        message:
            'Before you can offer rides, we need to quickly verify your driving licence.\n\n'
            'Upload your licence once – after approval you can post trips freely.',
        showUpload: true,
      );

      if (action == DriverPopupAction.upload) {
        _goToDriverLicense();
      } else {
        if (replaceCurrent && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
      return;
    }

    // 🕒 Pending review
    await _showDriverPopup(
      context,
      title: 'Licence under review',
      message:
          'Thanks for uploading your driving licence.\n\n'
          'Our team is reviewing it now. As soon as it is approved, you’ll be able to post rides.',
      showUpload: false,
    );

    // After OK on pending dialog, if this is gate page, go back
    if (replaceCurrent && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  } catch (e) {
    await _showDriverPopup(
      context,
      title: 'Driver verification',
      message: 'Something went wrong while checking your status.\n$e',
      showUpload: false,
    );

    if (replaceCurrent && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}
