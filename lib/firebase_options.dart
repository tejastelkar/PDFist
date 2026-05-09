import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web is not supported.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
            'DefaultFirebaseOptions are not supported for this platform.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDH_fiWjWZHPn41v6t6JFqoDnEOd7FRo7M',
    appId: '1:839099873252:android:cebc59b19f802e550839f1',
    messagingSenderId: '839099873252',
    projectId: 'pdfist-09',
    storageBucket: 'pdfist-09.firebasestorage.app',
  );
}
