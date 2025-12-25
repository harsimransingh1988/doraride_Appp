// lib/services/invitation_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class InvitationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get received invitations for a user
  Stream<QuerySnapshot> getReceivedInvitations(String userId) {
    return _firestore
        .collection('invitations')
        .where('receiverId', isEqualTo: userId)
        .where('status', whereIn: ['pending', 'accepted'])
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Accept an invitation
  Future<void> acceptInvitation(String invitationId, String userId) async {
    try {
      await _firestore
          .collection('invitations')
          .doc(invitationId)
          .update({
        'status': 'accepted',
        'respondedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to accept invitation: $e');
    }
  }

  // Decline an invitation
  Future<void> declineInvitation(String invitationId, String userId) async {
    try {
      await _firestore
          .collection('invitations')
          .doc(invitationId)
          .update({
        'status': 'declined',
        'respondedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to decline invitation: $e');
    }
  }

  // Get invitation details
  Future<DocumentSnapshot> getInvitation(String invitationId) async {
    return await _firestore
        .collection('invitations')
        .doc(invitationId)
        .get();
  }

  // Check if user has pending invitations
  Future<bool> hasPendingInvitations(String userId) async {
    final snapshot = await _firestore
        .collection('invitations')
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    return snapshot.docs.isNotEmpty;
  }

  // Mark invitation as read
  Future<void> markAsRead(String invitationId) async {
    try {
      await _firestore
          .collection('invitations')
          .doc(invitationId)
          .update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to mark invitation as read: $e');
    }
  }

  // Get unread invitation count
  Stream<int> getUnreadInvitationCount(String userId) {
    return _firestore
        .collection('invitations')
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }
}