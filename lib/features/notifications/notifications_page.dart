import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _auth = FirebaseAuth.instance;
  final AudioPlayer _player = AudioPlayer();

  String? _uid;

  // pagination limit
  int _limit = 20;

  // for sound triggering on new notifications
  int _lastNotificationCount = 0;

  @override
  void initState() {
    super.initState();
    _ensureSignedIn();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _ensureSignedIn() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
    setState(() => _uid = _auth.currentUser!.uid);
  }

  Future<void> _playNotificationSound() async {
    try {
      // Path is relative to "assets/" root in pubspec
      await _player.play(
        AssetSource('sounds/notification.mp3'),
      );
    } catch (e) {
      debugPrint('Notification sound error: $e');
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    if (_uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('notifications')
        .doc(notificationId)
        .update({'read': true});
  }

  Future<void> _markAsUnread(String notificationId) async {
    if (_uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('notifications')
        .doc(notificationId)
        .update({'read': false});
  }

  Future<void> _markAllAsRead() async {
    if (_uid == null) return;

    final unreadSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in unreadSnapshot.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  Future<void> _deleteNotification(String notificationId) async {
    if (_uid == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('notifications')
        .doc(notificationId)
        .delete();
  }

  Future<void> _deleteNotificationsForTrip(String tripId) async {
    if (_uid == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('notifications')
        .where('data.tripId', isEqualTo: tripId)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> _pinNotification(
    String notificationId, {
    required bool pinned,
  }) async {
    if (_uid == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('notifications')
        .doc(notificationId)
        .update({'pinned': pinned});
  }

  Widget _buildNotificationIcon(String type) {
    switch (type) {
      case 'booking_request':
        return const Icon(Icons.event_available, color: Colors.blue);
      case 'booking_accepted':
        return const Icon(Icons.check_circle, color: _kThemeGreen);
      case 'booking_rejected':
        return const Icon(Icons.cancel, color: Colors.red);
      case 'payment':
        return const Icon(Icons.payment, color: Colors.orange);
      case 'message':
      case 'new_message':
        return const Icon(Icons.message, color: Colors.purple);
      case 'trip_updated':
        return const Icon(Icons.drive_eta, color: Colors.teal);
      case 'trip_cancelled':
        return const Icon(Icons.warning_amber_rounded, color: Colors.red);
      default:
        return const Icon(Icons.notifications, color: _kThemeBlue);
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'booking_accepted':
        return _kThemeGreen.withOpacity(0.1);
      case 'booking_rejected':
        return Colors.red.withOpacity(0.1);
      case 'booking_request':
        return Colors.blue.withOpacity(0.1);
      case 'trip_updated':
        return Colors.teal.withOpacity(0.1);
      case 'trip_cancelled':
        return Colors.red.withOpacity(0.15);
      default:
        return Colors.grey.withOpacity(0.06);
    }
  }

  void _handleNotificationTap(Map<String, dynamic> notification) {
    final id = notification['id'] as String?;
    if (id != null) {
      _markAsRead(id);
    }

    final type = notification['type'] as String? ?? '';
    final data = notification['data'] as Map<String, dynamic>? ?? {};

    switch (type) {
      case 'booking_request':
        Navigator.of(context).pushNamed('/driver/requests');
        break;

      case 'booking_accepted':
      case 'booking_rejected':
        Navigator.of(context).pushNamed(
          '/booking/status',
          arguments: {
            'bookingId': data['bookingId'],
            'tripId': data['tripId'],
          },
        );
        break;

      case 'new_message':
      case 'message':
        Navigator.of(context).pushNamed(
          '/chat',
          arguments: {
            'chatId': data['chatId'],
            'recipientId': data['senderId'],
          },
        );
        break;

      case 'payment':
        Navigator.of(context).pushNamed(
          '/payments/details',
          arguments: {
            'paymentId': data['paymentId'],
            'tripId': data['tripId'],
          },
        );
        break;

      case 'trip_updated':
      case 'trip_cancelled':
        Navigator.of(context).pushNamed(
          '/trip/details',
          arguments: {
            'tripId': data['tripId'],
          },
        );
        break;

      case 'trip_group':
        // grouped card → open trip details
        Navigator.of(context).pushNamed(
          '/trip/details',
          arguments: {
            'tripId': data['tripId'],
          },
        );
        break;

      default:
        break;
    }
  }

  void _showNotificationOptions(
    Map<String, dynamic> notification,
    bool isRead,
  ) {
    final id = notification['id'] as String?;
    if (id == null) return;

    final data = notification['data'] as Map<String, dynamic>? ?? {};
    final tripId = data['tripId'] as String?;
    final pinned = notification['pinned'] == true;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(isRead ? Icons.mark_email_unread : Icons.done),
                title: Text(isRead ? 'Mark as unread' : 'Mark as read'),
                onTap: () {
                  Navigator.pop(context);
                  if (isRead) {
                    _markAsUnread(id);
                  } else {
                    _markAsRead(id);
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  pinned ? Icons.push_pin : Icons.push_pin_outlined,
                ),
                title: Text(pinned ? 'Unpin notification' : 'Pin notification'),
                onTap: () {
                  Navigator.pop(context);
                  _pinNotification(id, pinned: !pinned);
                },
              ),
              if (tripId != null && tripId.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.layers_clear),
                  title: const Text('Clear all notifications for this trip'),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteNotificationsForTrip(tripId);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Delete this notification',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteNotification(id);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: _kThemeBlue,
        actions: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(_uid)
                .collection('notifications')
                .where('read', isEqualTo: false)
                .snapshots(),
            builder: (context, snapshot) {
              final unreadCount = snapshot.data?.docs.length ?? 0;

              if (unreadCount == 0) {
                return IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.notifications_none),
                );
              }

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          begin: 0,
                          end: unreadCount > 0 ? 0.25 : 0,
                        ),
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.elasticOut,
                        builder: (context, angle, child) {
                          return Transform.rotate(
                            angle: angle,
                            child: IconButton(
                              onPressed: () {},
                              icon: const Icon(Icons.notifications),
                            ),
                          );
                        },
                      ),
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            unreadCount > 9 ? '9+' : '$unreadCount',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: _markAllAsRead,
                    icon: const Icon(Icons.mark_email_read, color: Colors.white),
                    label: Text(
                      'Mark all read ($unreadCount)',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: _buildNotificationsList(),
    );
  }

  Widget _buildNotificationsList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('notifications')
          .orderBy('createdAt', descending: true)
          .limit(_limit)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];

        // play sound when new notifications arrive (after first load)
        if (docs.length > _lastNotificationCount &&
            _lastNotificationCount != 0) {
          _playNotificationSound();
        }
        _lastNotificationCount = docs.length;

        if (docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No notifications yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'You\'ll see important updates here',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        // separate pinned and non-pinned
        List<QueryDocumentSnapshot<Map<String, dynamic>>> pinnedDocs = [];
        List<QueryDocumentSnapshot<Map<String, dynamic>>> otherDocs = [];

        for (final doc in docs) {
          final data = doc.data();
          if (data['pinned'] == true) {
            pinnedDocs.add(doc);
          } else {
            otherDocs.add(doc);
          }
        }

        final widgets = <Widget>[];

        const noTripKey = '__no_trip__';

        void buildGroupCards(
          List<QueryDocumentSnapshot<Map<String, dynamic>>> list,
        ) {
          final Map<String,
              List<QueryDocumentSnapshot<Map<String, dynamic>>>> grouped = {};

          for (final doc in list) {
            final data = doc.data();
            final tripId = (data['data']?['tripId'] as String?) ?? noTripKey;
            grouped.putIfAbsent(tripId, () => []).add(doc);
          }

          grouped.forEach((tripId, groupDocs) {
            if (tripId == noTripKey || groupDocs.length == 1) {
              for (final d in groupDocs) {
                final map = d.data();
                map['id'] = d.id;
                final isRead = map['read'] ?? false;
                widgets.add(_wrapDismissibleCard(map, isRead));
              }
            } else {
              final first = groupDocs.first.data();
              final summary = <String, dynamic>{
                'id': groupDocs.first.id,
                'title': first['title'] ?? 'Trip updates',
                'body':
                    '${groupDocs.length} notifications for this trip. Tap to view details.',
                'type': 'trip_group',
                'createdAt': first['createdAt'],
                'read': groupDocs.every((d) => d.data()['read'] == true),
                'data': {
                  'tripId': first['data']?['tripId'],
                },
              };
              widgets.add(
                _wrapDismissibleCard(summary, summary['read'] ?? false),
              );
            }
          });
        }

        // pinned at top
        if (pinnedDocs.isNotEmpty) {
          widgets.add(
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Pinned',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
          );
          buildGroupCards(pinnedDocs);
          widgets.add(const Divider());
        }

        // others
        buildGroupCards(otherDocs);

        // pagination
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _limit += 20;
                  });
                },
                icon: const Icon(Icons.expand_more),
                label: const Text('Load more'),
              ),
            ),
          ),
        );

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: widgets,
        );
      },
    );
  }

  Widget _wrapDismissibleCard(
    Map<String, dynamic> notification,
    bool isRead,
  ) {
    final id = notification['id'] as String?;
    if (id == null) {
      return _buildNotificationCard(notification, isRead);
    }

    return Dismissible(
      key: ValueKey(id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: Colors.red.withOpacity(0.9),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) {
        _deleteNotification(id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification deleted')),
        );
      },
      child: GestureDetector(
        onTap: () => _handleNotificationTap(notification),
        onLongPress: () => _showNotificationOptions(notification, isRead),
        child: _buildNotificationCard(notification, isRead),
      ),
    );
  }

  Widget _buildNotificationCard(
    Map<String, dynamic> notification,
    bool isRead,
  ) {
    final title = notification['title'] as String? ?? '';
    final body = notification['body'] as String? ?? '';
    final type = notification['type'] as String? ?? 'info';
    final createdAt = notification['createdAt'] as Timestamp?;
    final time = createdAt != null
        ? DateFormat('MMM d, h:mm a').format(createdAt.toDate())
        : '';

    final isPinned = notification['pinned'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isRead ? Colors.grey[50] : _getNotificationColor(type),
      elevation: isRead ? 0 : 2,
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            _buildNotificationIcon(type),
            if (isPinned)
              const Positioned(
                right: -4,
                bottom: -4,
                child: Icon(
                  Icons.push_pin,
                  size: 14,
                  color: Colors.amber,
                ),
              ),
          ],
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
          ),
        ),
        subtitle: Text(body),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              time,
              style: const TextStyle(fontSize: 12),
            ),
            if (!isRead)
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DoraNotifications {
  static Stream<int> unreadCountStream(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }
}
