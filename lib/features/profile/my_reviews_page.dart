// lib/features/profile/my_reviews_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56); // (kept in case you use it later)

final _dateFmt = DateFormat('MMM d, yyyy • h:mm a');

class MyReviewsPage extends StatelessWidget {
  const MyReviewsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _kThemeBlue,
          foregroundColor: Colors.white,
          title: const Text('My Reviews'),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Received'),
              Tab(text: 'Given'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ReviewsList(mode: _ReviewsMode.received),
            _ReviewsList(mode: _ReviewsMode.given),
          ],
        ),
      ),
    );
  }
}

enum _ReviewsMode { received, given }

class _ReviewsList extends StatelessWidget {
  final _ReviewsMode mode;
  const _ReviewsList({required this.mode});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const _CenteredInfo(
        title: 'Sign in required',
        subtitle: 'Please sign in to see your reviews.',
        icon: Icons.lock_outline,
      );
    }

    final uid = user.uid;
    final reviewsCol = FirebaseFirestore.instance.collection('reviews');

    // We do NOT orderBy here (avoids composite index requirements).
    // Instead we sort on the client by createdAt desc.
    Query<Map<String, dynamic>> query;
    if (mode == _ReviewsMode.received) {
      // Reviews written about ME
      query = reviewsCol.where('recipientId', isEqualTo: uid);
    } else {
      // Reviews I wrote
      query = reviewsCol.where('authorId', isEqualTo: uid);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return const _CenteredInfo(
            title: 'Couldn’t load reviews',
            subtitle: 'Please try again shortly.',
            icon: Icons.wifi_off_rounded,
          );
        }

        final docs =
            snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        // Sort newest → oldest by createdAt (if present)
        docs.sort((a, b) {
          final ad = a.data();
          final bd = b.data();
          final at = ad['createdAt'];
          final bt = bd['createdAt'];
          if (at is Timestamp && bt is Timestamp) {
            return bt.compareTo(at);
          }
          return 0;
        });

        if (docs.isEmpty) {
          return _CenteredInfo(
            title: mode == _ReviewsMode.received
                ? 'No reviews yet'
                : 'No reviews given yet',
            subtitle: mode == _ReviewsMode.received
                ? 'Once people rate you, their feedback will appear here.'
                : 'After you rate trips, your reviews will appear here.',
            icon: Icons.rate_review_outlined,
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final data = docs[i].data();

            final rating = (data['rating'] as num?)?.toInt() ?? 0;

            // Support both new 'comment' and any old 'reviewText' field
            final reviewText =
                (data['comment'] ?? data['reviewText'] ?? '').toString().trim();

            final createdAtTs = data['createdAt'] as Timestamp?;
            final createdAt = createdAtTs?.toDate();

            // Names from your RateTripPage schema
            final authorName =
                (data['authorName'] ?? 'Someone').toString().trim();
            final recipientName =
                (data['recipientName'] ?? 'User').toString().trim();

            final role = (data['role'] ?? 'rider').toString(); // driver / rider

            final titleText = mode == _ReviewsMode.received
                ? 'From $authorName'
                : 'To $recipientName';

            final subtitleRole = mode == _ReviewsMode.received
                ? (role == 'driver'
                    ? 'Written by a driver'
                    : 'Written by a rider')
                : (role == 'driver'
                    ? 'You wrote this as driver'
                    : 'You wrote this as rider');

            final dateLabel =
                createdAt != null ? _dateFmt.format(createdAt) : '—';

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.03),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ],
                border: Border.all(
                  color: Colors.black.withOpacity(0.04),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: stars + date
                  Row(
                    children: [
                      _StarRow(rating: rating),
                      const SizedBox(width: 8),
                      Text(
                        rating.toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _kThemeBlue,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        dateLabel,
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    titleText,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _kThemeBlue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitleRole,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (reviewText.isNotEmpty)
                    Text(
                      reviewText,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    )
                  else
                    Text(
                      'No written comment.',
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: Colors.black.withOpacity(0.6),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _StarRow extends StatelessWidget {
  final int rating;
  const _StarRow({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (i) {
        final filled = i < rating;
        return Icon(
          filled ? Icons.star_rounded : Icons.star_border_rounded,
          size: 18,
          color: filled ? Colors.amber : Colors.grey.shade400,
        );
      }),
    );
  }
}

class _CenteredInfo extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _CenteredInfo({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Colors.black26),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: _kThemeBlue,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black.withOpacity(.6),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
