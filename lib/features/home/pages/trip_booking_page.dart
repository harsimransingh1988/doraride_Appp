import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:doraride_appp/app_router.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class TripBookingPage extends StatefulWidget {
  const TripBookingPage({
    super.key,
    required this.tripId,
    required this.from,
    required this.to,
    required this.dateString,
    required this.timeString,
    required this.price,
    required this.availableSeats,
    required this.driverName,
    required this.driverId,
    this.isPremiumSeatAvailable = false,
    this.premiumExtra = 0.0,
    this.extraLuggagePrice = 0.0,
    this.premiumSeatAlreadyTaken = false,
    this.driverVerified = false,
    this.peopleDriven = 0,
    this.currencyCode = 'CAD',
    this.currencySymbol = '\$',
  });

  final String tripId;
  final String from;
  final String to;
  final String dateString;
  final String timeString;
  final double price;
  final int availableSeats;
  final String driverName;
  final String driverId;
  final bool isPremiumSeatAvailable;
  final double premiumExtra;
  final double extraLuggagePrice;
  final bool premiumSeatAlreadyTaken;

  // NEW: passed from search page (driver badge)
  final bool driverVerified;
  final int peopleDriven; // NEW: people driven count

  // NEW: currency info from trip
  final String currencyCode;
  final String currencySymbol;

  static TripBookingPage fromArgs(Map a) {
    return TripBookingPage(
      tripId: (a['tripId'] ?? '').toString(),
      from: (a['from'] ?? '—').toString(),
      to: (a['to'] ?? '—').toString(),
      dateString: (a['dateString'] ?? '—').toString(),
      timeString: (a['timeString'] ?? '—').toString(),
      price: (a['price'] is num) ? (a['price'] as num).toDouble() : 0.0,
      availableSeats:
          (a['availableSeats'] is int) ? (a['availableSeats'] as int) : 1,
      driverName: (a['driverName'] ?? '—').toString(),
      driverId: (a['driverId'] ?? '').toString(),
      isPremiumSeatAvailable: (a['isPremiumSeatAvailable'] ?? false) as bool,
      premiumExtra: ((a['premiumExtra'] as num?)?.toDouble() ?? 0.0),
      extraLuggagePrice: ((a['extraLuggagePrice'] as num?)?.toDouble() ?? 0.0),
      premiumSeatAlreadyTaken: (a['frontSeatTaken'] ?? false) as bool,
      driverVerified: (a['driverVerified'] ?? false) as bool,
      peopleDriven: (a['peopleDriven'] is int) ? (a['peopleDriven'] as int) : 0,
      currencyCode: (a['currencyCode'] ?? 'CAD').toString(),
      currencySymbol: (a['currencySymbol'] ??
              ((a['currencyCode'] ?? 'CAD').toString() == 'INR' ? '₹' : '\$'))
          .toString(),
    );
  }

  @override
  State<TripBookingPage> createState() => _TripBookingPageState();
}

class _TripBookingPageState extends State<TripBookingPage> {
  // --- Booking State ---
  int _seats = 1;
  bool _isPayingFull = true;
  bool _submitting = false;

  // Add-on selections
  bool _premiumSeatSelected = false;
  int _extraLuggageCount = 0;

  // --- Data State ---
  bool _authCheckComplete = false;
  late final Future<DocumentSnapshot<Map<String, dynamic>>> _tripDataFuture;

  // NEW: driver profile data
  late final Future<DocumentSnapshot<Map<String, dynamic>>> _driverDataFuture;

  // SIMPLIFIED PRICE CALCULATIONS
  double get _baseTotal => widget.price * _seats;
  double get _premiumTotal => _premiumSeatSelected ? widget.premiumExtra : 0.0;
  double get _luggageTotal => widget.extraLuggagePrice * _extraLuggageCount;
  double get _fullTotal => _baseTotal + _premiumTotal + _luggageTotal;

  // Currency helpers
  String get _currencySymbol =>
      widget.currencySymbol.isNotEmpty
          ? widget.currencySymbol
          : (widget.currencyCode == 'INR' ? '₹' : '\$');

  String _fmtMoney(double v) => '$_currencySymbol${v.toStringAsFixed(2)}';

  @override
  void initState() {
    super.initState();
    _runAuthCheckAndInitialize();
    _tripDataFuture = FirebaseFirestore.instance
        .collection('trips')
        .doc(widget.tripId)
        .get();

    // NEW: load driver profile
    _driverDataFuture = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.driverId)
        .get();

