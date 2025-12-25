// lib/features/payments/payment_gateway_page.dart
export 'payment_gateway_page_mobile.dart'
    if (dart.library.html) 'payment_gateway_page_web.dart';
