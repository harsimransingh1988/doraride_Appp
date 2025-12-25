import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ViewProfilePage extends StatefulWidget {
  const ViewProfilePage({super.key});

  @override
  State<ViewProfilePage> createState() => _ViewProfilePageState();
}

class _ViewProfilePageState extends State<ViewProfilePage> {
  // Brand
  static const kGreen = Color(0xFF279C56);
  static const kNavy = Color(0xFF180D3B);
  static const kBg = Color(0xFFF4F7F5);

  // local cache keys
  static const _kFirst = 'first_name';
  static const _kLast = 'last_name';
  static const _kBio = 'profile_bio';
  static const _kGender = 'profile_gender';
  static const _kDob = 'profile_dob_iso';
  static const _kPhoto = 'profile_photo_url';
  static const _kEmailVerified = 'email_verified';
  static const _kPhoneVerified = 'phone_verified';

  bool _savingPhoto = false;
  bool _savingBio = false;

  // -------- helpers
  String _friendlyMonthYear(DateTime dt) {
    const m = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${m[dt.month - 1]} ${dt.year}';
  }

  int _yearsBetween(DateTime from, DateTime to) {
    int years = to.year - from.year;
    if (to.month < from.month ||
        (to.month == from.month && to.day < from.day)) {
      years--;
    }
    return years;
  }

  String _genderAgeText(String? gender, String? dobIso) {
    final g = (gender ?? 'Male');
    int? age;
    if (dobIso != null && dobIso.isNotEmpty) {
      try {
        final dob = DateTime.parse(dobIso);
        age = _yearsBetween(dob, DateTime.now());
      } catch (_) {}
    }
    return age != null ? '$g, $age years old' : g;
  }

  // ---------- PHOTO UPLOAD ----------

