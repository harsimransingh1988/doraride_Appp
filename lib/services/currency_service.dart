import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class CurrencyService {
  static const Map<String, String> _countryToCurrency = {
    'IN': 'INR',
    'US': 'USD',
    'GB': 'GBP',
    'CA': 'CAD',
    'AU': 'AUD',
    'AE': 'AED',
    'SA': 'SAR',
    'PK': 'PKR',
    'BD': 'BDT',
    'DE': 'EUR',
    'FR': 'EUR',
    'IT': 'EUR',
    'ES': 'EUR',
    // add more if you want
  };

  static String currencyFromCountry(String? countryCode) {
    final cc = (countryCode ?? '').toUpperCase();
    return _countryToCurrency[cc] ?? 'USD';
  }

  /// Try GPS -> placemark ISO countryCode
  static Future<String?> detectCountryCodeFromGPS() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 8),
      );

      final placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );

      if (placemarks.isEmpty) return null;
      return placemarks.first.isoCountryCode;
    } catch (_) {
      return null;
    }
  }

  /// Fallback: device locale -> countryCode (like en_IN => IN)
  static String? countryCodeFromLocale(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return locale.countryCode; // may be null on some devices
  }
}
