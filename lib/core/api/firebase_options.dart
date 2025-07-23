import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
  show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static final FirebaseOptions web = FirebaseOptions(
    apiKey: dotenv.env['FIREBASE_API_KEY_WEB']!,
    appId: dotenv.env['FIREBASE_APP_ID_WEB']!,
    messagingSenderId: dotenv.env['FIREBASE_MESSAGING_SENDER_ID_WEB']!,
    projectId: dotenv.env['FIREBASE_PROJECT_ID_WEB']!,
    authDomain: dotenv.env['FIREBASE_AUTH_DOMAIN_WEB']!,
    storageBucket: dotenv.env['FIREBASE_STORAGE_BUCKET_WEB']!,
  );

  static final FirebaseOptions android = FirebaseOptions(
    apiKey: dotenv.env['FIREBASE_API_KEY_ANDROID']!,
    appId: dotenv.env['FIREBASE_APP_ID_ANDROID']!,
    messagingSenderId: dotenv.env['FIREBASE_MESSAGING_SENDER_ID_WEB']!,
    projectId: dotenv.env['FIREBASE_PROJECT_ID_WEB']!,
    storageBucket: dotenv.env['FIREBASE_STORAGE_BUCKET_WEB']!,
  );

  static final FirebaseOptions ios = FirebaseOptions(
    apiKey: dotenv.env['FIREBASE_API_KEY_IOS']!,
    appId: dotenv.env['FIREBASE_APP_ID_IOS']!,
    messagingSenderId: dotenv.env['FIREBASE_MESSAGING_SENDER_ID_WEB']!,
    projectId: dotenv.env['FIREBASE_PROJECT_ID_WEB']!,
    storageBucket: dotenv.env['FIREBASE_STORAGE_BUCKET_WEB']!,
    iosBundleId: dotenv.env['FIREBASE_IOS_BUNDLE_ID']!,
  );

  static final FirebaseOptions macos = FirebaseOptions(
    apiKey: dotenv.env['FIREBASE_API_KEY_IOS']!,
    appId: dotenv.env['FIREBASE_APP_ID_IOS']!,
    messagingSenderId: dotenv.env['FIREBASE_MESSAGING_SENDER_ID_WEB']!,
    projectId: dotenv.env['FIREBASE_PROJECT_ID_WEB']!,
    storageBucket: dotenv.env['FIREBASE_STORAGE_BUCKET_WEB']!,
    iosBundleId: dotenv.env['FIREBASE_IOS_BUNDLE_ID']!,
  );
}