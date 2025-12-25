// lib/services/location_cache.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class LocationCache {
  static final _col =
      FirebaseFirestore.instance.collection('locations_cache');

  /// Read one cached entry by placeId
  static Future<Map<String, dynamic>?> get(String placeId) async {
    try {
      print('📥 LocationCache.get("$placeId")');
      final snap = await _col.doc(placeId).get();

      if (!snap.exists) {
        print('📥 LocationCache MISS for $placeId');
        return null;
      }

      final data = snap.data()!;
      print(
          '🔥 LocationCache HIT for $placeId (country=${data['countryCode']}, currency=${data['currencyCode']})');
      return data;
    } catch (e) {
      print('❌ LocationCache.get error: $e');
      return null;
    }
  }

  /// Save/update cache entry
  static Future<void> save({
    required String placeId,
    required String description,
    required double lat,
    required double lng,
    required String countryCode,
    required String currencyCode,
  }) async {
    try {
      print('💾 LocationCache.save("$placeId")');
      await _col.doc(placeId).set(
        {
          'placeId': placeId,
          'description': description,
          'lat': lat,
          'lng': lng,
          'countryCode': countryCode,
          'currencyCode': currencyCode,
          'createdAt': FieldValue.serverTimestamp(),
          'lastUsedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      print('✅ LocationCache saved for $placeId');
    } catch (e) {
      print('❌ LocationCache.save error: $e');
    }
  }

  /// Just bump lastUsedAt if it exists
  static Future<void> touch(String placeId) async {
    try {
      await _col
          .doc(placeId)
          .update({'lastUsedAt': FieldValue.serverTimestamp()});
    } catch (_) {
      // ignore, it's just a touch
    }
  }
}
