// lib/common/chat_ids.dart

/// Build a trip-specific chat ID that includes the trip ID
String buildChatId({required String tripId, required String uidA, required String uidB}) {
  final users = [uidA, uidB]..sort();
  return '${tripId}_${users[0]}_${users[1]}';
}

/// Extract trip ID from a chat ID
String? extractTripIdFromChatId(String chatId) {
  final parts = chatId.split('_');
  if (parts.length >= 3) {
    return parts[0]; // First part is the tripId
  }
  return null;
}

/// Legacy chat ID (without trip) - for backward compatibility
String chatIdFor(String a, String b) {
  return (a.compareTo(b) < 0) ? '${a}_$b' : '${b}_$a';
}

/// Trip-specific chat ID helper
String chatIdForTrip(String uidA, String uidB, String tripId) {
  return buildChatId(tripId: tripId, uidA: uidA, uidB: uidB);
}

/// Check if chat ID is trip-specific
bool isTripChatId(String chatId) {
  return chatId.split('_').length >= 3;
}
