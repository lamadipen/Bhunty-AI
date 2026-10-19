import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// A sign-in problem, already worded for the shopkeeper.
class AuthFailure implements Exception {
  const AuthFailure(this.messageNe);
  final String messageNe;

  @override
  String toString() => 'AuthFailure($messageNe)';
}

/// What `sendCode` returns: either a code was sent, or Android read the SMS
/// itself and the user is already signed in.
class OtpRequest {
  const OtpRequest.sent(this.handle) : autoVerified = false;
  const OtpRequest.autoVerified() : handle = null, autoVerified = true;

  /// Opaque to the UI: a verification id (mobile) or a confirmation (web).
  final Object? handle;
  final bool autoVerified;
}

abstract interface class AuthService {
  /// The signed-in user's id, or null; emits on every sign-in and sign-out.
  Stream<String?> get userIds;

  /// Sends an SMS code to [phoneE164] (e.g. "+9779812345678").
  Future<OtpRequest> sendCode(String phoneE164);

  Future<void> confirmCode(OtpRequest request, String code);

  /// Signs in with no login screen. The account lives on this device only;
  /// when phone login is added, link it to the phone number (`linkWithCredential`)
  /// so the same uid — and the same shop — carries over.
  Future<void> signInAnonymously();

  Future<void> signOut();
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth);

  final FirebaseAuth _auth;

  @override
  Stream<String?> get userIds => _auth.authStateChanges().map((u) => u?.uid);

  @override
  Future<OtpRequest> sendCode(String phoneE164) async {
    try {
      if (kIsWeb) {
        // Uses an invisible reCAPTCHA that Firebase adds to the page.
        return OtpRequest.sent(await _auth.signInWithPhoneNumber(phoneE164));
      }
      final result = Completer<OtpRequest>();
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneE164,
        verificationCompleted: (credential) async {
          // Android auto-retrieval: sign in without the user typing the code.
          await _auth.signInWithCredential(credential);
          if (!result.isCompleted) result.complete(const OtpRequest.autoVerified());
        },
        verificationFailed: (e) {
          if (!result.isCompleted) result.completeError(_failure(e));
        },
        codeSent: (verificationId, _) {
          if (!result.isCompleted) result.complete(OtpRequest.sent(verificationId));
        },
        codeAutoRetrievalTimeout: (_) {},
      );
      return result.future;
    } on FirebaseAuthException catch (e) {
      throw _failure(e);
    }
  }

  @override
  Future<void> confirmCode(OtpRequest request, String code) async {
    try {
      switch (request.handle) {
        case final ConfirmationResult web:
          await web.confirm(code);
        case final String verificationId:
          await _auth.signInWithCredential(PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code));
        default:
          throw const AuthFailure('फेरि कोड पठाउनुस्');
      }
    } on FirebaseAuthException catch (e) {
      throw _failure(e);
    }
  }

  @override
  Future<void> signInAnonymously() async {
    try {
      await _auth.signInAnonymously();
    } on FirebaseAuthException catch (e) {
      throw _failure(e);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  static AuthFailure _failure(FirebaseAuthException e) {
    debugPrint('Bhunte: auth error ${e.code}: ${e.message}');
    return AuthFailure(switch (e.code) {
      'invalid-phone-number' => 'फोन नम्बर मिलेन',
      'invalid-verification-code' => 'कोड मिलेन, फेरि हेर्नुस्',
      'session-expired' || 'code-expired' => 'कोडको समय सकियो, फेरि पठाउनुस्',
      'too-many-requests' || 'quota-exceeded' => 'धेरै पटक प्रयास भयो, केही बेरपछि गर्नुस्',
      'network-request-failed' => 'इन्टरनेट छैन। जोडेर फेरि गर्नुस्',
      'operation-not-allowed' => 'Firebase मा यो लगइन तरिका खुलेको छैन (Authentication → Sign-in method)',
      _ => 'लगइन हुन सकेन, फेरि प्रयास गर्नुस्',
    });
  }
}
