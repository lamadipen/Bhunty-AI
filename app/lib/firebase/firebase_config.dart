import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Web Firebase settings, given at build time so no project details live in
/// the repo: `--dart-define-from-file=firebase.local.json` (see
/// firebase.example.json). Android and iOS read their git-ignored native files
/// (google-services.json / GoogleService-Info.plist) instead.
FirebaseOptions? webFirebaseOptionsFromDefines() {
  const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  const appId = String.fromEnvironment('FIREBASE_APP_ID');
  const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  const storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  if (apiKey.isEmpty || appId.isEmpty || projectId.isEmpty) return null;
  return const FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
    authDomain: authDomain == '' ? null : authDomain,
    storageBucket: storageBucket == '' ? null : storageBucket,
  );
}
