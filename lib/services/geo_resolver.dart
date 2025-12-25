// lib/services/geo_resolver.dart
// Picks mobile or web implementation depending on platform.

export 'geo_resolver_mobile.dart'
    if (dart.library.html) 'geo_resolver_web.dart';
