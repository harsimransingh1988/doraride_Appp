// lib/common/web/js_geocoder.dart
// Chooses mobile (HTTP) or web (JS SDK) reverse geocoder by platform.
//
// - On Web: uses js_geocoder_web.dart (your original JS/Maps implementation)
// - On Android/iOS: uses js_geocoder_mobile.dart (HTTP Geocoding API)

export 'js_geocoder_mobile.dart'
    if (dart.library.html) 'js_geocoder_web.dart';
