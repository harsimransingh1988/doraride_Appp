import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UnreadMessagesStream {
  static Stream<int> unreadTotalForCurrentUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Stream<int>.value(0);
    }

    return FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snap) {
          int total = 0;
          for (final doc in snap.docs) {
            final data = doc.data();
            final unread = data['unreadCount'] as Map<String, dynamic>?;

            if (unread != null) {
              final myCount = unread[uid];
              if (myCount is int) total += myCount;
            }
          }
          return total;
        });
  }
}
