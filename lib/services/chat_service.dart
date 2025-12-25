// lib/services/chat_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:doraride_appp/common/chat_ids.dart';

/// DoraRide Chat Service with trip-specific conversations + unread counts
class ChatService {
  ChatService._();
  static final ChatService _instance = ChatService._();
  factory ChatService() => _instance;

  final _db = FirebaseFirestore.instance;

  static const String _conversations = 'conversations';
  static const String _messages = 'messages';

  // ======================
  // TRIP-SPECIFIC CHAT API
  // ======================

  /// Ensure a TRIP-SPECIFIC conversation exists (rules-friendly).
  /// We ALWAYS do a `set(..., merge: true)` with a concrete participants LIST.
  Future<String> ensureConversationTrip({
    required String me,
    required String other,
    required String tripId,
    String? segmentFrom,
    String? segmentTo,
  }) async {
    final chatId = chatIdForTrip(me, other, tripId);
    final participants = [me, other]..sort();
    final convoRef = _db.collection(_conversations).doc(chatId);

    await convoRef.set({
      'participants': participants,
      'tripId': tripId,
      'segmentFrom': segmentFrom ?? '',
      'segmentTo': segmentTo ?? '',
      'type': 'trip',
      'createdAt': FieldValue.serverTimestamp(),
      'lastAt': FieldValue.serverTimestamp(),
      'read': {
        me: FieldValue.serverTimestamp(),
        other: FieldValue.serverTimestamp(),
      },
      // NEW: initialise unread counts, merge:true will create or update
      'unreadCount': {
        me: 0,
        other: 0,
      },
      // keep lastMessage/lastSender absent until first message
    }, SetOptions(merge: true));

    return chatId;
  }

  /// Get trip-specific chat ID
  String getTripChatId(String tripId, String uidA, String uidB) {
    return chatIdForTrip(uidA, uidB, tripId);
  }

