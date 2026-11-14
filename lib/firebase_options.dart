import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return android;
    }
    throw UnsupportedError(
      'Firebase configuration is currently provided for Android only.',
    );
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD6ZtHvfUDA3y6zFDnc5PCJlOgfFR3R4Xw',
    appId: '1:617449113035:android:6670d3f645394232aaa24e',
    messagingSenderId: '617449113035',
    projectId: 'ziyarat-ashura-796c7',
    storageBucket: 'ziyarat-ashura-796c7.firebasestorage.app',
  );
}
