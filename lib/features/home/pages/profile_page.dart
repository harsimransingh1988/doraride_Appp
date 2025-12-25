// lib/features/home/pages/profile_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart'; // ✅ Required for opening links
import 'package:doraride_appp/app_router.dart';
import 'package:doraride_appp/services/guest_guard.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  // ✅ Helper function to launch URLs safely
  // Updated to force new tab on web ('_blank') to prevent the "Green Screen" app loop
  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_blank', // Critical for Web
        );
      } else {
        debugPrint('Could not launch $url');
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final userStream = FirebaseAuth.instance.authStateChanges();

    return Scaffold(
      backgroundColor: _kThemeGreen,
      appBar: AppBar(
        title: const Text('My Profile', style: TextStyle(color: Colors.white)),
        backgroundColor: _kThemeBlue,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<User?>(
        stream: userStream,
        builder: (context, authSnap) {
          final user = authSnap.data;
          if (user == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Please sign in to view your profile.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header is tappable -> opens View Profile (BLOCK guests)
                _ProfileHeaderLive(user: user),

                const SizedBox(height: 24),

                // ==========================
                // 1. Account & Details
                // ==========================
                const _SectionHeader('Account & Details'),
                _ProfileTile(
                  icon: Icons.settings_outlined,
                  title: 'Profile Settings',
                  onTap: () {
                    GuestGuard.requireRegistered(
                      context,
                      onAllowed: () {
                        Navigator.of(context)
                            .pushNamed(Routes.profileSettings);
                      },
                    );
                  },
                ),
                _ProfileTile(
                  icon: Icons.account_circle_outlined,
                  title: 'View Your Profile',
                  onTap: () {
                    GuestGuard.requireRegistered(
                      context,
                      onAllowed: () {
                        Navigator.of(context).pushNamed(Routes.viewProfile);
                      },
                    );
                  },
                ),
                _ProfileTile(
                  icon: Icons.car_rental,
                  title: 'Vehicles (Driver)',
                  onTap: () {
                    GuestGuard.requireRegistered(
                      context,
                      onAllowed: () {
                        Navigator.of(context).pushNamed(Routes.vehicles);
                      },
                    );
                  },
                ),
                _ProfileTile(
                  icon: Icons.notifications_none,
                  title: 'Notifications',
                  onTap: () {
                    GuestGuard.requireRegistered(
                      context,
                      onAllowed: () {
                        Navigator.of(context)
                            .pushNamed(Routes.notifications);
                      },
                    );
                  },
                ),

                const SizedBox(height: 24),

                // ==========================
                // 2. Wallet & Payments
                // ==========================
                const _SectionHeader('Wallet & Payments'),
                _ProfileTile(
                  icon: Icons.wallet_giftcard_outlined,
                  title: 'Wallet',
                  onTap: () {
                    GuestGuard.requireRegistered(
                      context,
                      onAllowed: () {
                        Navigator.of(context).pushNamed(Routes.wallet);
                      },
                    );
                  },
                ),

                const SizedBox(height: 24),

                // ==========================
                // 3. Info & Support
                // ==========================
                const _SectionHeader('Info & Support'),
                
                // Standard Pages
                _ProfileTile(
                  icon: Icons.share_outlined,
                  title: 'Refer a Friend',
                  onTap: () =>
                      Navigator.of(context).pushNamed(Routes.referFriend),
                ),
                _ProfileTile(
                  icon: Icons.chat_bubble_outline,
                  title: 'Social Hub',
                  onTap: () =>
                      Navigator.of(context).pushNamed(Routes.socialHub),
                ),
                _ProfileTile(
                  icon: Icons.info_outline,
                  title: 'About Us',
                  onTap: () => Navigator.of(context).pushNamed(Routes.about),
                ),
                
                // Legal Policies
                _ProfileTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  onTap: () => _launchURL('https://doraride.com/privacy-policy.html'),
                ),
                _ProfileTile(
                  icon: Icons.gavel_outlined,
                  title: 'Terms & Conditions',
                  onTap: () => _launchURL('https://doraride.com/terms-and-conditions.html'),
                ),
                _ProfileTile(
                  icon: Icons.cancel_presentation_outlined,
                  title: 'Driver Cancellation Policy',
                  onTap: () => _launchURL('https://doraride.com/driver-cancellation-policy.html'),
                ),

                // ✅ MOVED HERE: Refund Policy
                _ProfileTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Refund & Payment Policy',
                  onTap: () => _launchURL('https://doraride.com/refund-and-payment-policy.html'),
                ),

                // ✅ MOVED HERE: Contact Us (Last)
                _ProfileTile(
                  icon: Icons.contact_support_outlined,
                  title: 'Contact Us',
                  onTap: () => _launchURL('https://doraride.com/contact.html'),
                ),

                const SizedBox(height: 24),

                const _LogoutButton(),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Tappable header with safe image handling
class _ProfileHeaderLive extends StatefulWidget {
  final User user;
  const _ProfileHeaderLive({required this.user});

  @override
  State<_ProfileHeaderLive> createState() => __ProfileHeaderLiveState();
}

class __ProfileHeaderLiveState extends State<_ProfileHeaderLive> {
  String _fallbackName() {
    if (widget.user.displayName?.isNotEmpty == true) {
      return widget.user.displayName!;
    }
    final email = widget.user.email;
    if (email?.isNotEmpty == true) return email!.split('@').first;
    return 'DoraRider';
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.user.uid;
    final docStream =
        FirebaseFirestore.instance.collection('users').doc(uid).snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docStream,
      builder: (context, snap) {
        final data = snap.data?.data() ?? const {};
        final dbName = (data['displayName'] ?? '').toString().trim();
        final displayName = dbName.isNotEmpty ? dbName : _fallbackName();
        final usageRole = (data['usageRole'] ?? 'Passenger').toString();

        // ---------- Driver verification logic (aligned with admin) ----------
        final String licenseNumber = (data['driverLicenseNumber'] ??
                data['licenseNumber'] ??
                '')
            .toString()
            .trim();

        final bool isDriver = usageRole.toLowerCase().contains('driver');

        String driverStatus =
            (data['driverStatus'] ?? 'pending').toString().toLowerCase();

        final bool driverVerifiedFlag =
            data['isDriverVerified'] == true ||
                data['driverVerified'] == true ||
                data['isVerifiedDriver'] == true ||
                driverStatus == 'approved';

        final bool isDriverVerified =
            isDriver && driverVerifiedFlag && licenseNumber.isNotEmpty;

        final bool isDriverPending =
            isDriver && !isDriverVerified && driverStatus == 'pending';
        // ------------------------------------------------

        String photo = (data['photoUrl'] ?? '').toString();
        if (photo.isEmpty && (widget.user.photoURL?.isNotEmpty ?? false)) {
          photo = widget.user.photoURL!;
        }

        String? backgroundUrl;
        if (photo.isNotEmpty) {
          final lastUpdate = data['lastPhotoUpdate'] ?? data['updatedAt'];
          int ts = 0;
          if (lastUpdate is Timestamp) ts = lastUpdate.millisecondsSinceEpoch;
          if (lastUpdate is int) ts = lastUpdate;

          final cacheValue =
              ts > 0 ? ts : DateTime.now().millisecondsSinceEpoch;
          if (photo.contains('?')) {
            backgroundUrl = '$photo&cache=$cacheValue';
          } else {
            backgroundUrl = '$photo?cache=$cacheValue';
          }
        }

        return InkWell(
          onTap: () {
            GuestGuard.requireRegistered(
              context,
              onAllowed: () {
                Navigator.of(context).pushNamed(Routes.viewProfile);
              },
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Card(
            margin: EdgeInsets.zero,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: _kThemeGreen.withOpacity(0.1),
                    backgroundImage: (backgroundUrl != null)
                        ? NetworkImage(backgroundUrl)
                        : null,
                    child: (backgroundUrl == null)
                        ? Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : 'R',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: _kThemeGreen,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: _kThemeBlue,
                              ),
                        ),
                        const SizedBox(height: 4),

                        if (isDriver)
                          Row(
                            children: [
                              Icon(
                                isDriverVerified
                                    ? Icons.verified_rounded
                                    : (isDriverPending
                                        ? Icons.hourglass_top
                                        : Icons.warning_amber),
                                size: 16,
                                color: isDriverVerified
                                    ? _kThemeGreen
                                    : (isDriverPending
                                        ? Colors.orange
                                        : Colors.redAccent),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isDriverVerified
                                    ? 'Driver verified'
                                    : (isDriverPending
                                        ? 'Driver verification pending'
                                        : 'Driver not verified'),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDriverVerified
                                      ? _kThemeGreen
                                      : (isDriverPending
                                          ? Colors.orange
                                          : Colors.redAccent),
                                ),
                              ),
                            ],
                          ),

                        if (isDriver) const SizedBox(height: 4),

                        Text(
                          'Role: $usageRole',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: _kThemeBlue),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton();

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Confirm Logout'),
            content: const Text('Are you sure you want to sign out?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Logout'),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmed) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('logged_in', false);
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          Routes.landing,
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.logout, color: Colors.red),
        title: const Text(
          'Log out',
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red),
        ),
        onTap: () => _logout(context),
      ),
    );
  }
}