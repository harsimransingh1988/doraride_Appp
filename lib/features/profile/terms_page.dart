import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class TermsPage extends StatefulWidget {
  const TermsPage({super.key});

  @override
  State<TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends State<TermsPage> {
  static const kGreen = Color(0xFF279C56);
  static const kBg = Color(0xFFF4F7F5);

  // Use the .html link
  static const _termsUrl = 'https://doraride.com/terms-and-conditions.html';

  WebViewController? _controller;
  bool _loading = !kIsWeb; 

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      // Mobile Logic (WebView)
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              if (mounted) setState(() => _loading = false);
            },
          ),
        )
        ..loadRequest(Uri.parse(_termsUrl));
    } else {
      // Web Logic: Force open in NEW TAB to prevent Flutter routing issues
      Future.microtask(() async {
        await launchUrl(
          Uri.parse(_termsUrl),
          // '_blank' forces a new tab. '_self' allows Flutter to intercept it.
          webOnlyWindowName: '_blank', 
          mode: LaunchMode.externalApplication,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        title: const Text('Terms & Conditions'),
        centerTitle: true,
      ),
      body: kIsWeb
          ? const Center(
              child: Text(
                'Opening Terms & Conditions in new tab...',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          : Stack(
              children: [
                if (_controller != null) WebViewWidget(controller: _controller!),
                if (_loading)
                  const Center(child: CircularProgressIndicator(color: kGreen)),
              ],
            ),
      bottomNavigationBar: kIsWeb
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: ElevatedButton.icon(
                // Button also updated to use '_blank'
                onPressed: () => launchUrl(
                  Uri.parse(_termsUrl),
                  webOnlyWindowName: '_blank',
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Terms in new tab'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}