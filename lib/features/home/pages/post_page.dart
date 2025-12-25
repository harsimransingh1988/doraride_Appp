// lib/features/home/pages/post_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app_router.dart';
import 'need_ride_page.dart';
import 'offer_ride_page.dart';
import 'offer_ride_gate_page.dart'; // ✅ Gate for driver licence / status check

enum TripType { offer, request }
enum TripStatus { active, recent, cancelled }

class PostedTrip {
  final String id;
  final TripType type;
  final String origin;
  final String destination;
  final DateTime postedAt;
  TripStatus status;

  PostedTrip({
    required this.id,
    required this.type,
    required this.origin,
    required this.destination,
    required this.postedAt,
    this.status = TripStatus.active,
  });
}

List<PostedTrip> _inMemoryTrips = [];

class PostPage extends StatelessWidget {
  const PostPage({super.key});

  Future<bool> _isGuest() async {
    final prefs = await SharedPreferences.getInstance();
    // ✅ uses is_guest flag (guest only)
    return prefs.getBool('is_guest') == true;
  }

  void _showRegisterPrompt(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Account Required'),
        content: const Text(
          'Please register or sign in to post a trip. '
          'As a guest, you can only view available options on the main feed (if implemented).',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushNamed(Routes.register);
            },
            child: const Text('Register Now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveTripToFirestore(Map<String, dynamic> tripData) async {
    // 🔹 currently mock implementation
    debugPrint(
      'MOCK: Trip saved to pseudo-Firestore: '
      '${tripData['origin']} to ${tripData['destination']}',
    );
  }

  Future<String?> _showSuccessDialog(BuildContext context, String type) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Post Successful!'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Your ride has been posted successfully.'),
                SizedBox(height: 10),
                Text('You will now be taken to the Active Trips tab.'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(dialogContext).pop('trips');
              },
            ),
          ],
        );
      },
    );
    return result;
  }

  Future<void> _navigateToForm(BuildContext context, String targetRoute) async {
    // 1) Guest check
    if (await _isGuest()) {
      _showRegisterPrompt(context);
      return;
    }

    Object? result;

    if (targetRoute == Routes.postOffer) {
      // ✅ Always go through gate (driverStatus + licence + rejected check)
      result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const OfferRideGatePage(),
        ),
      );
    } else {
      // "Need a ride" (no driver gate)
      final formPageWidget = _getFormWidget(targetRoute);
      result = await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => formPageWidget),
      );
    }

    // 2) Handle returned data (only if a trip was actually created)
    if (result != null && result is Map<String, dynamic>) {
      final firestoreData = {
        'origin': result['origin'] as String,
        'destination': result['destination'] as String,
        'type': result['type'] as String,
        'status': TripStatus.active.toString().split('.').last,
      };

      // Local in-memory list for UI
      _inMemoryTrips.insert(
        0,
        PostedTrip(
          id: 'MOCK_ID_${DateTime.now().millisecondsSinceEpoch}',
          type: firestoreData['type'] == 'offer'
              ? TripType.offer
              : TripType.request,
          origin: firestoreData['origin'] as String,
          destination: firestoreData['destination'] as String,
          postedAt: DateTime.now(),
          status: TripStatus.active,
        ),
      );

      await _saveTripToFirestore(firestoreData);

      final destinationSignal =
          await _showSuccessDialog(context, firestoreData['type'] as String);

      if (destinationSignal == 'trips' && Navigator.of(context).canPop()) {
        // Signal HomeShell to switch to Trips tab
        Navigator.of(context).pop('trips');
      }
    }
  }

  Widget _getFormWidget(String routeName) {
    if (routeName == Routes.postNeed) {
      return NeedRidePage();
    }
    if (routeName == Routes.postOffer) {
      // not used when going via gate, but kept for safety / direct access
      return OfferRidePage();
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'What are you looking to post?',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              _ChoiceCard(
                title: 'Need a ride',
                subtitle: 'Post a ride request so drivers can invite you.',
                icon: Icons.hail,
                onTap: () {
                  _navigateToForm(context, Routes.postNeed);
                },
              ),
              const SizedBox(height: 16),
              _ChoiceCard(
                title: 'Offer a ride',
                subtitle: 'Driving somewhere? Post seats for passengers.',
                icon: Icons.directions_car,
                onTap: () {
                  // ✅ goes through OfferRideGatePage (with rejected/pending logic)
                  _navigateToForm(context, Routes.postOffer);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _ChoiceCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              child: Icon(icon, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
