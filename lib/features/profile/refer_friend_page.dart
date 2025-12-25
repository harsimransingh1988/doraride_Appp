import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../common/repos/referral_repository.dart';
import '../../common/repos/wallet_repository.dart';

class ReferFriendPage extends StatefulWidget {
  const ReferFriendPage({super.key});

  @override
  State<ReferFriendPage> createState() => _ReferFriendPageState();
}

class _ReferFriendPageState extends State<ReferFriendPage> {
  static const kGreen = Color(0xFF279C56);
  static const kNavy  = Color(0xFF180D3B);
  static const kBg    = Color(0xFFF4F7F5);

  final referralRepo = ReferralRepository();
  final walletRepo   = WalletRepository();

  String link = '';
  int points = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final l = await referralRepo.getOrCreateReferralLink();
    final p = await referralRepo.getPoints();
    if (!mounted) return;
    setState(() {
      link = l;
      points = p;
      loading = false;
    });
  }

  String get _cashValue {
    final cents = points * ReferralRepository.centsPerPoint;
    final dollars = (cents / 100).toStringAsFixed(2);
    return '\$$dollars';
  }

  Future<void> _share() async {
    try {
      await Share.share(
        'Join me on DoraRide and we both benefit! Use my link: $link',
        subject: 'DoraRide referral',
      );
    } catch (_) {
      // If share fails (e.g., web), fallback: copy to clipboard
      await Clipboard.setData(ClipboardData(text: link));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link copied to clipboard')),
      );
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
  }

  Future<void> _simulateAddReferral() async {
    // In production, call referralRepo.redeemInstall(incomingCodeFromDeepLink)
    // Here we just credit the current user for demo.
    setState(() => loading = true);
    // Simulate: +10 points
    await referralRepo.redeemInstall('SOME-OTHER-CODE');
    final p = await referralRepo.getPoints();
    if (!mounted) return;
    setState(() {
      points = p;
      loading = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('+10 points added (demo)')),
    );
  }

  Future<void> _convertAll() async {
    if (points <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No points to convert')),
      );
      return;
    }
    setState(() => loading = true);
    try {
      final credited = await referralRepo.convertPointsToWallet(
        pointsToConvert: points,
        walletRepo: walletRepo,
      );
      final newPts = await referralRepo.getPoints();
      if (!mounted) return;
      setState(() {
        points = newPts;
        loading = false;
      });
      final dollars = (credited / 100).toStringAsFixed(2);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Converted to \$$dollars in your wallet')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Conversion failed: $e')),
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
        title: const Text('Refer a friend'),
        centerTitle: true,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: kGreen))
          : RefreshIndicator(
              onRefresh: _init,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _headline(),
                  const SizedBox(height: 12),
                  _linkCard(),
                  const SizedBox(height: 16),
                  _pointsCard(),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _convertAll,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle:
                          const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('Convert all points to wallet'),
                  ),
                  const SizedBox(height: 16),

                  // Dev/testing helper — remove/guard with kDebugMode when shipping
                  OutlinedButton.icon(
                    onPressed: _simulateAddReferral,
                    icon: const Icon(Icons.add),
                    label: const Text('Add referral (demo +10 points)'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _headline() => const Text(
        'Share your link. Earn rewards.',
        style: TextStyle(
          color: kNavy,
          fontWeight: FontWeight.w900,
          fontSize: 22,
        ),
      );

  Widget _linkCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your referral link',
                style: TextStyle(
                    color: kNavy, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    link,
                    style: const TextStyle(color: kNavy),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _copy,
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy, color: kNavy),
                ),
                IconButton(
                  onPressed: _share,
                  tooltip: 'Share',
                  icon: const Icon(Icons.share, color: kNavy),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Friends who install with your link give you +10 points.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      );

  Widget _pointsCard() {
    final cents = points * ReferralRepository.centsPerPoint;
    final dollars = (cents / 100).toStringAsFixed(2);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: kGreen.withOpacity(0.12),
            foregroundColor: kGreen,
            child: const Icon(Icons.stars),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your rewards',
                    style: TextStyle(
                        color: kNavy, fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  '$points points  •  ≈ \$$dollars',
                  style: const TextStyle(color: kNavy),
                ),
                const SizedBox(height: 4),
                const Text(
                  '1 point = \$0.10  •  10 points = \$1.00',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
