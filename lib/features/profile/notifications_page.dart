// lib/features/profile/notifications_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  // DoraRide palette
  static const kGreen = Color(0xFF279C56);
  static const kNavy = Color(0xFF180D3B);
  static const kBg = Colors.white;

  // Persistence keys
  static const _kPush = 'notif_push';
  static const _kSms = 'notif_sms';
  static const _kEmail = 'notif_email';
  static const _kMarketing = 'notif_marketing';

  bool loading = true;

  // Replace with your real verification flags
  bool phoneVerified = true;
  bool emailVerified = true;

  // User preferences
  bool push = true;
  bool sms = false;
  bool email = true;
  bool marketing = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      push = p.getBool(_kPush) ?? true;
      sms = p.getBool(_kSms) ?? false;
      email = p.getBool(_kEmail) ?? true;
      marketing = p.getBool(_kMarketing) ?? false;
      loading = false;
    });
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kPush, push);
    await p.setBool(_kSms, sms);
    await p.setBool(_kEmail, email);
    await p.setBool(_kMarketing, marketing);
  }

  Future<void> _confirm() async {
    setState(() => loading = true);
    await _savePrefs();

    // TODO: Hook to real services
    // await _configurePush(push);
    // await _configureSms(sms);
    // await _configureEmail(email, marketing);

    if (!mounted) return;
    setState(() => loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notification preferences saved')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final switchTheme = SwitchThemeData(
      thumbColor: MaterialStateProperty.resolveWith<Color?>(
          (states) => Colors.white),
      trackColor: MaterialStateProperty.resolveWith<Color?>((states) {
        if (states.contains(MaterialState.disabled)) {
          return const Color(0xFFCDD5DF);
        }
        if (states.contains(MaterialState.selected)) {
          return kGreen;
        }
        return const Color(0xFFE6EBF1);
      }),
    );

    return Theme(
      data: Theme.of(context).copyWith(switchTheme: switchTheme),
      child: Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: kBg,
          foregroundColor: kNavy,
          title: const Text(
            'Notifications',
            style: TextStyle(
              color: kNavy,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator(color: kGreen))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  const Text(
                    "Please select how you'd like us to notify you.",
                    style: TextStyle(color: kNavy, fontSize: 16),
                  ),
                  const SizedBox(height: 14),

                  // Recommended chip (green)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: kGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star, size: 16, color: Colors.white),
                          SizedBox(width: 6),
                          Text(
                            'Recommended',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Push
                  _SwitchTile(
                    title: 'Push notifications',
                    subtitle:
                        'For all important activity: bookings, messages, reviews, etc.',
                    value: push,
                    onChanged: (v) => setState(() => push = v),
                  ),

                  const SizedBox(height: 12),

                  // SMS (disabled unless phone verified & push enabled)
                  _SwitchTile(
                    title: 'SMS text messages',
                    subtitle:
                        'For new bookings and cancellations only (already sent as push notifications).',
                    value: sms,
                    onChanged: (phoneVerified && push)
                        ? (v) => setState(() => sms = v)
                        : null,
                    disabledReason: !phoneVerified
                        ? 'Verify your phone number to enable SMS.'
                        : (!push
                            ? 'Enable push notifications to allow SMS fallback.'
                            : null),
                  ),

                  const SizedBox(height: 12),

                  // Email
                  _SwitchTile(
                    title: 'Email',
                    subtitle:
                        'For all important activity: bookings, messages, reviews…',
                    value: email,
                    onChanged:
                        emailVerified ? (v) => setState(() => email = v) : null,
                    disabledReason: emailVerified
                        ? null
                        : 'Verify your email address to enable.',
                  ),

                  const SizedBox(height: 12),

                  // Marketing
                  _SwitchTile(
                    title: 'Marketing',
                    subtitle:
                        'For new features, special promos & discounts, DoraRide news, etc.',
                    value: marketing,
                    onChanged: (v) => setState(() => marketing = v),
                  ),
                ],
              ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          color: kBg,
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: loading ? null : _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: kGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800),
              ),
              child: const Text('Confirm'),
            ),
          ),
        ),
      ),
    );
  }
}

// ======================= UI Part =======================

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.disabledReason,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? disabledReason;

  static const kNavy = _NotificationsPageState.kNavy;

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            title,
            style: const TextStyle(
              color: kNavy,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              subtitle,
              style: TextStyle(
                color: kNavy.withOpacity(0.75),
                fontSize: 16,
                height: 1.3,
              ),
            ),
          ),
          trailing: Switch(value: value, onChanged: onChanged),
        ),
        if (disabled && disabledReason != null)
          Padding(
            padding:
                const EdgeInsets.only(left: 16, right: 16, bottom: 6),
            child: Text(
              disabledReason!,
              style: TextStyle(
                color: Colors.red.withOpacity(0.85),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
