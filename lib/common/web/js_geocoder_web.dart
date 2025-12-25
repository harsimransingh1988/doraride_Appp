// lib/common/web/js_geocoder.dart
import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'package:js/js.dart';

/// Wait until the Google Maps JS SDK is ready
Future<bool> _waitForGoogleMaps({Duration timeout = const Duration(seconds: 10)}) async {
  final sw = Stopwatch()..start();
  print('🔄 Waiting for Google Maps JS SDK to load...');
  
  while (sw.elapsed < timeout) {
    try {
      final google = js_util.getProperty(html.window, 'google');
      if (google != null) {
        final maps = js_util.getProperty(google, 'maps');
        if (maps != null) {
          final geocoderCtor = js_util.getProperty(maps, 'Geocoder');
          if (geocoderCtor != null) {
            print('✅ Google Maps JS SDK loaded successfully');
            return true;
          }
        }
      }
    } catch (e) {
      print('❌ Error checking Google Maps: $e');
    }
    
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  
  print('❌ Google Maps JS SDK loading timeout');
  return false;
}

/// Reverse geocode using JavaScript Geocoder
Future<String> reverseGeocodeWithJs(double lat, double lng) async {
  print('📍 Starting reverse geocode for: $lat, $lng');
  
  try {
    final ok = await _waitForGoogleMaps();
    if (!ok) {
      print('❌ Google Maps not loaded');
      return 'Google Maps not loaded';
    }

    final google = js_util.getProperty(html.window, 'google');
    final maps = js_util.getProperty(google, 'maps');

    final geocoderCtor = js_util.getProperty(maps, 'Geocoder');
    final latLngCtor = js_util.getProperty(maps, 'LatLng');
    
    if (geocoderCtor == null) {
      print('❌ Geocoder constructor not found');
      return 'Geocoder not available';
    }
    
    if (latLngCtor == null) {
      print('❌ LatLng constructor not found');
      return 'LatLng not available';
    }

    print('✅ Creating Geocoder instance...');
    final geocoder = js_util.callConstructor(geocoderCtor, const []);
    final latLng = js_util.callConstructor(latLngCtor, [lat, lng]);
    final req = js_util.jsify({'location': latLng});

    final completer = Completer<String>();

    print('🔄 Calling geocode API...');
    
    // FIX: Use allowInterop to wrap the Dart callback
    final callback = allowInterop((results, status) {
      print('📡 Geocode response - Status: $status');
      
      try {
        if (status == 'OK' && results != null) {
          final length = js_util.getProperty(results, 'length') as int? ?? 0;
          print('📊 Results count: $length');
          
          if (length > 0) {
            final first = js_util.getProperty(results, 0);
            final addr = js_util.getProperty(first, 'formatted_address') as String?;
            print('✅ Address found: ${addr ?? "NULL"}');
            completer.complete(addr ?? 'Address format error');
          } else {
            print('❌ No results in response');
            completer.complete('No results found');
          }
        } else {
          print('❌ Geocoding failed with status: $status');
          completer.complete('Geocoding failed: $status');
        }
      } catch (e) {
        print('❌ Error processing results: $e');
        completer.complete('Error processing results: $e');
      }
    });

    js_util.callMethod(geocoder, 'geocode', [req, callback]);

    final result = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        print('⏰ Geocoding timeout');
        return 'Geocoding timeout';
      },
    );
    
    print('🎯 Geocoding completed: $result');
    return result;
  } catch (e) {
    print('❌ Geocoding error: $e');
    return 'Geocoding error: $e';
  }
}