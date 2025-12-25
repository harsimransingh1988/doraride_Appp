// lib/features/chat/open_trip_chat.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// Import your existing chat screen and services
import 'chat_screen.dart';
import 'package:doraride_appp/services/chat_service.dart';
import 'package:doraride_appp/common/chat_ids.dart';

/// Opens a chat conversation for a trip using your existing chat structure
/// Creates the conversation if it doesn't exist, then navigates to the chat screen
Future<void> openTripChat({
  required BuildContext context,
  required String tripId,
  required String driverId,
  required String? riderId,
  required String segmentFrom,
  required String segmentTo,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to start chatting')),
      );
    }
    return;
  }

  // Show loading indicator
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(
      child: CircularProgressIndicator(),
    ),
  );

  try {
    // Determine who is initiating the chat and who is the other participant
    final isDriver = user.uid == driverId;
    final otherUserId = isDriver ? (riderId ?? '') : driverId;
    
    if (otherUserId.isEmpty) {
      if (context.mounted) {
        Navigator.pop(context); // Remove loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to start chat: missing participant')),
        );
      }
      return;
    }

    // Generate chat ID using your specific format: {tripId}_{uidA}_{uidB}
    final chatId = chatIdForTrip(user.uid, otherUserId, tripId);
    
    // Ensure conversation exists with proper structure
    await ensureTripConversation(
      tripId: tripId,
      currentUserId: user.uid,
      otherUserId: otherUserId,
      segmentFrom: segmentFrom,
      segmentTo: segmentTo,
    );

    // Remove loading indicator
    if (context.mounted) {
      Navigator.pop(context);
    }

    // Navigate to your existing ChatScreen
    if (!context.mounted) return;
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          chatId: chatId,
          recipientId: otherUserId,
          segmentFrom: segmentFrom,
          segmentTo: segmentTo,
          tripId: tripId,
        ),
      ),
    );
    
  } catch (e, stackTrace) {
    print('Error opening chat: $e');
    print('Stack trace: $stackTrace');
    
    // Remove loading indicator
    if (context.mounted) {
      Navigator.pop(context);
    }
    
    if (context.mounted) {
      String errorMessage = 'Failed to open chat';
      
      // Provide user-friendly error messages
      if (e.toString().contains('permission-denied') || e.toString().contains('PERMISSION_DENIED')) {
        errorMessage = 'Chat permission denied. Please make sure you are signed in.';
      } else if (e.toString().contains('not-found')) {
        errorMessage = 'Unable to start chat. Please try again.';
      } else {
        errorMessage = 'Failed to open chat: $e';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}

/// Ensure trip conversation exists with proper structure
Future<void> ensureTripConversation({
  required String tripId,
  required String currentUserId,
  required String otherUserId,
  required String segmentFrom,
  required String segmentTo,
}) async {
  final participants = [currentUserId, otherUserId];
  participants.sort();
  
  final chatId = chatIdForTrip(currentUserId, otherUserId, tripId);
  
  final conversationRef = FirebaseFirestore.instance
      .collection('conversations')
      .doc(chatId);

  final conversationDoc = await conversationRef.get();
  
  if (!conversationDoc.exists) {
    print('Creating new trip conversation: $chatId');
    
    // Get user display names if available
    String? currentUserName;
    String? otherUserName;
    
    try {
      final currentUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .get();
      if (currentUserDoc.exists) {
        final data = currentUserDoc.data();
        currentUserName = data?['displayName'] ?? data?['firstName'] ?? 'User';
      }
    } catch (e) {
      print('Error fetching current user name: $e');
    }
    
    try {
      final otherUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(otherUserId)
          .get();
      if (otherUserDoc.exists) {
        final data = otherUserDoc.data();
        otherUserName = data?['displayName'] ?? data?['firstName'] ?? 'User';
      }
    } catch (e) {
      print('Error fetching other user name: $e');
    }
    
    final conversationData = {
      'id': chatId,
      'tripId': tripId,
      'participants': participants,
      'participantNames': {
        currentUserId: currentUserName ?? 'User',
        otherUserId: otherUserName ?? 'User',
      },
      'tripInfo': {
        'from': segmentFrom,
        'to': segmentTo,
        'tripId': tripId,
      },
      'lastMessage': '',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastMessageSender': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'unreadCount': {
        currentUserId: 0,
        otherUserId: 0,
      },
    };

    await conversationRef.set(conversationData);
    print('Successfully created trip conversation: $chatId');
  } else {
    print('Trip conversation already exists: $chatId');
    
    // Update trip info if needed
    await conversationRef.update({
      'tripInfo.from': segmentFrom,
      'tripInfo.to': segmentTo,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

/// Alternative function that returns the chat ID for use in other parts of the app
Future<String?> getOrCreateTripConversation({
  required String tripId,
  required String driverId,
  required String? riderId,
  String? segmentFrom,
  String? segmentTo,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;

  try {
    final isDriver = user.uid == driverId;
    final otherUserId = isDriver ? (riderId ?? '') : driverId;
    
    if (otherUserId.isEmpty) return null;

    // Generate chat ID using your format
    final chatId = chatIdForTrip(user.uid, otherUserId, tripId);
    
    // Ensure conversation exists
    await ensureTripConversation(
      tripId: tripId,
      currentUserId: user.uid,
      otherUserId: otherUserId,
      segmentFrom: segmentFrom ?? 'Unknown',
      segmentTo: segmentTo ?? 'Unknown',
    );

    return chatId;
  } catch (e) {
    print('Error getting conversation: $e');
    return null;
  }
}

/// Check if a conversation exists for a trip
Future<bool> doesTripConversationExist({
  required String tripId,
  required String currentUserId,
  required String otherUserId,
}) async {
  try {
    final chatId = chatIdForTrip(currentUserId, otherUserId, tripId);
    
    final conversationDoc = await FirebaseFirestore.instance
        .collection('conversations')
        .doc(chatId)
        .get();
        
    return conversationDoc.exists;
  } catch (e) {
    print('Error checking conversation existence: $e');
    return false;
  }
}

/// Send a message in a trip conversation
Future<void> sendTripMessage({
  required String tripId,
  required String senderId,
  required String recipientId,
  required String text,
}) async {
  try {
    final chatId = chatIdForTrip(senderId, recipientId, tripId);
    
    final messagesRef = FirebaseFirestore.instance
        .collection('conversations')
        .doc(chatId)
        .collection('messages')
        .doc();

    final messageData = {
      'id': messagesRef.id,
      'conversationId': chatId,
      'senderId': senderId,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'readBy': [senderId],
    };

    // Add message to messages subcollection
    await messagesRef.set(messageData);

    // Update conversation last message and timestamp
    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(chatId)
        .update({
          'lastMessage': text,
          'lastMessageTime': FieldValue.serverTimestamp(),
          'lastMessageSender': senderId,
          'updatedAt': FieldValue.serverTimestamp(),
        });

    print('Message sent successfully in trip conversation: $chatId');
  } catch (e) {
    print('Error sending message: $e');
    rethrow;
  }
}

/// Get unread message count for a trip conversation
Future<int> getTripUnreadCount({
  required String tripId,
  required String currentUserId,
  required String otherUserId,
}) async {
  try {
    final chatId = chatIdForTrip(currentUserId, otherUserId, tripId);
    
    final conversationDoc = await FirebaseFirestore.instance
        .collection('conversations')
        .doc(chatId)
        .get();
        
    if (conversationDoc.exists) {
      final data = conversationDoc.data();
      final unreadCount = data?['unreadCount'] as Map<String, dynamic>?;
      return (unreadCount?[currentUserId] as int?) ?? 0;
    }
    
    return 0;
  } catch (e) {
    print('Error getting unread count: $e');
    return 0;
  }
}

/// Mark trip conversation as read
Future<void> markTripConversationAsRead({
  required String tripId,
  required String currentUserId,
  required String otherUserId,
}) async {
  try {
    final chatId = chatIdForTrip(currentUserId, otherUserId, tripId);
    
    // Reset unread count for current user
    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(chatId)
        .update({
          'unreadCount.$currentUserId': 0,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        
    print('Marked trip conversation as read: $chatId');
  } catch (e) {
    print('Error marking conversation as read: $e');
  }
}

/// Get list of trip conversations for a user
Stream<QuerySnapshot<Map<String, dynamic>>> getTripConversations(String userId) {
  return FirebaseFirestore.instance
      .collection('conversations')
      .where('participants', arrayContains: userId)
      .where('tripId', isNotEqualTo: null)
      .orderBy('lastMessageTime', descending: true)
      .snapshots();
}

/// Helper to extract trip info from chat ID using your format
Map<String, String>? getTripInfoFromChatId(String chatId) {
  if (!isTripChatId(chatId)) return null;
  
  try {
    final parts = chatId.split('_');
    if (parts.length >= 3) {
      return {
        'tripId': parts[0], // First part is tripId in your format
        'user1': parts[1],
        'user2': parts[2],
      };
    }
  } catch (e) {
    print('Error parsing chat ID: $e');
  }
  
  return null;
}

/// Get the other participant ID from a chat ID
String? getOtherParticipant(String chatId, String currentUserId) {
  final tripInfo = getTripInfoFromChatId(chatId);
  if (tripInfo != null) {
    final user1 = tripInfo['user1'];
    final user2 = tripInfo['user2'];
    
    if (user1 == currentUserId) return user2;
    if (user2 == currentUserId) return user1;
  }
  return null;
}

/// Check if current user can access this trip chat
bool canAccessTripChat(String chatId, String currentUserId) {
  final tripInfo = getTripInfoFromChatId(chatId);
  if (tripInfo != null) {
    final user1 = tripInfo['user1'];
    final user2 = tripInfo['user2'];
    return user1 == currentUserId || user2 == currentUserId;
  }
  return false;
}

/// Get display name for trip chat
Future<String> getTripChatDisplayName(String chatId, String currentUserId) async {
  final otherUserId = getOtherParticipant(chatId, currentUserId);
  
  if (otherUserId == null) return 'Unknown User';
  
  try {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(otherUserId)
        .get();
        
    if (userDoc.exists) {
      final data = userDoc.data();
      final displayName = data?['displayName'] ?? data?['firstName'] ?? 'User';
      return displayName;
    }
  } catch (e) {
    print('Error fetching user name: $e');
  }
  
  return 'User';
}