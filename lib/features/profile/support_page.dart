import 'package:flutter/material.dart';

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF176E3C), // DoraRide green
      appBar: AppBar(
        backgroundColor: const Color(0xFF180D3B), // DoraRide blue
        title: const Text(
          'Support',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text(
                'Need Help?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'We’re here to make your DoraRide experience smooth. Choose an option below or contact us directly.',
                style: TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 30),

              _supportOption(
                icon: Icons.chat_bubble_outline,
                title: 'Chat with Support',
                subtitle: 'Get instant help from our team.',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Chat support coming soon!')),
                  );
                },
              ),
              _supportOption(
                icon: Icons.mail_outline,
                title: 'Email Us',
                subtitle: 'support@doraride.com',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Email: support@doraride.com')),
                  );
                },
              ),
              _supportOption(
                icon: Icons.help_outline,
                title: 'FAQs',
                subtitle: 'Find answers to common questions.',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('FAQ section coming soon!')),
                  );
                },
              ),
              _supportOption(
                icon: Icons.feedback_outlined,
                title: 'Send Feedback',
                subtitle: 'Tell us how we can improve.',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Feedback form coming soon!')),
                  );
                },
              ),

              const SizedBox(height: 40),
              Center(
                child: Text(
                  'Ride Smart. Ride Together. Smile on Every Ride.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontStyle: FontStyle.italic,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _supportOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF176E3C)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}
