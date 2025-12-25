// lib/firebase_options.dart
// ignore_for_file: type=lint

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return ios; // macOS same as iOS
      case TargetPlatform.windows:
        return web;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDJWu_E1ar-YuTn418J3MxL5oANY6cP56M',
    appId: '1:370934169599:web:b0b9c7d9d1b79dd1cf71ca',
    messagingSenderId: '370934169599',
    projectId: 'doraride-af3ec',
    authDomain: 'doraride-af3ec.firebaseapp.com',
    storageBucket: 'doraride-af3ec.firebasestorage.app',
    measurementId: 'G-50M6SN5C0W',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB-hZS8C05UZX35xLE_puOgBgj9JTX1id8',
    appId: '1:370934169599:android:cfbe7a86400b72fdcf71ca',
    messagingSenderId: '370934169599',
    projectId: 'doraride-af3ec',
    storageBucket: 'doraride-af3ec.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCvqX9_aV_PWHckZXgPP3ACssOFj-g41sA',
    appId: '1:370934169599:ios:932abcfaad8c1766cf71ca',
    messagingSenderId: '370934169599',
    projectId: 'doraride-af3ec',
    storageBucket: 'doraride-af3ec.firebasestorage.app',
    iosClientId:
        '370934169599-t6d5k63dm7aad2qmg9drptfqnnj27qu2.apps.googleusercontent.com',
    iosBundleId: 'com.example.doraride',
  );
}
