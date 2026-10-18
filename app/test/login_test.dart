import 'dart:async';

import 'package:bhunte_ai/ai/demo_services.dart';
import 'package:bhunte_ai/app.dart';
import 'package:bhunte_ai/core/keypad_input.dart';
import 'package:bhunte_ai/core/phone.dart';
import 'package:bhunte_ai/firebase/auth_service.dart';
import 'package:bhunte_ai/firebase/firebase_root.dart';
import 'package:bhunte_ai/firebase/firestore_backend.dart';
import 'package:bhunte_ai/screens/login_screen.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Signs in when the code is 012345.
class FakeAuth implements AuthService {
  final _users = StreamController<String?>.broadcast();
  final sentTo = <String>[];
  String? _uid;

  @override
  Stream<String?> get userIds async* {
    yield _uid;
    yield* _users.stream;
  }

  @override
  Future<OtpRequest> sendCode(String phoneE164) async {
    sentTo.add(phoneE164);
    return const OtpRequest.sent('verification-1');
  }

  @override
  Future<void> confirmCode(OtpRequest request, String code) async {
    if (code != '012345') throw const AuthFailure('कोड मिलेन, फेरि हेर्नुस्');
    _uid = 'owner-1';
    _users.add(_uid);
  }

  @override
  Future<void> signOut() async {
    _uid = null;
    _users.add(null);
  }
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _type(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.byKey(ValueKey('key-$d')));
    await tester.pump();
  }
}

String _entry(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('login-entry'))).data!;

void main() {
  test('Nepal mobile numbers', () {
    expect(isNepalMobile('9812345678'), isTrue);
    expect(isNepalMobile('9712345678'), isTrue);
    expect(isNepalMobile('981234567'), isFalse);
    expect(isNepalMobile('0812345678'), isFalse);
    expect(toE164Nepal('9812345678'), '+9779812345678');
    expect(formatNepalMobile('9812345678'), '98123 45678');
  });

  test('codes keep their leading zero', () {
    expect(applyKey('0', '1', leadingZeros: true), '01');
    expect(applyKey('0', '1'), '1');
  });

  testWidgets('login: bad number is caught before any SMS is sent', (tester) async {
    _phoneSize(tester);
    final auth = FakeAuth();
    await tester.pumpWidget(ShellApp(home: LoginScreen(auth: auth)));
    await _type(tester, '12345');
    await tester.tap(find.text('कोड पठाउनुस्'));
    await tester.pump();
    expect(find.textContaining('१० अङ्कको नम्बर'), findsOneWidget);
    expect(auth.sentTo, isEmpty);
  });

  testWidgets('sign in, shop opens from Firestore, sign out returns to login', (tester) async {
    _phoneSize(tester);
    final auth = FakeAuth();
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(
      FirebaseRoot(
        auth: auth,
        openShop: (uid) => openFirestoreShop(db: db, uid: uid),
        assistant: DemoAssistantService(delay: Duration.zero),
        scanner: DemoBarcodeScanner(delay: Duration.zero),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('तपाईंको मोबाइल नम्बर'), findsOneWidget);

    await _type(tester, '9812345678');
    expect(_entry(tester), '98123 45678');
    await tester.tap(find.text('कोड पठाउनुस्'));
    await tester.pumpAndSettle();
    expect(auth.sentTo, ['+9779812345678']);
    expect(find.text('SMS मा आएको कोड लेख्नुस्'), findsOneWidget);

    await _type(tester, '999999');
    await tester.tap(find.text('लगइन गर्नुस्'));
    await tester.pumpAndSettle();
    expect(find.text('कोड मिलेन, फेरि हेर्नुस्'), findsOneWidget);

    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const ValueKey('key-${Keys.backspace}')));
    }
    await _type(tester, '012345');
    await tester.tap(find.text('लगइन गर्नुस्'));
    // Firestore work happens outside the fake clock.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.text('मेरो पसल'), findsOneWidget); // new shop, home screen
    expect((await db.doc('shops/owner-1').get()).exists, isTrue);

    await tester.tap(find.byTooltip('पसल · Shop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('बाहिर निस्कनुस् · Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('तपाईंको मोबाइल नम्बर'), findsOneWidget);
  });
}
