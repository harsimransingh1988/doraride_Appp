// lib/features/home/pages/driver_profile_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:doraride_appp/app_router.dart';
import 'package:doraride_appp/services/chat_service.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class DriverProfilePage extends StatefulWidget {
  final String driverId;
  final String? driverName;
  final String? vehicleInfo;

  const DriverProfilePage({
    super.key,
    required this.driverId,
    this.driverName,
    this.vehicleInfo,
  });

  @override
  State<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends State<DriverProfilePage> {
  final _auth = FirebaseAuth.instance;
  final ChatService _chatService = ChatService();

  String? _myUid;

  @override
  void initState() {
    super.initState();
    _ensureSignedIn();
  }

  Future<void> _ensureSignedIn() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
    setState(() => _myUid = _auth.currentUser!.uid);
  }

  Future<void> _startChat() async {
    if (_myUid == null || _myUid!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to start chat')),
      );
      return;
    }

    if (widget.driverId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot start chat: Driver information missing'),
        ),
      );
      return;
    }

    try {
      final chatId = await _chatService.ensureConversation(
        me: _myUid!,
        other: widget.driverId,
      );

      if (context.mounted) {
        Navigator.pushNamed(
          context,
          Routes.chatScreen,
          arguments: {
            'chatId': chatId,
            'recipientId': widget.driverId,
          },
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to start chat')),
      );
    }
  }

  void _reportDriver() {
    if (widget.driverId.isEmpty) return;

    Navigator.of(context).pushNamed(
      Routes.reportDriver,
      arguments: {
        'driverId': widget.driverId,
        'driverName': widget.driverName ?? '',
        'tripId': '',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.driverId.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Driver Profile'),
          backgroundColor: _kThemeBlue,
        ),
        body: const Center(
          child: Text('Driver information not available'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Profile'),
        backgroundColor: _kThemeBlue,
        foregroundColor: Colors.white,
      ),
      backgroundColor: _kThemeGreen,
      body: _myUid == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(widget.driverId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading driver: ${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(child: Text('Driver not found'));
                }

                final data = snapshot.data!.data()!;
                return _buildProfileContent(context, data);
              },
            ),
    );
  }

  Widget _buildProfileContent(
      BuildContext context, Map<String, dynamic> driverData) {
    final firstName = (driverData['firstName'] ?? '').toString();
    final lastName = (driverData['lastName'] ?? '').toString();
    final gender = (driverData['gender'] ?? '').toString();
    final joinedAt = (driverData['createdAt'] as Timestamp?);
    final displayName = [firstName, lastName]
        .where((s) => s.trim().isNotEmpty)
        .join(' ')
        .trim();

    final effectiveName = displayName.isNotEmpty
        ? displayName
        : (widget.driverName ?? 'Driver');

    final photoUrl = (driverData['photoUrl'] ??
            driverData['profilePhotoUrl'] ??
            driverData['avatarUrl'] ??
            '')
        .toString();

    final int peopleDriven = (driverData['peopleDriven'] is num)
        ? (driverData['peopleDriven'] as num).toInt()
        : 0;
    final int ridesTaken = (driverData['ridesTaken'] is num)
        ? (driverData['ridesTaken'] as num).toInt()
        : 0;

    final bool emailVerified =
        driverData['emailVerified'] == true ||
            driverData['isEmailVerified'] == true ||
            driverData['email_verification'] == 'verified';

    final bool phoneVerified =
        driverData['phoneVerified'] == true ||
            driverData['isPhoneVerified'] == true ||
            driverData['phone_verification'] == 'verified';

    final String bio = (driverData['bio'] ??
            'Hello! I love carpooling and meeting new people.')
        .toString();

    // ---------- Driver verification logic (aligned with admin) ----------
    final usageRole = (driverData['usageRole'] ?? '').toString();
    final bool isDriver = usageRole.toLowerCase().contains('driver');

    final String licenseNumber = (driverData['driverLicenseNumber'] ??
            driverData['licenseNumber'] ??
            '')
        .toString()
        .trim();

    String driverStatus =
        (driverData['driverStatus'] ?? '').toString().toLowerCase();

    final bool driverVerifiedFlag =
        driverData['isDriverVerified'] == true ||
            driverData['driverVerified'] == true ||
            driverData['isVerifiedDriver'] == true ||
            driverStatus == 'approved';

    final bool driverVerified =
        isDriver && driverVerifiedFlag && licenseNumber.isNotEmpty;

    final bool driverPending =
        isDriver && !driverVerified && driverStatus == 'pending';
    // -------------------------------------------------------------------

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            children: [
              // HEADER
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: _kThemeGreen.withOpacity(0.1),
                        backgroundImage:
                            photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                        child: photoUrl.isEmpty
                            ? Text(
                                effectiveName.isNotEmpty
                                    ? effectiveName[0].toUpperCase()
                                    : 'D',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: _kThemeBlue,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              effectiveName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: _kThemeBlue,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (joinedAt != null)
                              Text(
                                'Joined ${DateFormat.yMMMM().format(joinedAt.toDate())}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                ),
                              ),
                            if (gender.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                gender,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                            // Driver licence verification badge
                            if (isDriver) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    driverVerified
                                        ? Icons.verified_rounded
                                        : (driverPending
                                            ? Icons.hourglass_top
                                            : Icons.warning_amber_rounded),
                                    size: 16,
                                    color: driverVerified
                                        ? Colors.green
                                        : (driverPending
                                            ? Colors.orange
                                            : Colors.redAccent),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    driverVerified
                                        ? 'Driver verified'
                                        : (driverPending
                                            ? 'Driver verification pending'
                                            : 'Driver not verified'),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: driverVerified
                                          ? Colors.green
                                          : (driverPending
                                              ? Colors.orange
                                              : Colors.redAccent),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (emailVerified)
                            _verifiedPill(label: 'Verified'),
                          if (phoneVerified) ...[
                            const SizedBox(height: 4),
                            _verifiedPill(label: 'Verified'),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // BIO
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bio',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        bio,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // STATS
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _statChip(
                        icon: Icons.group,
                        value: peopleDriven,
                        label: 'people driven',
                      ),
                      _statChip(
                        icon: Icons.directions_car,
                        value: ridesTaken,
                        label: 'rides taken',
                      ),
                    ],
                  ),
                ),
              ),

              // REVIEWS
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reviews',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildReviewsList(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // BOTTOM ACTION BUTTONS
        SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.message_outlined),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kThemeBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: _startChat,
                    label: const Text(
                      'Message Driver',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.flag_outlined),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      side: const BorderSide(color: Colors.red),
                    ),
                    onPressed: _reportDriver,
                    label: const Text(
                      'Report this driver',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _verifiedPill({required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.green),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.verified, size: 14, color: Colors.green),
          SizedBox(width: 4),
          Text(
            'Verified',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip({
    required IconData icon,
    required int value,
    required String label,
  }) {
    return Column(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: _kThemeBlue.withOpacity(0.06),
          child: Icon(icon, color: _kThemeBlue),
        ),
        const SizedBox(height: 6),
        Text(
          '$value',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: _kThemeBlue,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  /// Reviews list – uses recipientId == this driver
  Widget _buildReviewsList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('reviews')
          .where('recipientId', isEqualTo: widget.driverId)
          // removed orderBy to avoid composite index requirement
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (snap.hasError) {
          // show the Firestore error so we know what's wrong
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Error loading reviews: ${snap.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No reviews yet.',
              style: TextStyle(color: Colors.black54),
            ),
          );
        }

        final docs = snap.data!.docs;

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 16),
          itemBuilder: (_, i) {
            final data = docs[i].data();
            final rating = (data['rating'] is num)
                ? (data['rating'] as num).toDouble()
                : 0.0;
            final text = (data['comment'] ?? '').toString();
            final createdAt = data['createdAt'] as Timestamp?;
            final when = createdAt != null
                ? DateFormat.yMMMd().format(createdAt.toDate())
                : '';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 18),
                    const SizedBox(width: 6),
                    const Text(
                      'Rider',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    if (rating > 0) ...[
                      const Icon(Icons.star,
                          size: 16, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(
                        rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    if (when.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        when,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ],
                ),
                if (text.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
