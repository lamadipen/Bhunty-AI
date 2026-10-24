import 'dart:async';

import 'package:flutter/material.dart';

import '../ai/assistant_service.dart';
import '../app.dart';
import '../bills/bill_reader.dart';
import '../data/shop_store.dart';
import '../photos/photo_reader.dart';
import '../screens/login_screen.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import 'auth_service.dart';
import 'firestore_backend.dart';

/// Opens the signed-in user's shop. Injected so tests can pass a fake Firestore.
typedef ShopOpener = Future<(ShopStore, FirestoreBackend)> Function(String uid);

/// Signed out → sign in (anonymously, or the phone login screen when
/// [phoneLogin] is on). Signed in → open the shop, then the normal app.
class FirebaseRoot extends StatefulWidget {
  const FirebaseRoot({
    super.key,
    required this.auth,
    required this.openShop,
    required this.assistant,
    required this.scanner,
    this.photoReader = const NoPhotoReader(),
    this.billReader = const NoBillReader(),
    this.phoneLogin = false,
  });

  final AuthService auth;
  final ShopOpener openShop;
  final AssistantService assistant;
  final BarcodeScanner scanner;
  final PhotoReader photoReader;
  final BillReader billReader;

  /// Off for now: the app signs in anonymously with no screen.
  final bool phoneLogin;

  @override
  State<FirebaseRoot> createState() => _FirebaseRootState();
}

class _FirebaseRootState extends State<FirebaseRoot> {
  StreamSubscription<String?>? _sub;
  bool _known = false;
  String? _uid;
  ShopStore? _store;
  FirestoreBackend? _backend;
  Object? _error;
  String? _signInError;
  int _opening = 0;

  @override
  void initState() {
    super.initState();
    _sub = widget.auth.userIds.listen(_onUser);
  }

  void _onUser(String? uid) {
    if (_known && uid == _uid) return;
    _close();
    setState(() {
      _known = true;
      _uid = uid;
      _error = null;
    });
    if (uid != null) {
      _open(uid);
    } else if (!widget.phoneLogin) {
      _signInAnonymously();
    }
  }

  Future<void> _signInAnonymously() async {
    setState(() => _signInError = null);
    try {
      await widget.auth.signInAnonymously(); // the auth stream then opens the shop
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _signInError = e.messageNe);
    } catch (e) {
      debugPrint('Bhunte: anonymous sign-in failed: $e');
      if (mounted) setState(() => _signInError = 'इन्टरनेट जोडेर फेरि प्रयास गर्नुस्');
    }
  }

  Future<void> _open(String uid) async {
    final attempt = ++_opening;
    setState(() => _error = null);
    try {
      final (store, backend) = await widget.openShop(uid);
      if (!mounted || attempt != _opening) {
        backend.close();
        store.dispose();
        return;
      }
      setState(() {
        _store = store;
        _backend = backend;
      });
    } catch (e) {
      debugPrint('Bhunte: could not open shop: $e');
      if (mounted && attempt == _opening) setState(() => _error = e);
    }
  }

  void _close() {
    _opening++;
    _backend?.close();
    final old = _store;
    // The old app still holds the store until this frame is rebuilt.
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _store = null;
    _backend = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_known) return const ShellApp(home: _Waiting(text: ''));
    if (_uid == null && widget.phoneLogin) return ShellApp(home: LoginScreen(auth: widget.auth));
    if (_uid == null) {
      final problem = _signInError;
      return ShellApp(
        home: problem == null
            ? const _Waiting(text: 'सुरु हुँदैछ…')
            : _Problem(title: 'सुरु गर्न सकिएन', detail: problem, onRetry: _signInAnonymously),
      );
    }
    // An anonymous account can't be signed back into, so only phone users may sign out.
    final signOut = widget.phoneLogin ? widget.auth.signOut : null;
    if (_error != null) {
      return ShellApp(
        home: _Problem(
          title: 'पसल खोल्न सकिएन',
          detail: 'पहिलो पटक खोल्दा इन्टरनेट चाहिन्छ। जोडेर फेरि प्रयास गर्नुस्।',
          onRetry: () => _open(_uid!),
          onSignOut: signOut,
        ),
      );
    }
    final store = _store;
    if (store == null) return const ShellApp(home: _Waiting(text: 'पसल खोल्दैछ…'));
    return BhunteApp(
      key: ValueKey(_uid),
      store: store,
      assistant: widget.assistant,
      scanner: widget.scanner,
      photoReader: widget.photoReader,
      billReader: widget.billReader,
      signOut: signOut,
    );
  }
}

/// Shown when the app was built for Firebase but Firebase is not configured.
class FirebaseSetupProblem extends StatelessWidget {
  const FirebaseSetupProblem({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => _Problem(
    title: 'Firebase सेटअप भएको छैन',
    detail: 'app/ मा `flutterfire configure` चलाउनुस्, वा BACKEND=firebase बिना चलाउनुस् (demo)।\n\n$error',
  );
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset('assets/brand/bhunte-logo.png', width: 96, height: 96),
          ),
          const SizedBox(height: 20),
          const CircularProgressIndicator(color: BColors.green),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(text, style: const TextStyle(fontSize: 18, color: BColors.inkSoft)),
          ],
        ],
      ),
    ),
  );
}

class _Problem extends StatelessWidget {
  const _Problem({required this.title, required this.detail, this.onRetry, this.onSignOut});

  final String title;
  final String detail;
  final VoidCallback? onRetry;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 64, color: BColors.warnInk),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: BColors.inkSoft),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              BigButton(label: 'फेरि प्रयास गर्नुस्', onPressed: onRetry),
            ],
            if (onSignOut != null) ...[
              const SizedBox(height: 10),
              BigButton(
                label: 'बाहिर निस्कनुस्',
                outlineColor: BColors.line,
                foreground: BColors.ink,
                height: 56,
                fontSize: 18,
                onPressed: onSignOut,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
