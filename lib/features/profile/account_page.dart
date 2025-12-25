import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/profile_avatar.dart'; // <- new reusable avatar

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  static const kGreen = Color(0xFF279C56);
  static const kNavy = Color(0xFF180D3B);
  static const kBg = Color(0xFFF4F7F5);

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  // local cache keys (same as profile page)
  static const _kFirst = 'first_name';
  static const _kLast = 'last_name';
  static const _kPhoto = 'profile_photo_url';

  String _name = '';
  String _email = '';
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _loadHeader();
  }

  Future<void> _loadHeader() async {
    final prefs = await SharedPreferences.getInstance();

    final first = prefs.getString(_kFirst) ?? '';
    final last = prefs.getString(_kLast) ?? '';
    _photoUrl = prefs.getString(_kPhoto);

    final user = FirebaseAuth.instance.currentUser;
    _email = user?.email ?? '';
    _name = [first, last]
        .where((s) => s.trim().isNotEmpty)
        .join(' ')
        .trim();
    if (_name.isEmpty) _name = user?.displayName ?? '';

    // Try live Firestore (instant update after you save on profile page)
    if (user != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((snap) async {
        if (!snap.exists) return;
        final data = snap.data()!;
        final nf = (data['firstName'] ?? '').toString();
        final nl = (data['lastName'] ?? '').toString();
        final nurl = (data['photoUrl'] ?? '').toString();

        setState(() {
          _name = [nf, nl].where((s) => s.isNotEmpty).join(' ').trim();
          if (_name.isEmpty) _name = user.displayName ?? _name;
          if (nurl.isNotEmpty) _photoUrl = nurl;
        });

        // keep cache hot for next launches
        await prefs.setString(_kFirst, nf);
        await prefs.setString(_kLast, nl);
        if (nurl.isNotEmpty) await prefs.setString(_kPhoto, nurl);
      });
    }

    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AccountPage.kBg,
      appBar: AppBar(
        backgroundColor: AccountPage.kGreen,
        foregroundColor: Colors.white,
        title: const Text('Account'),
        centerTitle: true,
        // Top-right bubble avatar (updates as soon as photo changes)
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: ProfileAvatar(size: 22), // <- shared widget
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _Header(
            name: _name.isEmpty ? 'Your name' : _name,
            email: _email,
            photoUrl: _photoUrl,
            onOpenProfile: () => Navigator.pushNamed(context, '/view_profile'),
          ),
          const SizedBox(height: 16),

          const _SectionLabel('Profile'),
          _NavTile(
            icon: Icons.person_outline,
            label: 'View profile',
            onTap: () => Navigator.pushNamed(context, '/view_profile'),
          ),
          _NavTile(
            icon: Icons.settings_outlined,
            label: 'Profile settings',
            onTap: () => Navigator.pushNamed(context, '/profile_settings'),
          ),
          const SizedBox(height: 16),

          const _SectionLabel('Engagement'),
          _NavTile(
            icon: Icons.notifications_active_outlined,
            label: 'Notifications',
            onTap: () => Navigator.pushNamed(context, '/notifications'),
          ),
          _NavTile(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Wallet',
            onTap: () => Navigator.pushNamed(context, '/wallet'),
          ),
          _NavTile(
            icon: Icons.card_giftcard_outlined,
            label: 'Refer & earn',
            onTap: () => Navigator.pushNamed(context, '/refer_friend'),
          ),
          _NavTile(
            icon: Icons.public,
            label: 'Social',
            onTap: () => Navigator.pushNamed(context, '/social_hub'),
          ),
          const SizedBox(height: 16),

          const _SectionLabel('Information'),
          _NavTile(
            icon: Icons.support_agent,
            label: 'Support / Help',
            onTap: () => Navigator.pushNamed(context, '/support_page'),
          ),
          _NavTile(
            icon: Icons.info_outline,
            label: 'About us',
            onTap: () => Navigator.pushNamed(context, '/about_page'),
          ),
          _NavTile(
            icon: Icons.description_outlined,
            label: 'Terms & policies',
            onTap: () => Navigator.pushNamed(context, '/terms_page'),
          ),
          _NavTile(
            icon: Icons.sentiment_dissatisfied_outlined,
            label: 'Close account',
            onTap: () => Navigator.pushNamed(context, '/close_account_page'),
          ),
          const SizedBox(height: 16),

          _LogoutTile(
            onConfirmLogout: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Logout'),
                    ),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await FirebaseAuth.instance.signOut();
                Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.onOpenProfile,
  });

  final String name;
  final String email;
  final String? photoUrl;
  final VoidCallback onOpenProfile;

  static const kNavy = AccountPage.kNavy;
  static const kGreen = AccountPage.kGreen;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpenProfile,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            // FIX: Pass the photoUrl to ProfileAvatar for display
            ProfileAvatar(
              size: 28,
              photoUrl: photoUrl, 
              fallback: CircleAvatar(
                radius: 28,
                backgroundColor: kGreen.withOpacity(0.12),
                child: const Icon(Icons.person, color: kGreen, size: 28),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kNavy, fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(
                    email.isEmpty ? '—' : email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0x99000000), fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black45),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  static const kNavy = AccountPage.kNavy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(color: kNavy, fontWeight: FontWeight.w900, fontSize: 16),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  static const kNavy = AccountPage.kNavy;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(icon, color: kNavy),
        title: Text(label, style: const TextStyle(color: kNavy, fontWeight: FontWeight.w800)),
        trailing: const Icon(Icons.chevron_right, color: Colors.black45),
        onTap: onTap,
      ),
    );
  }
}

class _LogoutTile extends StatelessWidget {
  const _LogoutTile({required this.onConfirmLogout});
  final VoidCallback onConfirmLogout;

  static const kNavy = AccountPage.kNavy;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: const Icon(Icons.logout, color: Colors.redAccent),
        title: const Text('Logout', style: TextStyle(color: kNavy, fontWeight: FontWeight.w800)),
        onTap: onConfirmLogout,
      ),
    );
  }
}