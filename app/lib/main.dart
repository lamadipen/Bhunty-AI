import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'ai/demo_services.dart';
import 'app.dart';
import 'data/demo_data.dart';
import 'firebase/auth_service.dart';
import 'firebase/firebase_root.dart';
import 'firebase/firestore_backend.dart';
import 'firebase_options.dart';

/// `demo` (default): in-memory demo shop, no login.
/// `firebase`: phone login and the shop saved in Firestore —
/// `flutter run --dart-define=BACKEND=firebase` (after `flutterfire configure`).
const _backend = String.fromEnvironment('BACKEND', defaultValue: 'demo');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The AI backend (Cloud Functions) is Phase 2; the scripted demo stands in for it.
  final assistant = DemoAssistantService();
  final scanner = DemoBarcodeScanner();

  if (_backend != 'firebase') {
    runApp(BhunteApp(store: demoStore(), assistant: assistant, scanner: scanner));
    return;
  }

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
    ),
  );
}
