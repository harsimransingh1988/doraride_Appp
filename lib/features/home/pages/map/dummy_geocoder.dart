// lib/features/home/pages/map/dummy_geocoder.dart

// Dummy implementation for web platform
Future<String> reverseGeocodeNative(double lat, double lng) async {
  // This should never be called on web since we use kIsWeb check
  return 'Native geocoder not available on web';
} 