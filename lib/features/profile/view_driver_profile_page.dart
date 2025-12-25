// lib/features/profile/view_driver_profile_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Theme dark blue from your app (used for AppBar and text)
const _kThemeBlue = Color(0xFF180D3B);
// Theme green (used for rating icon)
const _kThemeGreen = Color(0xFF279C56);

class ViewDriverProfilePage extends StatelessWidget {
  final String driverId;

  const ViewDriverProfilePage({super.key, required this.driverId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Profile'),
        backgroundColor: _kThemeBlue,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        // 1. Fetch the driver's user document using the passed ID
        future: FirebaseFirestore.instance.collection('users').doc(driverId).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error loading profile: ${snapshot.error}'));
          }

          // Check if data exists
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Driver profile not found.'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          
          // Extract key profile details (Use dummy values if fields are missing)
          final driverName = (data['displayName'] ?? 'Unknown Driver') as String;
          final driverRating = (data['rating'] ?? 4.5).toString();
          final vehicleModel = (data['carModel'] ?? 'Vehicle Not Listed') as String;
          final vehicleColor = (data['carColor'] ?? 'Not Specified') as String;

          // Replace placeholder body with actual UI content
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Driver Name and Rating Card
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 30,
                          child: Text('DR', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              driverName,
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: _kThemeBlue),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.star, color: _kThemeGreen, size: 20),
                                const SizedBox(width: 4),
                                Text(
                                  '$driverRating Rating',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: _kThemeGreen),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),

                // Vehicle Details Section
                Text(
                  'Vehicle Information',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: _kThemeBlue),
                ),
                const Divider(height: 16, thickness: 1),
                
                _DetailRow(
                  label: 'Model/Make:',
                  value: vehicleModel,
                ),
                _DetailRow(
                  label: 'Color:',
                  value: vehicleColor,
                ),
                _DetailRow(
                  label: 'Driver ID:',
                  value: driverId,
                  icon: Icons.vpn_key_outlined,
                ),
                
                const SizedBox(height: 24),
                
                // Placeholder for Reviews/Bio
                Text(
                  'About the Driver',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: _kThemeBlue),
                ),
                const Divider(height: 16, thickness: 1),
                const Text(
                  'This section will include the driver\'s bio, preferences (pets/luggage), and passenger reviews once implemented.',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Helper Widget for detail rows
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  const _DetailRow({required this.label, required this.value, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? Icons.info_outline, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}