// lib/common/config/maps_config.dart
//
// DoraRide Google Maps / Places configuration
// -------------------------------------------
// This reads your key from a --dart-define argument so you
// never hard-code it in source control.
//
// Run like this:
// flutter run -d chrome --dart-define=MAPS_API_KEY=YOUR_KEY
//
// (Example below uses your current key; you can rotate it later safely.)

const String kGoogleMapsApiKey =
    String.fromEnvironment('MAPS_API_KEY', defaultValue: 'AIzaSyBWwKkOXJ882pqKk3fzhP8I3JwUeGv3Rkc');