  // Upload + save profile photo — uses path allowed by your rules.
  // Now: spinner only during Storage upload; Firestore/Auth are updated in background.
  Future<void> _pickAndUploadPhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to update your photo.')),
        );
      }
      return;
    }

    try {
      final picker = ImagePicker();
      final XFile? x = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (x == null) return;

      setState(() => _savingPhoto = true);

      final Uint8List bytes = await x.readAsBytes();

      // IMPORTANT: path matches your Storage rules (user_uploads/{uid}/…)
      final ref = FirebaseStorage.instance
          .ref('user_uploads/${user.uid}/profile.jpg');

      final uploadTask = ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      await uploadTask;

      final String url = await ref.getDownloadURL();

      // ✅ Upload finished → stop spinner immediately
      if (!mounted) return;
      setState(() => _savingPhoto = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Photo uploaded! Saving to profile...'),
          duration: Duration(seconds: 2),
        ),
      );

      // Save to Auth + Firestore in background
      _savePhotoToUser(user, url);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _savingPhoto = false);
      final msg = (e.code == 'unauthorized')
          ? 'No permission to upload. Check Storage rules for user_uploads/{uid}.'
          : e.message ?? e.code;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $msg')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update photo: $e')),
      );
    }
  }

  /// After Storage upload, link the URL to Auth + Firestore + local cache.
  /// Runs without touching the spinner, so slow writes don't freeze the UI.
  Future<void> _savePhotoToUser(User user, String url) async {
    try {
      await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {
            'photoUrl': url,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        ),
        user.updatePhotoURL(url),
      ]);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPhoto, url);

      await user.reload();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Profile photo saved.'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // Photo already exists in Storage; worst case we only failed linking it.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Photo uploaded, but profile update had an issue: $e'),
        ),
      );
    }
  }

  // Save bio text
  Future<void> _editBio(String currentBio) async {
    final controller = TextEditingController(text: currentBio);
    final newBio = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit bio'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Write a short bio…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newBio == null) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      setState(() => _savingBio = true);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'bio': newBio, 'updatedAt': FieldValue.serverTimestamp()},
              SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kBio, newBio);
    } finally {
      if (mounted) setState(() => _savingBio = false);
    }
  }

  /// My bookings mirror (for stats – used for rides taken).
  Stream<QuerySnapshot<Map<String, dynamic>>> _myBookingsStream(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('my_bookings')
        .snapshots();
  }

  // Live stream of the user's profile document, with fallback to legacy 'profiles'
  Stream<DocumentSnapshot<Map<String, dynamic>>> _profileStream(String uid) async* {
    final usersDoc =
        FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
    await for (final snap in usersDoc) {
      if (snap.exists) {
        yield snap;
      } else {
        yield* FirebaseFirestore.instance.collection('profiles').doc(uid).snapshots();
      }
    }
  }

  /// Reviews stream for this user (as recipient/driver).
  /// ✅ CHANGED: Use index-friendly orderBy + limit for faster loading
  Stream<QuerySnapshot<Map<String, dynamic>>> _reviewsStream(String uid) {
    return FirebaseFirestore.instance
        .collection('reviews')
        .where('recipientId', isEqualTo: uid)
        .orderBy('createdAt', descending: true) // ✅ CHANGED
        .limit(50) // ✅ CHANGED
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        title: const Text('Profile'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pushNamed('/profile_settings'),
            child: const Text('Settings', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: user == null
          ? const Center(child: Text('Please sign in'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _profileStream(user.uid),
              builder: (ctx, profSnap) {
                final prefsFuture = SharedPreferences.getInstance();

                // refresh auth flags
                FirebaseAuth.instance.currentUser?.reload();

                // Defaults
                String first = '';
                String last = '';
                String bio = 'Hello! I love carpooling and meeting new people.';
                String? photoUrl; // Firestore photo
                String? authPhoto = user.photoURL; // Auth photo fallback
                String joined =
                    'Joined ${_friendlyMonthYear(user.metadata.creationTime ?? DateTime.now())}';
                String genderAge = 'Male';

                bool emailVerified =
                    FirebaseAuth.instance.currentUser?.emailVerified ?? false;
                bool phoneVerified =
                    (FirebaseAuth.instance.currentUser?.phoneNumber ?? '').isNotEmpty;

                // driver fields
                String usageRole = '';
                String licenseNumber = '';
                bool isDriver = false;
                String driverStatus = ''; // pending / verified / ...
                bool driverVerified = false;

                // stats from profile
                int profilePeopleDriven = 0;

                if (profSnap.hasData && profSnap.data != null && profSnap.data!.exists) {
                  final data = profSnap.data!.data()!;
                  first = (data['firstName'] ?? '').toString();
                  last = (data['lastName'] ?? '').toString();
                  bio = (data['bio'] ?? bio).toString();
                  final rawPhoto = data['photoUrl'];
                  if (rawPhoto is String && rawPhoto.isNotEmpty) {
                    photoUrl = rawPhoto;
                  }

                  final ts = data['createdAt'];
                  if (ts is Timestamp) {
                    joined = 'Joined ${_friendlyMonthYear(ts.toDate())}';
                  }

                  genderAge = _genderAgeText(
                      data['gender']?.toString(), data['dobIso']?.toString());

                  if (data['emailVerified'] != null) {
                    emailVerified = data['emailVerified'] == true;
                  }
                  if (data['phoneVerified'] != null) {
                    phoneVerified = data['phoneVerified'] == true;
                  }

                  usageRole = (data['usageRole'] ?? '').toString();
                  licenseNumber = (data['driverLicenseNumber'] ??
                          data['licenseNumber'] ??
                          '')
                      .toString()
                      .trim();
                  isDriver = usageRole.toLowerCase().contains('driver');

                  // driver status & verified flag
                  driverStatus = (data['driverStatus'] ?? '').toString().toLowerCase();
                  if (driverStatus.isEmpty && data['verificationStatus'] != null) {
                    driverStatus = data['verificationStatus'].toString().toLowerCase();
                  }

                  final driverVerifiedFlag =
                      data['driverVerified'] == true ||
                          data['isDriverVerified'] == true ||
                          data['isVerifiedDriver'] == true ||
                          driverStatus == 'verified' ||
                          driverStatus == 'approved';

                  driverVerified =
                      isDriver && driverVerifiedFlag && licenseNumber.isNotEmpty;

                  // people driven counter from profile (matches search page)
                  if (data['peopleDriven'] is num) {
                    profilePeopleDriven = (data['peopleDriven'] as num).toInt();
                  } else if (data['peopleDrivenSeats'] is num) {
                    profilePeopleDriven =
                        (data['peopleDrivenSeats'] as num).toInt();
                  }

                  // Cache locally
                  prefsFuture.then((p) async {
                    await p.setString(_kFirst, first);
                    await p.setString(_kLast, last);
                    await p.setString(_kBio, bio);
                    if (photoUrl != null && photoUrl!.isNotEmpty) {
                      await p.setString(_kPhoto, photoUrl!);
                    }
                    await p.setBool(_kEmailVerified, emailVerified);
                    await p.setBool(_kPhoneVerified, phoneVerified);
                    if (data['gender'] != null) {
                      await p.setString(_kGender, data['gender'].toString());
                    }
                    if (data['dobIso'] != null) {
                      await p.setString(_kDob, data['dobIso'].toString());
                    }
                  });
                } else if (profSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Name
                final fullName =
                    [first, last].where((s) => s.isNotEmpty).join(' ').trim();
                final nameDisplay = fullName.isEmpty
                    ? (user.displayName ?? 'Your name')
                    : fullName;

                // Final photo selection: Firestore → Auth → local cache
                Future<String?> resolvedPhoto() async {
                  if (photoUrl != null && photoUrl!.isNotEmpty) {
                    return photoUrl;
                  }
                  if (authPhoto != null && authPhoto!.isNotEmpty) {
                    return authPhoto;
                  }
                  final p = await SharedPreferences.getInstance();
                  final cached = p.getString(_kPhoto);
                  return (cached != null && cached.isNotEmpty) ? cached : null;
                }

                // driver pending state for UI
                final bool driverPending =
                    isDriver && !driverVerified && driverStatus == 'pending';

                return RefreshIndicator(
                  onRefresh: () async {
                    await FirebaseAuth.instance.currentUser?.reload();
                    setState(() {});
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: FutureBuilder<String?>(
                      future: resolvedPhoto(),
                      builder: (context, photoSnap) {
                        final effectivePhoto = photoSnap.data;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _HeaderCard(
                              name: nameDisplay,
                              joined: joined,
                              genderAge: genderAge,
                              photoUrl: effectivePhoto,
                              onChangePhoto: _savingPhoto ? null : _pickAndUploadPhoto,
                              saving: _savingPhoto,
                              isDriver: isDriver,
                              driverVerified: driverVerified,
                              driverStatus: driverStatus,
                            ),
                            const SizedBox(height: 12),

                            _SectionTitle(
                              'Bio',
                              trailing: IconButton(
                                icon: const Icon(Icons.edit, color: kNavy),
                                onPressed: _savingBio ? null : () => _editBio(bio),
                                tooltip: 'Edit bio',
                              ),
                            ),
                            _CardContainer(
                              child: _savingBio
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8),
                                      child: Center(child: CircularProgressIndicator()),
                                    )
                                  : Text(
                                      bio.isEmpty ? 'No bio yet.' : bio,
                                      style: const TextStyle(color: kNavy, fontSize: 16),
                                    ),
                            ),
                            const SizedBox(height: 12),

                            // -------- STATS (people driven / rides taken) --------
                            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: _myBookingsStream(user.uid),
                              builder: (context, statsSnap) {
                                int ridesTaken = 0;
                                int peopleDrivenFromBookings = 0;

                                final docs = statsSnap.data?.docs ?? [];

                                for (final doc in docs) {
                                  final data = doc.data();

                                  // booking role: 'driver' or 'rider'
                                  final type =
                                      (data['type'] ?? '').toString().toLowerCase();

                                  // seats booked on this booking (defaults to 1)
                                  int seats = 1;
                                  final rawSeats =
                                      data['seats'] ?? data['seatCount'] ?? data['bookedSeats'];
                                  if (rawSeats is int) {
                                    seats = rawSeats;
                                  }

                                  if (type == 'driver') {
                                    peopleDrivenFromBookings += seats;
                                  } else if (type == 'rider') {
                                    ridesTaken += seats;
                                  } else {
                                    // fallback to ids if type not set
                                    final driverId = (data['driverId'] ?? '').toString();
                                    final riderId = (data['riderId'] ?? '').toString();
                                    if (driverId == user.uid) {
                                      peopleDrivenFromBookings += seats;
                                    }
                                    if (riderId == user.uid) {
                                      ridesTaken += seats;
                                    }
                                  }
                                }

                                // if profile has a value, prefer it; otherwise use bookings
                                final effectivePeopleDriven = profilePeopleDriven > 0
                                    ? profilePeopleDriven
                                    : peopleDrivenFromBookings;

                                return _ProfileStatsRow(
                                  peopleDriven: effectivePeopleDriven,
                                  ridesTaken: ridesTaken,
                                );
                              },
                            ),
                            const SizedBox(height: 12),

                            // -------- REVIEWS SECTION (LIVE) --------
                            const _SectionTitle('Reviews'),
                            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: _reviewsStream(user.uid),
                              builder: (context, reviewSnap) {
                                if (reviewSnap.hasError) {
                                  debugPrint('PROFILE REVIEWS ERROR: ${reviewSnap.error}');
                                }

                                if (reviewSnap.connectionState == ConnectionState.waiting &&
                                    !reviewSnap.hasData) {
                                  return const _CardContainer(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(vertical: 16),
                                      child: Center(child: CircularProgressIndicator()),
                                    ),
                                  );
                                }

                                List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
                                    reviewSnap.data?.docs ?? [];

                                // ✅ CHANGED: Removed Dart-side sorting (Firestore already sorted)

                                if (docs.isEmpty) {
                                  return const _CardContainer(
                                    child: Text(
                                      'No reviews yet.',
                                      style: TextStyle(
                                        color: kNavy,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  );
                                }

                                // REAL average rating from reviews collection
                                double sumRating = 0;
                                int count = 0;
                                for (final d in docs) {
                                  final r = d.data()['rating'];
                                  if (r is num) {
                                    sumRating += r.toDouble();
                                    count++;
                                  }
                                }
                                final double avg = count == 0 ? 0 : sumRating / count;

                                final dateFmt = DateFormat('MMM d, yyyy');

                                return _CardContainer(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.star, color: Colors.amber[700]),
                                          const SizedBox(width: 4),
                                          Text(
                                            avg.toStringAsFixed(1),
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: kNavy,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '($count reviews)',
                                            style: TextStyle(
                                              color: kNavy.withOpacity(0.7),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const Spacer(),
                                          TextButton(
                                            onPressed: () {
                                              Navigator.of(context).pushNamed('/my_reviews');
                                            },
                                            child: const Text('View all'),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      // show ONLY top 5 reviews here
                                      ...docs.take(5).map((doc) {
                                        final data = doc.data();
                                        final rawRating = data['rating'];
                                        int rating = 0;
                                        if (rawRating is num) {
                                          final v = rawRating.toDouble();
                                          if (v <= 0) {
                                            rating = 0;
                                          } else if (v >= 5) {
                                            rating = 5;
                                          } else {
                                            rating = v.round();
                                          }
                                        }
                                        final comment =
                                            (data['comment'] ?? data['text'] ?? '').toString();
                                        final authorName =
                                            (data['authorName'] ?? 'Rider').toString();
                                        final ts = data['createdAt'];
                                        DateTime? dt;
                                        if (ts is Timestamp) {
                                          dt = ts.toDate();
                                        }
                                        final dateStr = dt == null ? '' : dateFmt.format(dt);

                                        return Padding(
                                          padding: const EdgeInsets.only(top: 8.0),
                                          child: _ReviewBubble(
                                            authorName: authorName,
                                            rating: rating,
                                            comment: comment,
                                            dateLabel: dateStr,
                                          ),
                                        );
                                      }).toList(),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),

                            const _SectionTitle('Verifications'),
                            _CardContainer(
                              child: Column(
                                children: [
                                  _VerificationRow(
                                    icon: Icons.smartphone_outlined,
                                    label: 'Phone number',
                                    verified: phoneVerified,
                                  ),
                                  const Divider(height: 20),
                                  _VerificationRow(
                                    icon: Icons.email_outlined,
                                    label: 'Email address',
                                    verified: emailVerified,
                                  ),
                                  if (isDriver) const Divider(height: 20),
                                  if (isDriver)
                                    _VerificationRow(
                                      icon: Icons.directions_car_outlined,
                                      label: 'Driver licence',
                                      verified: driverVerified,
                                      pending: driverPending,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ===================== UI widgets =====================

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.name,
    required this.joined,
    required this.genderAge,
    required this.photoUrl,
    required this.onChangePhoto,
    required this.saving,
    required this.isDriver,
    required this.driverVerified,
    required this.driverStatus,
  });

  final String name;
  final String joined;
  final String genderAge;
  final String? photoUrl;
  final VoidCallback? onChangePhoto;
  final bool saving;

  final bool isDriver;
  final bool driverVerified;
  final String driverStatus;

  static const kGreen = _ViewProfilePageState.kGreen;
  static const kNavy = _ViewProfilePageState.kNavy;

  @override
  Widget build(BuildContext context) {
    // Decide driver badge visuals
    IconData? badgeIcon;
    String? badgeText;
    Color badgeColor = kGreen;

    if (isDriver) {
      if (driverVerified) {
        badgeIcon = Icons.verified_rounded;
        badgeText = 'Driver verified';
        badgeColor = kGreen;
      } else if (driverStatus == 'pending') {
        badgeIcon = Icons.hourglass_top;
        badgeText = 'Driver verification pending';
        badgeColor = Colors.orange;
      } else {
        badgeIcon = Icons.warning_amber_rounded;
        badgeText = 'Driver not verified';
        badgeColor = Colors.orange;
      }
    }

    return _CardContainer(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: kGreen,
                backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty)
                    ? NetworkImage(photoUrl!)
                    : null,
                child: (photoUrl == null || photoUrl!.isEmpty)
                    ? const Icon(Icons.person, color: Colors.white, size: 36)
                    : null,
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: kGreen,
                    child: InkWell(
                      onTap: saving ? null : onChangePhoto,
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.edit, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: kNavy,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),

                // Driver badge
                if (badgeIcon != null && badgeText != null)
                  Row(
                    children: [
                      Icon(badgeIcon, size: 16, color: badgeColor),
                      const SizedBox(width: 6),
                      Text(
                        badgeText,
                        style: TextStyle(
                          color: badgeColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),

                if (badgeIcon != null) const SizedBox(height: 6),

                Text(
                  joined,
                  style: TextStyle(
                    color: kNavy.withOpacity(0.7),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  genderAge,
                  style: TextStyle(
                    color: kNavy.withOpacity(0.7),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: saving ? null : onChangePhoto,
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: const Text('Change photo'),
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

class _ProfileStatsRow extends StatelessWidget {
  const _ProfileStatsRow({
    required this.peopleDriven,
    required this.ridesTaken,
  });

  final int peopleDriven;
  final int ridesTaken;

  static const kNavy = _ViewProfilePageState.kNavy;

  @override
  Widget build(BuildContext context) {
    return _CardContainer(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatPill(
            icon: Icons.group,
            value: peopleDriven.toString(),
            label: 'people driven',
          ),
          _StatPill(
            icon: Icons.directions_car,
            value: ridesTaken.toString(),
            label: 'rides taken',
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  static const kNavy = _ViewProfilePageState.kNavy;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: const Color(0xFFEAF2EC),
          child: Icon(icon, color: kNavy, size: 26),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: kNavy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: kNavy.withOpacity(0.7),
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _VerificationRow extends StatelessWidget {
  const _VerificationRow({
    required this.icon,
    required this.label,
    required this.verified,
    this.pending = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool verified;
  final bool pending;
  final VoidCallback? onTap;

  static const kNavy = _ViewProfilePageState.kNavy;
  static const kGreen = _ViewProfilePageState.kGreen;

  @override
  Widget build(BuildContext context) {
    IconData statusIcon;
    Color statusColor;
    String statusText;

    if (pending) {
      statusIcon = Icons.hourglass_top;
      statusColor = Colors.orange;
      statusText = 'Pending';
    } else if (verified) {
      statusIcon = Icons.verified;
      statusColor = kGreen;
      statusText = 'Verified';
    } else {
      statusIcon = Icons.error_outline;
      statusColor = Colors.orange;
      statusText = 'Unverified';
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Icon(icon, color: kNavy),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: kNavy,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(statusIcon, color: statusColor, size: 20),
            const SizedBox(width: 6),
            Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  static const kNavy = _ViewProfilePageState.kNavy;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: kNavy,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: kNavy),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.trailing});
  final String title;
  final Widget? trailing;

  static const kNavy = _ViewProfilePageState.kNavy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: kNavy,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _CardContainer extends StatelessWidget {
  const _CardContainer({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: card,
    );
  }
}

/// Bubble-style widget to show a single review
class _ReviewBubble extends StatelessWidget {
  const _ReviewBubble({
    required this.authorName,
    required this.rating,
    required this.comment,
    required this.dateLabel,
  });

  final String authorName;
  final int rating;
  final String comment;
  final String dateLabel;

  static const kNavy = _ViewProfilePageState.kNavy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kNavy.withOpacity(0.02),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                authorName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: kNavy,
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < rating ? Icons.star : Icons.star_border,
                    size: 16,
                    color: Colors.amber[700],
                  ),
                ),
              ),
              const Spacer(),
              if (dateLabel.isNotEmpty)
                Text(
                  dateLabel,
                  style: TextStyle(
                    color: kNavy.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              comment,
              style: const TextStyle(color: kNavy),
            ),
          ],
        ],
      ),
    );
  }
}
