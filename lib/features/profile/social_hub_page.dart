import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class SocialHubPage extends StatelessWidget {
  const SocialHubPage({super.key});

  static const kGreen = Color(0xFF279C56);
  static const kNavy = Color(0xFF180D3B);
  static const kBg = Color(0xFFF4F7F5);

  static final _items = <_SocialItem>[
    _SocialItem(
      name: 'Facebook',
      url: 'https://www.facebook.com/share/1BYJrf7Z89/?mibextid=wwXIfr',
      icon: Icons.facebook,
      color: Color(0xFF1877F2),
    ),
    _SocialItem(
      name: 'Instagram',
      url: 'https://www.instagram.com/dorarideofficial?igsh=dHR6eWxqdTlldGhz',
      icon: Icons.camera_alt_outlined,
      color: Color(0xFFE1306C),
    ),
    _SocialItem(
      name: 'TikTok',
      url: 'https://www.tiktok.com/@doraride?_t=ZS-90ZInkZOcUy&_r=1',
      icon: Icons.play_circle_outline,
      color: Color(0xFF000000),
    ),
  ];

  Future<void> _open(String url, BuildContext context) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        title: const Text('DoraRide — Social'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stay connected',
                    style: TextStyle(
                      color: kNavy,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    )),
                SizedBox(height: 6),
                Text(
                  'Follow DoraRide for updates, community stories, and new features.',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ..._items.map((s) => _SocialTile(
                item: s,
                onTap: () => _open(s.url, context),
              )),
        ],
      ),
    );
  }
}

class _SocialTile extends StatelessWidget {
  const _SocialTile({required this.item, required this.onTap});

  final _SocialItem item;
  final VoidCallback onTap;

  static const kNavy = SocialHubPage.kNavy;
  static const kGreen = SocialHubPage.kGreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: item.color.withOpacity(0.12),
          child: Icon(item.icon, color: item.color),
        ),
        title: Text(
          item.name,
          style: const TextStyle(
            color: kNavy,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          item.url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.black54),
        ),
        trailing: const Icon(Icons.open_in_new, color: kGreen),
        onTap: onTap,
      ),
    );
  }
}

class _SocialItem {
  final String name;
  final String url;
  final IconData icon;
  final Color color;
  const _SocialItem({
    required this.name,
    required this.url,
    required this.icon,
    required this.color,
  });
}
