import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class DriverVerificationBadge extends StatelessWidget {
  final String userId;
  final bool compact; // if you want a small version for some screens

  const DriverVerificationBadge({
    super.key,
    required this.userId,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox.shrink();
        }

        final data = snap.data!.data() ?? {};
        final bool isVerified = data['isDriverVerified'] == true;
        final String status =
            (data['driverStatus'] ?? 'pending').toString();

        if (isVerified && status == 'approved') {
          // ✅ Approved & verified
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified,
                color: Colors.green.shade600,
                size: compact ? 16 : 18,
              ),
              if (!compact) const SizedBox(width: 4),
              if (!compact)
                Text(
                  'Verified driver',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
            ],
          );
        }

        if (status == 'pending') {
          // ⏳ Pending review
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.hourglass_bottom,
                color: Colors.orange.shade700,
                size: compact ? 16 : 18,
              ),
              if (!compact) const SizedBox(width: 4),
              if (!compact)
                Text(
                  'Verification pending',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
            ],
          );
        }

        // ❌ Not verified / rejected / nothing
        return const SizedBox.shrink();
      },
    );
  }
}
