// lib/features/chat/chat_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:doraride_appp/services/chat_service.dart';
import 'package:doraride_appp/common/chat_ids.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class _RecipientName extends StatelessWidget {
  final String recipientId;
  const _RecipientName({required this.recipientId});

  String _getDisplayName(Map<String, dynamic> data) {
    final firstName = (data['firstName'] ?? '').toString().trim();
    final lastName = (data['lastName'] ?? '').toString().trim();
    final fullName = [firstName, lastName].where((s) => s.isNotEmpty).join(' ');
    if (fullName.isNotEmpty) return fullName;

    final email = (data['email'] ?? '').toString();
    if (email.isNotEmpty) return email.split('@').first;

    return 'Loading User...';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(recipientId).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Text('Loading...', style: TextStyle(color: Colors.white));
        }
        if (snap.hasData && snap.data!.exists) {
          return Text(
            _getDisplayName(snap.data!.data()!),
            style: const TextStyle(color: Colors.white),
          );
        }
        return const Text(
          'User Not Found',
          style: TextStyle(color: Colors.white),
        );
      },
    );
  }
}

/// Small banner under the app bar to display trip/segment context (optional)
Widget _buildContextBanner(
  BuildContext context,
  String? tripId,
  String? requestId,
  String? from,
  String? to,
) {
  final route = [
    if (from != null && from.isNotEmpty) from,
    if (to != null && to.isNotEmpty) to,
  ].join(' → ');

  // --- Banner for a RIDE REQUEST ---
  if (requestId != null && requestId.isNotEmpty) {
    return Container(
      width: double.infinity,
      color: Colors.blue.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.hail, color: Colors.blue.shade900), // Request icon
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (route.isNotEmpty)
                  Text(
                    route,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade900,
                    ),
                  ),
                Text(
                  'About ride request',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Banner for a DRIVER TRIP ---
  if (tripId != null && tripId.isNotEmpty) {
    // If we already have route from segmentFrom/segmentTo, use it as initial.
    final initialRoute = route;

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future:
          FirebaseFirestore.instance.collection('trips').doc(tripId).get(),
      builder: (context, snap) {
        String finalRoute = initialRoute;

        if (snap.hasData && snap.data!.exists) {
          final trip = snap.data!.data()!;
          final origin = (trip['origin'] ?? '').toString().trim();
          final destination = (trip['destination'] ?? '').toString().trim();

          // Fallback to trip doc if we didn't get route via arguments
          if (finalRoute.isEmpty &&
              origin.isNotEmpty &&
              destination.isNotEmpty) {
            finalRoute = '$origin → $destination';
          }
        }

        return Container(
          width: double.infinity,
          color: Colors.white, // keep original white banner
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.directions_car, color: _kThemeBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (finalRoute.isNotEmpty)
                      Text(
                        finalRoute,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    // 🔻 Trip ID line removed as requested
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // No context, no banner
  return const SizedBox.shrink();
}

class ChatScreen extends StatefulWidget {
  final String? chatId;
  final String recipientId; // who I'm chatting with
  final String? segmentFrom;
  final String? segmentTo;
  final String? tripId;
  final String? requestId;

  const ChatScreen({
    super.key,
    this.chatId,
    required this.recipientId,
    this.segmentFrom,
    this.segmentTo,
    this.tripId,
    this.requestId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final ChatService _chatService = ChatService();

  String? _activeChatId;
  bool _isLoadingId = true;

  // prevent duplicate sends when pressing enter multiple times quickly
  bool _isSending = false;

  String get myUid {
    final user = FirebaseAuth.instance.currentUser;
    return user?.uid ?? '';
  }

  String get _routeText {
    final from = widget.segmentFrom;
    final to = widget.segmentTo;
    final parts = <String>[];
    if (from != null && from.isNotEmpty) parts.add(from);
    if (to != null && to.isNotEmpty) parts.add(to);
    return parts.join(' → ');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeChat();
    });
  }

  Future<void> _initializeChat() async {
    if (myUid.isEmpty) {
      _showNotSignedInDialog();
      setState(() => _isLoadingId = false);
      return;
    }

    String? effectiveChatId = widget.chatId;

    if (effectiveChatId == null || effectiveChatId.isEmpty) {
      if (widget.recipientId.isEmpty) {
        setState(() => _isLoadingId = false);
        return;
      }

      if (myUid.compareTo(widget.recipientId) < 0) {
        effectiveChatId = '${myUid}_${widget.recipientId}';
      } else {
        effectiveChatId = '${widget.recipientId}_${myUid}';
      }
    }

    setState(() {
      _activeChatId = effectiveChatId;
      _isLoadingId = false;
    });

    if (_activeChatId != null && _activeChatId!.isNotEmpty) {
      try {
        // Tag conversation with requestId if provided
        if (widget.requestId != null && widget.requestId!.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('conversations')
              .doc(_activeChatId)
              .set(
            {
              'associatedRequestIds':
                  FieldValue.arrayUnion([widget.requestId]),
            },
            SetOptions(merge: true),
          );
        }

        final isTrip = isTripChatId(_activeChatId!);

        if (isTrip && widget.tripId != null && widget.tripId!.isNotEmpty) {
          await _chatService.ensureConversationTrip(
            me: myUid,
            other: widget.recipientId,
            tripId: widget.tripId!,
            segmentFrom: widget.segmentFrom,
            segmentTo: widget.segmentTo,
          );
          await _chatService.markTripConversationRead(
            tripId: widget.tripId!,
            myUid: myUid,
            otherUid: widget.recipientId,
          );
        } else {
          final parts = _activeChatId!.split('_');
          if (parts.length == 2) {
            await _chatService.ensureConversation(
              me: parts[0],
              other: parts[1],
            );
          }
          await _chatService.markConversationRead(
            chatId: _activeChatId!,
            myUid: myUid,
          );
        }
      } catch (e) {
        // ignore: avoid_print
        print('❌ Error in chat initialization: $e');
      }
    }
  }

  void _showNotSignedInDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign in required'),
        content: const Text('Please sign in to use chat.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // close dialog
              Navigator.of(context).pop(); // leave chat
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (myUid.isEmpty) {
      _showNotSignedInDialog();
      return;
    }

    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_activeChatId == null || _activeChatId!.isEmpty) return;

    // prevent double-send if user hits Enter multiple times quickly
    if (_isSending) return;
    _isSending = true;

    try {
      final isTrip = isTripChatId(_activeChatId!);

      if (isTrip && widget.tripId != null && widget.tripId!.isNotEmpty) {
        await _chatService.sendMessageInTrip(
          tripId: widget.tripId!,
          senderId: myUid,
          recipientId: widget.recipientId,
          text: text,
        );
      } else {
        await _chatService.sendMessage(
          chatId: _activeChatId!,
          senderId: myUid,
          text: text,
          recipientId: widget.recipientId,
        );
      }

      _controller.clear();

      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 72,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } finally {
      _isSending = false;
    }
  }

  PreferredSizeWidget _buildAppBar() {
    final route = _routeText;

    return AppBar(
      backgroundColor: _kThemeBlue,
      foregroundColor: Colors.white,
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RecipientName(recipientId: widget.recipientId),
          if (route.isNotEmpty)
            Text(
              route,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingId) {
      return Scaffold(
        appBar: _buildAppBar(),
        backgroundColor: _kThemeGreen,
        body: Column(
          children: [
            _buildContextBanner(
              context,
              widget.tripId,
              widget.requestId,
              widget.segmentFrom,
              widget.segmentTo,
            ),
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    if (_activeChatId == null || _activeChatId!.isEmpty) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: const Center(child: Text('No chat specified')),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(),
      backgroundColor: _kThemeGreen,
      body: Column(
        children: [
          _buildContextBanner(
            context,
            widget.tripId,
            widget.requestId,
            widget.segmentFrom,
            widget.segmentTo,
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: () {
                final isTrip = isTripChatId(_activeChatId!);
                if (isTrip && widget.tripId != null && widget.tripId!.isNotEmpty) {
                  return _chatService.streamTripMessages(
                    widget.tripId!,
                    myUid,
                    widget.recipientId,
                  );
                } else {
                  return _chatService.streamMessages(_activeChatId!);
                }
              }(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? const [];

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scroll.hasClients) {
                    _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  }
                });

                return ListView.builder(
                  controller: _scroll,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final m = docs[index].data();
                    final fromMe = m['senderId'] == myUid;
                    final text = (m['text'] ?? '').toString();
                    final ts = m['createdAt'];
                    DateTime? when;
                    if (ts is Timestamp) when = ts.toDate();

                    return Align(
                      alignment:
                          fromMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        constraints: BoxConstraints(
                          maxWidth:
                              MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: fromMe ? _kThemeBlue : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: fromMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Text(
                              text,
                              style: TextStyle(
                                color: fromMe
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                            if (when != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                TimeOfDay.fromDateTime(when).format(context),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: fromMe
                                      ? Colors.white70
                                      : Colors.black45,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Type a message…',
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Send Button (Circular)
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: _kThemeBlue,
                    child: IconButton(
                      icon: const Icon(Icons.send,
                          color: Colors.white, size: 20),
                      onPressed: _send,
                      tooltip: 'Send',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