    if (widget.premiumSeatAlreadyTaken) {
      _premiumSeatSelected = false;
    }
  }

  Future<void> _runAuthCheckAndInitialize() async {
    if (mounted) setState(() => _authCheckComplete = true);
  }

  Future<void> _startChat() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to message a driver.')),
      );
      return;
    }

    final currentUserId = currentUser.uid;

    if (currentUserId == widget.driverId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot message yourself.')),
      );
      return;
    }

    final participants = [currentUserId, widget.driverId]..sort();
    final chatId = '${widget.tripId}_${participants.join('_')}';

    final chatRef =
        FirebaseFirestore.instance.collection('conversations').doc(chatId);
    final chatDoc = await chatRef.get();

    if (!chatDoc.exists) {
      await chatRef.set({
        'participants': participants,
        'tripId': widget.tripId,
        'createdAt': FieldValue.serverTimestamp(),
        'mapRead': {currentUserId: true, widget.driverId: false},
        'lastAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
      });
    }

    if (!mounted) return;
    Navigator.pushNamed(
      context,
      Routes.chatScreen,
      arguments: {
        'chatId': chatId,
        'recipientId': widget.driverId,
        'segmentFrom': widget.from,
        'segmentTo': widget.to,
      },
    );
  }

  // 👉 NEW: open driver profile page from booking screen
  void _openDriverProfile() {
    if (widget.driverId.isEmpty) return;
    Navigator.of(context).pushNamed(
      Routes.viewDriverProfile,
      arguments: {
        'driverId': widget.driverId,
        'driverName': widget.driverName,
        // if you want, you can pass vehicle info later
        'vehicleInfo': '',
      },
    );
  }

  Future<void> _continueToBooking() async {
    if (!mounted) return;

    Navigator.of(context).pushNamed(
      Routes.tripPaymentFinal,
      arguments: {
        'tripId': widget.tripId,
        'from': widget.from,
        'to': widget.to,
        'dateString': widget.dateString,
        'timeString': widget.timeString,
        'price': widget.price,
        'availableSeats': widget.availableSeats,
        'driverName': widget.driverName,
        'driverId': widget.driverId,
        'initialSeats': _seats,
        'initialPaymentFull': true,
        'premiumSeatSelected': _premiumSeatSelected,
        'premiumExtra': widget.premiumExtra,
        'extraLuggageCount': _extraLuggageCount,
        'extraLuggagePrice': widget.extraLuggagePrice,
        'currencyCode': widget.currencyCode,
        'currencySymbol': widget.currencySymbol,
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: _kThemeBlue,
            ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: _kThemeBlue),
            const SizedBox(width: 8),
          ],
          Text(
            '$label:',
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: Colors.black87),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  // NEW: driver summary card
  Widget _buildDriverSummary(Map<String, dynamic> userData) {
    final photoUrl = (userData['photoUrl'] ??
            userData['profilePhotoUrl'] ??
            userData['avatarUrl'] ??
            '')
        .toString();

    final bool driverVerified =
        (userData['isVerified'] == true) ||
            (userData['driverVerified'] == true) ||
            (userData['isDriverVerified'] == true) ||
            (userData['isVerifiedDriver'] == true) ||
            (userData['accountVerified'] == true) ||
            (userData['verificationStatus'] == 'verified') ||
            (userData['driverStatus'] == 'verified') ||
            widget.driverVerified;

    final double rating =
        (userData['rating'] is num) ? (userData['rating'] as num).toDouble() : 5.0;

    final int ratingCount =
        (userData['ratingCount'] ??
                userData['reviewsCount'] ??
                userData['completedTrips'] ??
                0) as int;

    int peopleDriven = widget.peopleDriven;
    if (peopleDriven == 0) {
      peopleDriven = (userData['peopleDriven'] ?? ratingCount) as int;
    }

    // ⬇️ Make entire card tappable to open driver profile
    return InkWell(
      onTap: _openDriverProfile,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: _kThemeBlue.withOpacity(0.08),
                backgroundImage:
                    photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                child: photoUrl.isEmpty
                    ? Text(
                        widget.driverName.isNotEmpty
                            ? widget.driverName[0].toUpperCase()
                            : 'D',
                        style: const TextStyle(
                            color: _kThemeBlue, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.driverName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: _kThemeBlue,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (driverVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified,
                            size: 18,
                            color: _kThemeGreen,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, size: 22, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(
                        rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: _kThemeBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$peopleDriven people driven',
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: _openDriverProfile,
                icon: const Icon(Icons.chevron_right, color: _kThemeBlue),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_authCheckComplete || widget.tripId.isEmpty) {
      if (widget.tripId.isEmpty) {
        return Scaffold(
          appBar: AppBar(title: const Text('Trip Booking')),
          body: const Center(
              child:
                  Text('Error: Cannot load trip. A valid Trip ID is missing.')),
        );
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _tripDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Trip Booking'),
              backgroundColor: _kThemeBlue,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Trip Booking'),
              backgroundColor: _kThemeBlue,
            ),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Text(
                  'Error loading trip details. Trip may have been canceled or deleted.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ),
          );
        }

        final tripData = snapshot.data!.data()!;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Trip Booking'),
            backgroundColor: _kThemeBlue,
          ),
          backgroundColor: _kThemeGreen,
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  children: [
                    // Minimal header
                    Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: _kThemeGreen.withOpacity(.12),
                              child:
                                  const Icon(Icons.route, color: _kThemeGreen),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${widget.from} → ${widget.to}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: _kThemeBlue,
                                      )),
                                  const SizedBox(height: 4),
                                  Text(
                                      '${widget.dateString} at ${widget.timeString}',
                                      style: TextStyle(
                                        color: Colors.black.withOpacity(.65),
                                        fontWeight: FontWeight.w600,
                                      )),
                                  const SizedBox(height: 4),

                                  // ⬇️ NOW TAPPABLE: opens driver profile page
                                  GestureDetector(
                                    onTap: _openDriverProfile,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Driver: ${widget.driverName}',
                                          style: TextStyle(
                                            color: Colors.black
                                                .withOpacity(.65),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.chevron_right,
                                          size: 18,
                                          color: _kThemeBlue,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: _startChat,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _kThemeBlue,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.chat_bubble_outline,
                                        color: Colors.white, size: 18),
                                    SizedBox(width: 6),
                                    Text(
                                      'Chat',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Driver summary card
                    FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: _driverDataFuture,
                      builder: (context, driverSnap) {
                        if (driverSnap.connectionState ==
                            ConnectionState.waiting) {
                          return const SizedBox.shrink();
                        }
                        if (!driverSnap.hasData || !driverSnap.data!.exists) {
                          return const SizedBox.shrink();
                        }
                        final driverData = driverSnap.data!.data()!;
                        return _buildDriverSummary(driverData);
                      },
                    ),

                    _buildAddOnsSection(),
                    _buildPriceSummary(),
                    _buildItinerary(tripData),
                    _buildVehicleDetails(tripData),
                    _buildPreferencesAndDescription(tripData),

                    const SizedBox(height: 24),
                  ],
                ),
              ),

              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _continueToBooking,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kThemeBlue,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        'Continue to Payment (${_fmtMoney(_fullTotal)})',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ... rest of the widget methods remain unchanged
  Widget _buildAddOnsSection() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Available Add-ons'),

            if (widget.premiumSeatAlreadyTaken &&
                widget.isPremiumSeatAvailable)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.event_seat, color: Colors.grey),
                title: Text(
                  'Premium Front Seat',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                subtitle: Text('Already booked by another rider.'),
              ),

            if (widget.isPremiumSeatAvailable &&
                !widget.premiumSeatAlreadyTaken) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_seat, color: _kThemeBlue),
                title: const Text('Premium Front Seat',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    'Extra legroom and comfort • +${_fmtMoney(widget.premiumExtra)}'),
                trailing: Switch(
                  value: _premiumSeatSelected,
                  onChanged: (value) {
                    setState(() => _premiumSeatSelected = value);
                  },
                  activeColor: _kThemeBlue,
                ),
              ),
              if (widget.extraLuggagePrice > 0) const Divider(height: 1),
            ],

            if (widget.extraLuggagePrice > 0)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.luggage, color: _kThemeBlue),
                title: const Text('Extra Luggage',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    '+${_fmtMoney(widget.extraLuggagePrice)} per item'),
                trailing: SizedBox(
                  width: 120,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 24),
                        onPressed: _extraLuggageCount > 0
                            ? () => setState(() => _extraLuggageCount--)
                            : null,
                      ),
                      SizedBox(
                        width: 30,
                        child: Center(
                          child: Text('$_extraLuggageCount',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 16)),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 24),
                        onPressed: () =>
                            setState(() => _extraLuggageCount++),
                      ),
                    ],
                  ),
                ),
              ),

            if (_premiumSeatSelected || _extraLuggageCount > 0) ...[
              const Divider(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kThemeGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Add-ons Total:',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      _fmtMoney(_premiumTotal + _luggageTotal),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _kThemeGreen,
                          fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],

            if (!widget.isPremiumSeatAvailable &&
                widget.extraLuggagePrice <= 0)
              const Text('No additional add-ons available for this trip.',
                  style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildItinerary(Map<String, dynamic> data) {
    final origin = (data['origin'] ?? '—').toString();
    final destination = (data['destination'] ?? '—').toString();
    final stopsData = (data['stops'] as List<dynamic>?) ?? [];

    final stops = stopsData
        .map((s) => s is Map ? (s['location'] ?? '').toString() : s.toString())
        .where((s) => s.isNotEmpty)
        .toList();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Trip Itinerary'),

            Row(
              children: [
                const Icon(Icons.my_location, size: 20, color: _kThemeGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    origin,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: _kThemeBlue),
                  ),
                ),
              ],
            ),

            ...stops.map((stop) => Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      margin:
                          const EdgeInsets.only(left: 2, top: 4, bottom: 4),
                      child: const VerticalDivider(
                          color: Colors.grey, thickness: 1.5, width: 4),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stop,
                        style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.black87),
                      ),
                    ),
                  ],
                )),

            Row(
              children: [
                const Icon(Icons.location_on, size: 20, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    destination,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: _kThemeBlue),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleDetails(Map<String, dynamic> data) {
    final company = (data['carCompany'] ?? 'N/A').toString();
    final model = (data['carModel'] ?? 'N/A').toString();
    final year = (data['carYear'] ?? 'N/A').toString();
    final color = (data['carColor'] ?? 'N/A').toString();
    final plate = (data['carPlate'] ?? 'N/A').toString();
    final photoUrl = (data['carPhotoUrl'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Vehicle Details'),
            _buildDetailRow('Car', '$company $model',
                icon: Icons.directions_car),
            _buildDetailRow('Year', year, icon: Icons.calendar_today),
            _buildDetailRow('Color', color, icon: Icons.color_lens),
            _buildDetailRow('Plate', plate, icon: Icons.confirmation_number),

            if (photoUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            _FullScreenImageView(url: photoUrl),
                      ));
                    },
                    child: Hero(
                      tag: 'carPhoto_$photoUrl',
                      child: Image.network(
                        photoUrl,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.directions_car, size: 40),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferencesAndDescription(Map<String, dynamic> data) {
    final pets = (data['allowsPets'] ?? false) ? 'Yes' : 'No';
    final luggage = (data['luggageSize'] ?? 'M').toString();
    final desc =
        (data['description'] ?? 'No description provided.').toString();

    final int backRowLimit = (data['backRowLimit'] is int)
        ? (data['backRowLimit'] as int)
        : (data['backRow'] as int? ?? 3);
    final seatsConstraint =
        (backRowLimit == 2) ? 'Max 2 in back row' : 'Up to 3 in back row';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Trip Preferences'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                    width: MediaQuery.of(context).size.width * 0.4,
                    child: _buildDetailRow('Pets Allowed', pets,
                        icon: Icons.pets)),
                SizedBox(
                    width: MediaQuery.of(context).size.width * 0.4,
                    child: _buildDetailRow('Max Luggage', luggage,
                        icon: Icons.luggage)),
              ],
            ),
            _buildDetailRow('Seating', seatsConstraint,
                icon: Icons.airline_seat_recline_extra),
            const Divider(height: 24),
            _buildSectionHeader('Notes from Driver'),
            Text(desc, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceSummary() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Price Breakdown'),
            _buildPriceRow(
                'Base Price',
                '${_fmtMoney(widget.price)} × $_seats seat(s)',
                _fmtMoney(_baseTotal)),
            if (_premiumSeatSelected)
              _buildPriceRow(
                  'Premium Seat',
                  '+${_fmtMoney(widget.premiumExtra)}',
                  '+${_fmtMoney(_premiumTotal)}'),
            if (_extraLuggageCount > 0)
              _buildPriceRow(
                  'Extra Luggage',
                  '$_extraLuggageCount × ${_fmtMoney(widget.extraLuggagePrice)}',
                  '+${_fmtMoney(_luggageTotal)}'),
            const Divider(height: 16),
            _buildPriceRow('Total Amount', '', _fmtMoney(_fullTotal),
                isTotal: true),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceRow(String label, String description, String amount,
      {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
                      fontSize: isTotal ? 16 : 14,
                      color: isTotal ? _kThemeBlue : Colors.black87,
                    )),
                if (description.isNotEmpty)
                  Text(description,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(amount,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: isTotal ? FontWeight.w900 : FontWeight.w600,
                  fontSize: isTotal ? 18 : 14,
                  color: isTotal ? _kThemeGreen : Colors.black87,
                )),
          ),
        ],
      ),
    );
  }
}

/// Simple full-screen viewer for car images (no external packages)
class _FullScreenImageView extends StatelessWidget {
  final String url;
  const _FullScreenImageView({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title:
            const Text('Vehicle photo', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: Hero(
          tag: 'carPhoto_$url',
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, color: Colors.white, size: 56),
            ),
          ),
        ),
      ),
    );
  }
}
