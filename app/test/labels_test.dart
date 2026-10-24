import 'dart:convert';
import 'dart:math';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:bhunte_ai/ai/demo_services.dart';
import 'package:bhunte_ai/app.dart';
import 'package:bhunte_ai/core/barcode.dart';
import 'package:bhunte_ai/core/keypad_input.dart';
import 'package:bhunte_ai/core/money.dart';
import 'package:bhunte_ai/core/qty.dart';
import 'package:bhunte_ai/data/demo_data.dart';
import 'package:bhunte_ai/firebase/firestore_backend.dart';
import 'package:bhunte_ai/labels/label_pdf.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 1×1 PNG, enough for the PDF builder.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

void main() {
  group('in-store codes', () {
    test('EAN-13 check digit matches the standard', () {
      expect(ean13CheckDigit('400638133393'), 1);
      expect(isValidEan13('4006381333931'), isTrue);
      expect(isValidEan13('4006381333932'), isFalse);
      expect(isInStoreCode('4006381333931'), isFalse, reason: 'a real product code');
    });

    test('generated codes are valid, in the 2xx range, and never reused', () {
      final first = generateInStoreEan13(taken: {}, random: Random(7));
      expect(isInStoreCode(first), isTrue);
      expect(first, startsWith('2'));
      // Same seed would give the same code; it must skip the taken one.
      final second = generateInStoreEan13(taken: {first}, random: Random(7));
      expect(second, isNot(first));
      expect(isInStoreCode(second), isTrue);
      expect(formatEan13('2012345678905'), '2 012345 678905');
    });

    test('store: own code gets a label kind, a scanned code does not', () {
      final s = demoStore();
      final code = s.newInStoreCode();
      expect(s.products.any((p) => p.barcode == code), isFalse);
      final own = s.addProduct(nameNe: 'जिरा', pricePaisa: rs(40), costPaisa: rs(30), unit: Unit.packet, barcode: code);
      expect(own.hasOwnCode, isTrue);
      expect(own.labelKind, LabelKind.barcode);
      final real = s.addProduct(
        nameNe: 'कोक',
        pricePaisa: rs(60),
        costPaisa: rs(50),
        unit: Unit.piece,
        barcode: '4006381333931',
      );
      expect(real.hasOwnCode, isFalse);
      expect(real.labelKind, isNull);
      s.setLabelKind(own.id, LabelKind.qr);
      expect(s.product(own.id).labelKind, LabelKind.qr);
    });
  });

  group('label sheet PDF', () {
    test('24 labels per A4 sheet', () {
      expect(sheetsFor(0), 0);
      expect(sheetsFor(1), 1);
      expect(sheetsFor(24), 1);
      expect(sheetsFor(25), 2);
    });

    test('builds a PDF', () async {
      final bytes = await buildLabelSheetPdf(labelPng: _png, copies: 30);
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    });
  });

  test('Firestore: label kind is saved with the product', () async {
    final db = FakeFirebaseFirestore();
    final (store, backend) = await openFirestoreShop(db: db, uid: 'u1');
    addTearDown(backend.close);
    final p = store.addProduct(
      nameNe: 'जिरा',
      pricePaisa: rs(40),
      costPaisa: rs(30),
      unit: Unit.packet,
      barcode: store.newInStoreCode(),
    );
    await pumpEventQueue();
    store.setLabelKind(p.id, LabelKind.qr);
    await pumpEventQueue();
    final doc = (await db.doc('shops/u1/products/${p.id}').get()).data()!;
    expect(doc['labelKind'], 'qr');
    expect(isInStoreCode(doc['barcode'] as String), isTrue);
  });

  testWidgets('new product without a barcode: make own QR, then the label screen opens', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = demoStore();
    await tester.pumpWidget(
      BhunteApp(
        store: store,
        assistant: DemoAssistantService(delay: Duration.zero),
        scanner: DemoBarcodeScanner(delay: Duration.zero),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('स्टक थप्नुस्'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('नयाँ सामान'));
    await tester.pumpAndSettle();

    final list = find
        .descendant(of: find.byKey(const ValueKey('new-product-list')), matching: find.byType(Scrollable))
        .first;
    await tester.enterText(find.byKey(const ValueKey('name-ne')), 'जिरा');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('field-price')), 120, scrollable: list);
    await tester.tap(find.byKey(const ValueKey('field-price')));
    await tester.pumpAndSettle();
    for (final d in '40'.split('')) {
      await tester.tap(find.byKey(ValueKey('key-$d')).last);
      await tester.pump();
    }
    await tester.tap(find.text('ठीक छ').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byKey(const ValueKey('make-own-code')), 200, scrollable: list);
    await tester.tap(find.byKey(const ValueKey('make-own-code')));
    await tester.pumpAndSettle();
    expect(find.text('पसलको आफ्नै कोड'), findsOneWidget);
    expect(find.byType(BarcodeWidget), findsOneWidget, reason: 'live preview');
    await tester.ensureVisible(find.text('QR').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('QR').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('सामान थप्नुस्'));
    await tester.pumpAndSettle();

    final p = store.products.firstWhere((x) => x.nameNe == 'जिरा');
    expect(p.hasOwnCode, isTrue);
    expect(p.labelKind, LabelKind.qr);
    expect(find.text('लेबल प्रिन्ट'), findsOneWidget);
    expect(find.text('24 वटा · 1 पाना A4'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('label-copies')));
    await tester.pumpAndSettle();
    for (final d in '30'.split('')) {
      await tester.tap(find.byKey(ValueKey('key-$d')).last);
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('key-${Keys.ok}')).last);
    await tester.pumpAndSettle();
    expect(find.text('30 वटा · 2 पाना A4'), findsOneWidget);

    // Switching to barcode here is remembered for reprints.
    await tester.tap(find.text('बारकोड').last);
    await tester.pumpAndSettle();
    expect(store.product(p.id).labelKind, LabelKind.barcode);
    await tester.pump(const Duration(seconds: 2));
  });
}
