import 'package:flutter/material.dart';

class CloseAccountPage extends StatefulWidget {
  const CloseAccountPage({super.key});

  @override
  State<CloseAccountPage> createState() => _CloseAccountPageState();
}

class _CloseAccountPageState extends State<CloseAccountPage> {
  static const kGreen = Color(0xFF279C56);
  static const kNavy = Color(0xFF180D3B);
  static const kBg = Color(0xFFF4F7F5);

  final List<_Reason> _reasons = [
    _Reason('I have privacy concerns'),
    _Reason('I found another service'),
    _Reason('Too few rides in my area'),
    _Reason('Issues with payments'),
    _Reason('Technical problems / bugs'),
    _Reason('Other'),
  ];

  final TextEditingController _feedbackCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  bool _understandDelete = false;
  bool _sending = false;

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );

  Future<void> _exportData() async {
    // TODO: Implement export (e.g., call backend to generate export and email link)
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('We’ll email you a copy of your data.')),
    );
  }

  Future<void> _deactivateAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate account?'),
        content: const Text(
          'You can reactivate anytime by logging in again. '
          'Your trips and wallet remain intact.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Deactivate')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _sending = true);
    // TODO: backend call to mark account inactive and record reasons/feedback
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _sending = false);

    // TODO: clear local session if needed
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your account has been deactivated.')),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
    }
  }

  Future<void> _deleteAccount() async {
    if (!_understandDelete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please confirm you understand deletion is permanent.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permanently delete account?'),
        content: const Text(
          'This will permanently remove your account and data where legally permitted. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete forever', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _sending = true);

    // Example payload you might send:
    final payload = {
      'reasons': _reasons.where((r) => r.selected).map((r) => r.label).toList(),
      'feedback': _feedbackCtrl.text.trim(),
      'password': _passwordCtrl.text, // if required by backend for re-auth
      'acknowledged': _understandDelete,
    };

    // TODO: backend call to permanently delete account with `payload`
    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;
    setState(() => _sending = false);

    // TODO: clear auth/session
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your account was deleted.')),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/welcome', (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        title: const Text('Close account'),
        centerTitle: true,
      ),
      body: AbsorbPointer(
        absorbing: _sending,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('We’re sorry to see you go',
                      style: TextStyle(
                        color: kNavy,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      )),
                  SizedBox(height: 6),
                  Text(
                    'Before you leave, please tell us why. Your feedback helps improve DoraRide.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('Reasons'),
                  const SizedBox(height: 6),
                  ..._reasons.map((r) => CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: r.selected,
                        onChanged: (v) => setState(() => r.selected = v ?? false),
                        title: Text(r.label,
                            style: const TextStyle(
                              color: kNavy,
                              fontWeight: FontWeight.w600,
                            )),
                      )),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _feedbackCtrl,
                    maxLines: 4,
                    decoration: _dec('Additional feedback (optional)'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('Export your data'),
                  const SizedBox(height: 6),
                  const Text(
                    'You can request a copy of your data for your records before closing your account.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _exportData,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Request export'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kNavy,
                      side: const BorderSide(color: kNavy),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('Security check'),
                  const SizedBox(height: 6),
                  const Text(
                    'For your security, you may be asked to confirm your password again.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    decoration: _dec('Confirm password (if required)'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Actions
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('Choose an action'),
                  const SizedBox(height: 12),
                  // Deactivate
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _sending ? null : _deactivateAccount,
                      icon: const Icon(Icons.pause_circle_outline),
                      label: Text(_sending ? 'Processing…' : 'Deactivate account'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Divider(),
                  const SizedBox(height: 10),

                  // Delete permanently
                  const Text(
                    'Permanent deletion',
                    style: TextStyle(
                      color: kNavy,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'This will permanently delete your account and data (where legally permitted). '
                    'Wallet balance may be forfeited if not withdrawn.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _understandDelete,
                    onChanged: (v) => setState(() => _understandDelete = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'I understand this cannot be undone.',
                      style: TextStyle(color: kNavy, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _sending ? null : _deleteAccount,
                      icon: const Icon(Icons.delete_forever_outlined, color: Colors.red),
                      label: Text(
                        _sending ? 'Deleting…' : 'Delete my account permanently',
                        style: const TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  static const kNavy = _CloseAccountPageState.kNavy;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: kNavy,
        fontWeight: FontWeight.w900,
        fontSize: 16,
      ),
    );
  }
}

class _Reason {
  _Reason(this.label);
  final String label;
  bool selected = false;
}
