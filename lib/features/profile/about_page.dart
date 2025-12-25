import 'package:flutter/material.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const kGreen = Color(0xFF279C56);
  static const kNavy = Color(0xFF180D3B);
  static const kBg = Color(0xFFF4F7F5);

  Widget _sectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: kGreen, size: 22),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: kNavy,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paragraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black87,
          height: 1.5,
          fontSize: 15.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text("About Us – DoraRide"),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Row(
                  children: [
                    const Icon(Icons.directions_car_rounded,
                        color: kGreen, size: 26),
                    const SizedBox(width: 10),
                    const Text(
                      "About DoraRide",
                      style: TextStyle(
                        color: kNavy,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                _paragraph(
                    "At DoraRide, we believe that every journey should be more than just travel — it should be an experience of connection, comfort, and care for the planet."),
                _paragraph(
                    "We are a smart carpooling platform designed to bring people together on the road. Whether you’re heading to work, college, or a weekend trip, DoraRide makes it easy to share rides, save money, and reduce your carbon footprint — all while meeting new people along the way."),
                _paragraph(
                    "Our vision started with a simple idea: if millions of empty car seats move every day, why not fill them with people going the same way? DoraRide transforms everyday commuting into a shared, sustainable, and social experience."),
                _paragraph(
                    "With DoraRide, you can offer a ride as a driver, find a ride as a passenger, or simply explore routes — all with trust, transparency, and ease."),
                const SizedBox(height: 10),
                const Text(
                  "“Ride Smart. Ride Together. Smile on Every Ride.”",
                  style: TextStyle(
                    color: kGreen,
                    fontStyle: FontStyle.italic,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),

                // Mission
                _sectionTitle("Our Mission", Icons.eco_rounded),
                _paragraph(
                    "To make travel smarter, greener, and more connected by creating a trusted platform where drivers and passengers can easily share rides, reduce travel costs, and make a positive impact on the environment."),
                _paragraph(
                    "We aim to build a strong community that values sustainability, collaboration, and shared journeys, turning every trip into an opportunity to connect and care."),

                // Vision
                _sectionTitle("Our Vision", Icons.public_rounded),
                _paragraph(
                    "To become the most trusted community carpooling network that redefines how people move — transforming mobility into a shared, joyful, and sustainable experience for everyone."),
                _paragraph(
                    "We envision a future where every empty car seat becomes a chance to build connections, cut emissions, and make travel happier for all."),

                const SizedBox(height: 20),

                // Footer
                const Divider(),
                const SizedBox(height: 10),
                const Center(
                  child: Text(
                    "© 2025 DoraRide – All rights reserved",
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
