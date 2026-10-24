import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'ai/assistant_service.dart';
import 'ai/demo_services.dart';
import 'app.dart';
import 'data/demo_data.dart';
import 'firebase/auth_service.dart';
import 'firebase/firebase_config.dart';
import 'firebase/firebase_root.dart';
import 'firebase/firestore_backend.dart';
import 'scanning/scanner_screen.dart';

/// `demo` (default): in-memory demo shop, no login.
/// `firebase`: the shop saved in Firestore —
/// `flutter run --dart-define-from-file=firebase.local.json` (sets BACKEND and the
/// web settings; see app/README.md). Project details stay out of the repo.
const _backend = String.fromEnvironment('BACKEND', defaultValue: 'demo');

/// Phone OTP login is built but off for now; the app signs in anonymously.
/// Turn on with `--dart-define=PHONE_LOGIN=true`.
const _phoneLogin = bool.fromEnvironment('PHONE_LOGIN');

/// `camera` (default) scans with the phone camera; `demo` returns the sample
/// products' codes in turn (for demos and devices without a camera).
const _scanner = String.fromEnvironment('SCANNER', defaultValue: 'camera');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The AI backend (Cloud Functions) is Phase 2; the scripted demo stands in for it.
  final assistant = DemoAssistantService();
  final BarcodeScanner scanner = _scanner == 'demo' ? DemoBarcodeScanner() : const CameraBarcodeScanner();

  if (_backend != 'firebase') {
    runApp(BhunteApp(store: demoStore(), assistant: assistant, scanner: scanner));
    return;
  }

  try {
    // Android/iOS: null → read google-services.json / GoogleService-Info.plist.
    final options = kIsWeb ? webFirebaseOptionsFromDefines() : null;
    if (kIsWeb && options == null) {
      throw UnsupportedError('Web needs Firebase settings: run with --dart-define-from-file=firebase.local.json');
    }
    await Firebase.initializeApp(options: options);
  } catch (e) {
    runApp(ShellApp(home: FirebaseSetupProblem(error: e)));
    return;
  }
  final db = FirebaseFirestore.instance;
  // Offline-first: keep the whole shop in the local cache.
  db.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED);

  runApp(
    FirebaseRoot(
      auth: FirebaseAuthService(FirebaseAuth.instance),
      openShop: (uid) => openFirestoreShop(db: db, uid: uid),
      assistant: assistant,
      scanner: scanner,
      phoneLogin: _phoneLogin,
    ),
  );
}
