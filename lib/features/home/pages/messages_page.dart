// lib/features/home/pages/messages_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../app_router.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

// CONVERTED TO STATEFUL WIDGET TO MANAGE UID AND STREAM REBUILD
class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final _auth = FirebaseAuth.instance;
  String? _uid;

  @override
  void initState() {
    super.initState();
    // Start listening to auth changes to update UID immediately
    _auth.authStateChanges().listen((user) {
      if (mounted) {
        // This ensures the StreamBuilder rebuilds with the correct UID (or null)
        setState(() => _uid = user?.uid);
      }
    });
    // Set initial UID
    _uid = _auth.currentUser?.uid;
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;

    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to see your messages.')),
      );
    }

    // CRITICAL: Key the StreamBuilder to the UID to force a complete stream reset on login/logout.
    final convos = FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .orderBy('lastAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Messages',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        backgroundColor: _kThemeBlue,
        elevation: 0,
      ),
      backgroundColor: _kThemeGreen,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        key: ValueKey(uid), // <--- KEY FOR ROBUSTNESS
        stream: convos,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final all = snap.data?.docs ?? const [];
          // Filter out any broken conversations (e.g., missing otherId)
          final docs = all.where((d) {
            final data = d.data();
            final parts = List.from(data['participants'] ?? const []);
            if (parts.length < 2) return false;
            final uidMe = uid;
            final other = parts.firstWhere(
              (p) => p != uidMe,
              orElse: () => '',
            );
            return (other is String) && other.isNotEmpty;
          }).toList();

          if (docs.isEmpty) {
            return const _EmptyInbox();
          }

          return ListView.separated(
            itemCount: docs.length,
            padding: const EdgeInsets.all(12),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final data = docs[i].data();
              final chatId = docs[i].id;

              // TripId stored in conversation doc
              final String? tripId = data['tripId'] as String?;

              final List participants =
                  List.from(data['participants'] ?? const []);
              final uidMe = uid;
              final String otherId =
                  participants.firstWhere((p) => p != uidMe, orElse: () => '');

              // Extra guard (prevents red-screen if something slipped through)
              if (otherId.isEmpty) return const SizedBox.shrink();

              final String lastMsg = (data['lastMessage'] ?? '').toString();
              final Timestamp? ts = data['lastAt'] as Timestamp?;
              final DateTime lastAt = ts?.toDate() ?? DateTime.now();
              final Map<String, dynamic> mapRead =
                  Map<String, dynamic>.from(data['mapRead'] ?? {});
              final bool isUnread = !(mapRead[uidMe] as bool? ?? false);

              // 🔹 NEW: try to pull segmentFrom/segmentTo from the conversation doc
              Map<String, dynamic> tripInfo =
                  (data['tripInfo'] as Map<String, dynamic>?) ?? {};
              final String? segmentFrom =
                  (data['segmentFrom'] ?? tripInfo['from']) as String?;
              final String? segmentTo =
                  (data['segmentTo'] ?? tripInfo['to']) as String?;

              return _ConversationTile(
                chatId: chatId,
                otherUserId: otherId,
                lastMessage: lastMsg,
                lastAt: lastAt,
                isUnread: isUnread,
                tripId: tripId,
                segmentFrom: segmentFrom,
                segmentTo: segmentTo,
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_outline,
                size: 64, color: Colors.white),
            const SizedBox(height: 12),
            Text(
              'No conversations yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              'Send a message from a trip or driver profile to start chatting.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final String chatId;
  final String otherUserId;
  final String lastMessage;
  final DateTime lastAt;
  final bool isUnread;
  final String? tripId;

  // 🔹 NEW: store segmentFrom / segmentTo so we can pass into ChatScreen
  final String? segmentFrom;
  final String? segmentTo;

  const _ConversationTile({
    required this.chatId,
    required this.otherUserId,
    required this.lastMessage,
    required this.lastAt,
    required this.isUnread,
    this.tripId,
    this.segmentFrom,
    this.segmentTo,
  });

  String _relativeTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return DateFormat('MMM d').format(t);
  }

  // Trip header used in the list
  Widget _buildTripHeader(BuildContext context) {
    if (tripId == null || tripId!.isEmpty) {
      return const SizedBox.shrink();
    }

    final tripDoc =
        FirebaseFirestore.instance.collection('trips').doc(tripId).get();

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: tripDoc,
      builder: (context, tripSnap) {
        if (!tripSnap.hasData || !tripSnap.data!.exists) {
          // Fallback if trip is deleted or not found
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Trip: Deleted or N/A',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.redAccent),
            ),
          );
        }

        final d = tripSnap.data!.data()!;
        final origin = (d['origin'] ?? '—').toString().trim();
        final destination = (d['destination'] ?? '—').toString().trim();
        final date =
            d['date'] is Timestamp ? d['date'].toDate() : DateTime.now();

        // Format date like "Tomorrow at 2:30pm"
        String dateStr;
        final now = DateTime.now();
        final tomorrow =
            DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
        final tripDate = DateTime(date.year, date.month, date.day);
        final timeStr = DateFormat('h:mma').format(date).toLowerCase();

        if (tripDate == DateTime(now.year, now.month, now.day)) {
          dateStr = 'Today at $timeStr';
        } else if (tripDate == tomorrow) {
          dateStr = 'Tomorrow at $timeStr';
        } else {
          dateStr = DateFormat('EEE, MMM d').format(date);
        }

        return Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: _kThemeBlue.withOpacity(0.5),
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.only(left: 8, top: 4, bottom: 8),
          margin: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateStr,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '$origin → $destination',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _kThemeBlue,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!context.mounted) return const SizedBox.shrink();

    final userDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(otherUserId)
        .get();

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: userDoc,
      builder: (context, snap) {
        String displayName = 'User';
        String email = '';
        String photoUrl = '';

        if (snap.hasData && snap.data!.exists) {
          final d = snap.data!.data()!;
          displayName = (d['displayName'] ?? '').toString().trim();
          if (displayName.isEmpty) {
            final first = (d['firstName'] ?? '').toString().trim();
            final last = (d['lastName'] ?? '').toString().trim();
            final full =
                [first, last].where((s) => s.isNotEmpty).join(' ');
            if (full.isNotEmpty) displayName = full;
          }
          if (displayName.isEmpty) {
            displayName = (d['name'] ?? '').toString().trim();
          }
          if (displayName.isEmpty) {
            displayName = (d['username'] ?? '').toString().trim();
          }

          email = (d['email'] ?? '').toString();
          photoUrl = (d['photoUrl'] ?? '').toString();

          if (displayName.isEmpty && email.isNotEmpty) {
            displayName = email.split('@').first;
          }
          if (displayName.isEmpty) displayName = 'User';
        }

        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.pushNamed(
                context,
                Routes.chatScreen,
                arguments: {
                  'chatId': chatId,
                  'recipientId': otherUserId,
                  // 🔹 NEW: pass route + trip into ChatScreen
                  'segmentFrom': segmentFrom,
                  'segmentTo': segmentTo,
                  'tripId': tripId,
                },
              );
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Trip Header Details
                  _buildTripHeader(context),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor:
                            _kThemeGreen.withOpacity(0.1),
                        backgroundImage: photoUrl.isNotEmpty
                            ? NetworkImage(photoUrl)
                            : null,
                        child: photoUrl.isEmpty
                            ? Text(
                                displayName
                                    .trim()
                                    .split(RegExp(r'\s+'))
                                    .map(
                                      (e) =>
                                          e.isNotEmpty ? e[0] : '',
                                    )
                                    .take(2)
                                    .join()
                                    .toUpperCase(),
                                style: const TextStyle(
                                  color: _kThemeGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: isUnread
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    color: _kThemeBlue,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              lastMessage.isEmpty
                                  ? (email.isNotEmpty
                                      ? email
                                      : 'Say hello 👋')
                                  : lastMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: isUnread
                                        ? Colors.black87
                                        : Colors.black54,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _relativeTime(lastAt),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: isUnread
                                      ? _kThemeBlue
                                      : Colors.grey,
                                ),
                          ),
                          if (isUnread)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: CircleAvatar(
                                radius: 5,
                                backgroundColor: _kThemeGreen,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