  /// Send message in TRIP-SPECIFIC conversation
  Future<bool> sendMessageInTrip({
    required String tripId,
    required String senderId,
    required String recipientId,
    required String text,
  }) async {
    try {
      final chatId = chatIdForTrip(senderId, recipientId, tripId);
      final clean = text.trim();
      if (clean.isEmpty) return false;

      final convRef = _db.collection(_conversations).doc(chatId);
      final messagesCol = convRef.collection(_messages);

      // Ensure conversation exists (idempotent upsert).
      await ensureConversationTrip(
        me: senderId,
        other: recipientId,
        tripId: tripId,
      );

      // Add message (rules: convo must exist, sender is participant, senderId == auth.uid)
      await messagesCol.add({
        'senderId': senderId,
        'text': clean,
        'type': 'text',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update conversation summary + unread counts
      await convRef.set({
        'lastMessage': clean,
        'lastSender': senderId,
        'lastAt': FieldValue.serverTimestamp(),
        'read': {
          senderId: FieldValue.serverTimestamp(),
          // mark recipient as unread: clear their read timestamp
          recipientId: null,
        },
        // 🔥 unread logic — increment for recipient, reset for sender
        'unreadCount.$recipientId': FieldValue.increment(1),
        'unreadCount.$senderId': 0,
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      // ignore: avoid_print
      print('❌ Error sending trip message: $e');
      return false;
    }
  }

  /// Stream messages for a TRIP-SPECIFIC conversation
  Stream<QuerySnapshot<Map<String, dynamic>>> streamTripMessages(
    String tripId,
    String uidA,
    String uidB,
  ) {
    final chatId = chatIdForTrip(uidA, uidB, tripId);
    return _db
        .collection(_conversations)
        .doc(chatId)
        .collection(_messages)
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  /// Mark TRIP-SPECIFIC conversation as read
  Future<void> markTripConversationRead({
    required String tripId,
    required String myUid,
    required String otherUid,
  }) async {
    final chatId = chatIdForTrip(myUid, otherUid, tripId);
    final convRef = _db.collection(_conversations).doc(chatId);

    await convRef.set({
      'lastAt': FieldValue.serverTimestamp(),
      'read': {myUid: FieldValue.serverTimestamp()},
      // 🔥 reset my unread count to 0
      'unreadCount.$myUid': 0,
    }, SetOptions(merge: true));
  }

  // ==========================
  // LEGACY CHAT SUPPORT
  // ==========================

  Future<String> ensureConversation({
    required String me,
    required String other,
  }) async {
    final chatId = chatIdFor(me, other);
    final participants = [me, other]..sort();
    final convoRef = _db.collection(_conversations).doc(chatId);

    await convoRef.set({
      'participants': participants,
      'createdAt': FieldValue.serverTimestamp(),
      'lastAt': FieldValue.serverTimestamp(),
      'read': {
        me: FieldValue.serverTimestamp(),
        other: FieldValue.serverTimestamp(),
      },
      // NEW: initialise unread counts for legacy chat
      'unreadCount': {
        me: 0,
        other: 0,
      },
    }, SetOptions(merge: true));

    return chatId;
  }

  Future<bool> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
    String? recipientId,
  }) async {
    try {
      final clean = text.trim();
      if (clean.isEmpty) return false;

      final convRef = _db.collection(_conversations).doc(chatId);
      final messagesCol = convRef.collection(_messages);

      // Make sure a shell convo exists (covers first message in legacy chat)
      await convRef.set({
        'createdAt': FieldValue.serverTimestamp(),
        'lastAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await messagesCol.add({
        'senderId': senderId,
        'text': clean,
        'type': 'text',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Conversation summary + unread counts (legacy)
      await convRef.set({
        'lastMessage': clean,
        'lastSender': senderId,
        'lastAt': FieldValue.serverTimestamp(),
        if (recipientId != null)
          'read': {
            senderId: FieldValue.serverTimestamp(),
            recipientId: null, // mark recipient as unread
          },
        if (recipientId != null) ...{
          // 🔥 unread handling for legacy chat
          'unreadCount.$recipientId': FieldValue.increment(1),
          'unreadCount.$senderId': 0,
        },
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      // ignore: avoid_print
      print('❌ Error sending legacy message: $e');
      return false;
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamMessages(String chatId) {
    return _db
        .collection(_conversations)
        .doc(chatId)
        .collection(_messages)
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  Future<void> markConversationRead({
    required String chatId,
    required String myUid,
  }) async {
    await _db.collection(_conversations).doc(chatId).set({
      'lastAt': FieldValue.serverTimestamp(),
      'read': {myUid: FieldValue.serverTimestamp()},
      // 🔥 reset my unread count to 0
      'unreadCount.$myUid': 0,
    }, SetOptions(merge: true));
  }

  /// Chat ID (without trip)
  String chatIdFor(String a, String b) {
    return (a.compareTo(b) < 0) ? '${a}_$b' : '${b}_$a';
  }

  /// Check if conversation exists
  Future<bool> doesConversationExist(String chatId) async {
    try {
      final doc = await _db.collection(_conversations).doc(chatId).get();
      return doc.exists;
    } catch (e) {
      // ignore: avoid_print
      print('❌ Error checking conversation existence: $e');
      return false;
    }
  }

  /// Get or create conversation (universal method)
  Future<String> getOrCreateConversation({
    required String userA,
    required String userB,
    String? tripId,
    String? segmentFrom,
    String? segmentTo,
  }) async {
    if (tripId != null && tripId.isNotEmpty) {
      return await ensureConversationTrip(
        me: userA,
        other: userB,
        tripId: tripId,
        segmentFrom: segmentFrom,
        segmentTo: segmentTo,
      );
    } else {
      return await ensureConversation(me: userA, other: userB);
    }
  }

  /// Send message universal method
  Future<bool> sendUniversalMessage({
    required String senderId,
    required String recipientId,
    required String text,
    String? tripId,
  }) async {
    if (tripId != null && tripId.isNotEmpty) {
      return await sendMessageInTrip(
        tripId: tripId,
        senderId: senderId,
        recipientId: recipientId,
        text: text,
      );
    } else {
      final chatId = chatIdFor(senderId, recipientId);
      return await sendMessage(
        chatId: chatId,
        senderId: senderId,
        text: text,
        recipientId: recipientId,
      );
    }
  }

  /// Stream messages universal method
  Stream<QuerySnapshot<Map<String, dynamic>>> streamUniversalMessages({
    required String userA,
    required String userB,
    String? tripId,
  }) {
    if (tripId != null && tripId.isNotEmpty) {
      return streamTripMessages(tripId, userA, userB);
    } else {
      final chatId = chatIdFor(userA, userB);
      return streamMessages(chatId);
    }
  }
}
