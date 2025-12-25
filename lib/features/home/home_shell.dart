// lib/features/home/home_shell.dart
import 'package:flutter/material.dart';

// --- Firebase + routes ---
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:doraride_appp/app_router.dart';

// ✅ ADDED for currency saving
import 'package:shared_preferences/shared_preferences.dart';
import 'package:doraride_appp/services/currency_service.dart';

// Tabs shown in the bottom navigation bar
import 'pages/search_page.dart';
import 'pages/post_page.dart';
import 'pages/trips_page.dart';
import 'pages/messages_page.dart';
import 'pages/help_page.dart';

const _kThemeBlue = Color(0xFF180D3B);

class HomeShell extends StatefulWidget {
  /// Option 1: You can programmatically select a starting tab
  final int initialIndex;

  const HomeShell({super.key, this.initialIndex = 0});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _currentIndex;

  // Consume route args exactly once
  bool _argsConsumed = false;

  // Track if we've already checked for reviews
  bool _reviewCheckPerformed = false;

  // ✅ ADDED: only run currency detect once per app session
  bool _currencyCheckPerformed = false;

  // Preserve state per tab
  final List<Widget> _pages = const [
    SearchPage(),   // 0
    PostPage(),     // 1
    TripsPage(),    // 2
    MessagesPage(), // 3
    HelpPage(),     // 4
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex; // constructor wins first

    // Check for pending reviews after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForPendingReviews();

      // ✅ ADDED: detect + save currency once (GPS -> locale fallback)
      _ensureCurrencySaved();
    });
  }

  // ✅ ADDED: Save currency based on location/locale
  Future<void> _ensureCurrencySaved() async {
    if (_currencyCheckPerformed) return;
    _currencyCheckPerformed = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString('currency_code');
      if (existing != null && existing.trim().isNotEmpty) return;

      // 1) Try GPS country code
      final ccGps = await CurrencyService.detectCountryCodeFromGPS();

      // 2) Fallback: device locale country code
      final ccLocale = CurrencyService.countryCodeFromLocale(context);

      final countryCode = (ccGps ?? ccLocale ?? 'US').toUpperCase();
      final currencyCode = CurrencyService.currencyFromCountry(countryCode);

      await prefs.setString('country_code', countryCode);
      await prefs.setString('currency_code', currencyCode);

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'countryCode': countryCode,
        'currencyCode': currencyCode,
        'currencyUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Currency detect/save failed: $e');
    }
  }

  /// STREAM: total unread messages across all conversations for current user
  Stream<int> _unreadMessagesStream(String uid) {
    return FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snap) {
      int total = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final unread = data['unreadCount'] as Map<String, dynamic>?;
        if (unread == null) continue;
        final myCount = unread[uid];
        if (myCount is int) {
          total += myCount;
        }
      }

      // Debug: see totals in browser console
      // ignore: avoid_print
      print('🔔 DoraRide unread total for $uid = $total');
      return total;
    });
  }

  /// Checks for an unrated completed booking for the current user (as rider)
  Future<void> _checkForPendingReviews() async {
    // Only run this check once per app session
    if (_reviewCheckPerformed) return;
    _reviewCheckPerformed = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return; // Not signed in

    try {
      // One completed booking that hasn't been rated by the rider
      final query = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('my_bookings')
          .where('status', isEqualTo: 'completed')
          .where('isRiderRated', isNotEqualTo: true) // finds null or false
          .limit(1);

      final snapshot = await query.get();

      if (snapshot.docs.isNotEmpty && mounted) {
        final bookingToRate = snapshot.docs.first;
        final bookingData = bookingToRate.data();

        final String driverId = bookingData['driverId'] ?? '';
        final String driverName = bookingData['driverName'] ?? 'the driver';
        final String tripId = bookingData['tripId'] ?? '';
        final String bookingId = bookingToRate.id;

        if (driverId.isEmpty || tripId.isEmpty) return;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text("Rate Your Trip"),
              content: Text(
                "You had a completed trip with $driverName. Would you like to leave a review?",
              ),
              actions: [
                TextButton(
                  child: const Text("Later"),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                FilledButton(
                  child: const Text("Rate Now"),
                  onPressed: () {
                    Navigator.of(dialogContext).pop(); // Close dialog
                    Navigator.of(context).pushNamed(
                      Routes.rateTrip,
                      arguments: {
                        'bookingId': bookingId,
                        'tripId': tripId,
                        'recipientId': driverId,
                        'recipientName': driverName,
                        'role': 'rider',
                      },
                    );
                  },
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      // Fail silently. Don't block the app for a review check.
      debugPrint('Error checking for pending reviews: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsConsumed) return;

    // Allow route arguments to select a tab (string 'trips' or {'tab':'trips'})
    final args = ModalRoute.of(context)?.settings.arguments;
    String? tab;
    if (args is Map && args['tab'] is String) {
      tab = args['tab'] as String;
    } else if (args is String) {
      tab = args;
    }

    if (tab != null) {
      switch (tab) {
        case 'search':
          _currentIndex = 0;
          break;
        case 'post':
          _currentIndex = 1;
          break;
        case 'trips':
          _currentIndex = 2;
          break;
        case 'messages':
          _currentIndex = 3;
          break;
        case 'help':
          _currentIndex = 4;
          break;
        // NOTE: No 'profile' case here; Profile is not a HomeShell tab.
        default:
          break;
      }
      _argsConsumed = true;
      setState(() {});
    }
  }

  Future<void> _onItemTapped(int index) async {
    // Intercept "Post" tab to open as a pushed flow if needed
    if (index == 1) {
      final result = await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PostPage()),
      );
      if (result == 'trips') {
        setState(() => _currentIndex = 2);
      }
      return;
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        selectedItemColor: _kThemeBlue,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            label: 'Post',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.directions_car_outlined),
            label: 'Trips',
          ),

          // 🔔 Messages tab with unread badge
          BottomNavigationBarItem(
            label: 'Messages',
            icon: uid == null
                ? const Icon(Icons.mail_outline)
                : StreamBuilder<int>(
                    stream: _unreadMessagesStream(uid),
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;

                      if (count == 0) {
                        return const Icon(Icons.mail_outline);
                      }

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.mail_outline),
                          Positioned(
                            right: -6,
                            top: -6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.all(
                                  Radius.circular(10),
                                ),
                              ),
                              child: Text(
                                count > 9 ? '9+' : '$count',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),

          const BottomNavigationBarItem(
            icon: Icon(Icons.help_outline),
            label: 'Help',
          ),
        ],
      ),
    );
  }
}
