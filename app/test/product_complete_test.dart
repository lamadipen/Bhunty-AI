import 'package:bhunte_ai/ai/assistant_service.dart';
import 'package:bhunte_ai/ai/demo_services.dart';
import 'package:bhunte_ai/app.dart';
import 'package:bhunte_ai/core/keypad_input.dart';
import 'package:bhunte_ai/core/money.dart';
import 'package:bhunte_ai/core/product_code.dart';
import 'package:bhunte_ai/core/qty.dart';
import 'package:bhunte_ai/data/demo_data.dart';
import 'package:bhunte_ai/data/shop_store.dart';
import 'package:bhunte_ai/firebase/firestore_backend.dart';
import 'package:bhunte_ai/firebase/firestore_mapping.dart';
import 'package:bhunte_ai/scanning/scanner_screen.dart';
import 'package:bhunte_ai/theme/theme.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FixedScanner implements BarcodeScanner {
  FixedScanner(this.code);
  String? code;

  @override
  Future<String?> scan(BuildContext context) async => code;
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<ShopStore> _app(WidgetTester tester, {BarcodeScanner? scanner, ShopStore? store}) async {
  _phone(tester);
  final s = store ?? demoStore();
  await tester.pumpWidget(
    BhunteApp(
      store: s,
      assistant: DemoAssistantService(delay: Duration.zero),
      scanner: scanner ?? DemoBarcodeScanner(delay: Duration.zero),
    ),
  );
  await tester.pumpAndSettle();
  return s;
}

Future<void> _keys(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.byKey(ValueKey('key-$d')).last);
    await tester.pump();
  }
}

Future<void> _ok(WidgetTester tester) async {
  final okKey = find.byKey(const ValueKey('key-${Keys.ok}'));
  await tester.tap(okKey.evaluate().isNotEmpty ? okKey.last : find.text('ठीक छ').last);
  await tester.pumpAndSettle();
}

/// Opens Stock → tap a product → ✎ (edit).
Future<void> _openEdit(WidgetTester tester, String productId) async {
  await tester.tap(find.text('स्टक थप्नुस्'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(ValueKey('tile-$productId')));
  await tester.tap(find.byKey(ValueKey('tile-$productId')));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('सामान मिलाउनुस्'));
  await tester.pumpAndSettle();
}

Finder get _formList =>
    find.descendant(of: find.byKey(const ValueKey('new-product-list')), matching: find.byType(Scrollable)).first;

void main() {
  group('which codes may be saved', () {
    test('retail codes, normalised so every scan of a packet matches', () {
      expect(checkProductCode('4006381333931').code, '4006381333931');
      expect(checkProductCode('036000291452').code, '0036000291452', reason: 'UPC-A stored as EAN-13');
      expect(checkProductCode('04006381333931').code, '4006381333931', reason: 'GTIN-14 indicator 0');
      expect(checkProductCode('96385074').code, '96385074', reason: 'EAN-8');
      expect(checkProductCode(' ab-123 ').code, 'AB-123', reason: 'distributor code');
    });

    test('mistyped and non-product codes are refused', () {
      expect(checkProductCode('4006381333932', typed: true).error, 'अङ्क मिलेन, एक पटक फेरि हेर्नुस्');
      expect(checkProductCode('https://example.com/p/1').error, isNotNull);
      expect(checkProductCode('00020101021126360011np.fonepay.com0123456789').error, isNotNull, reason: 'payment QR');
      expect(checkProductCode('WIFI:S:shop;T:WPA;P:secret;;').error, isNotNull);
      expect(checkProductCode('123').error, isNotNull);
      expect(checkProductCode('').error, isNotNull);
    });
  });

  group('store', () {
    test('a scanned code starting with 2 is not mistaken for our own', () {
      final s = demoStore();
      final p = s.addProduct(
        nameNe: 'मासु',
        pricePaisa: rs(700),
        costPaisa: rs(600),
        unit: Unit.kg,
        barcode: '2100001234560',
      );
      expect(p.hasOwnCode, isFalse);
      expect(p.labelKind, isNull);
    });

    test('edit: details change, stock does not, rules still apply', () {
      final s = demoStore();
      final egg = s.product('egg');
      final edited = s.updateProduct(
        'egg',
        nameNe: 'अण्डा (लोकल)',
        pricePaisa: rs(22),
        costPaisa: rs(17),
        unit: Unit.piece,
        barcode: '4006381333931',
      );
      expect(edited.pricePaisa, rs(22));
      expect(edited.stockMilli, egg.stockMilli);
      expect(edited.letter, 'अण');
      expect(s.productByBarcode('4006381333931')?.id, 'egg');
      // Unit is locked while there is stock.
      expect(
        () => s.updateProduct('egg', nameNe: 'अण्डा', pricePaisa: rs(22), costPaisa: rs(17), unit: Unit.kg),
        throwsArgumentError,
      );
      // Its own name is not a duplicate; another product's is.
      expect(s.validateProduct(excludeId: 'egg', nameNe: 'अण्डा (लोकल)', pricePaisa: 1, costPaisa: 0), isNull);
      expect(s.validateProduct(excludeId: 'egg', nameNe: 'चिनी', pricePaisa: 1, costPaisa: 0), isNotNull);
    });

    test('hide: gone from grids, code still known, can come back', () {
      final s = demoStore();
      s.setArchived('soap', true);
      expect(s.products.map((p) => p.id), isNot(contains('soap')));
      expect(s.archivedProducts.single.id, 'soap');
      expect(s.productByBarcode('demo-soap')?.archived, isTrue);
      expect(
        s.validateNewProduct(nameNe: 'नयाँ', pricePaisa: 100, costPaisa: 0, barcode: 'demo-soap'),
        'यो कोड लुकाइएको "साबुन" मा छ',
      );
      s.setArchived('soap', false);
      expect(s.products.map((p) => p.id), contains('soap'));
    });
  });

  group('Firestore', () {
    test('an edit never overwrites stock another device changed', () async {
      final db = FakeFirebaseFirestore();
      final (store, backend) = await openFirestoreShop(db: db, uid: 'u1');
      addTearDown(backend.close);
      // Another phone sells 5 eggs; this phone hasn't heard yet.
      await db.doc('shops/u1/products/egg').update({'stockMilli': 85 * milli});
      store.updateProduct('egg', nameNe: 'अण्डा', pricePaisa: rs(22), costPaisa: rs(16), unit: Unit.piece);
      await pumpEventQueue();
      final egg = (await db.doc('shops/u1/products/egg').get()).data()!;
      expect(egg['pricePaisa'], rs(22));
      expect(egg['stockMilli'], 85 * milli);
      store.setArchived('egg', true);
      await pumpEventQueue();
      expect((await db.doc('shops/u1/products/egg').get()).data()!['archived'], isTrue);
    });

    test('older product docs: own code inferred from labelKind', () {
      final p = productFromMap('x', {'name_ne': 'जिरा', 'barcode': '2564771936787', 'labelKind': 'qr'});
      expect(p.ownCode, isTrue);
      final q = productFromMap('y', {'name_ne': 'कोक', 'barcode': '4006381333931'});
      expect(q.ownCode, isFalse);
    });
  });

  group('scanner screen fallbacks', () {
    Future<String?> openScanner(WidgetTester tester, ScannerPreviewBuilder preview) async {
      _phone(tester);
      String? result = 'not closed';
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await Navigator.of(
                      context,
                    ).push<String>(MaterialPageRoute(builder: (_) => ScannerScreen(preview: preview)));
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('a payment QR is refused, then a real code closes with the clean value', (tester) async {
      late ValueChanged<String> emit;
      String? result;
      _phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => ScannerScreen(
                    preview: (c, onRaw, onError) {
                      emit = onRaw;
                      return const ColoredBox(color: Colors.black);
                    },
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      emit('00020101021126360011np.fonepay.com0123456789');
      await tester.pump();
      expect(find.textContaining('सामानको कोड होइन'), findsOneWidget);
      expect(find.byType(ScannerScreen), findsOneWidget, reason: 'keeps scanning');

      emit('036000291452'); // UPC-A
      await tester.pumpAndSettle();
      expect(find.byType(ScannerScreen), findsNothing);
      expect(result, '0036000291452');
    });

    testWidgets('no camera: the reason is shown and the number can be typed', (tester) async {
      await openScanner(tester, (c, onRaw, onError) => onError('यो उपकरणमा क्यामेरा चलेन। तल नम्बर लेख्नुस्।'));
      expect(find.text('यो उपकरणमा क्यामेरा चलेन। तल नम्बर लेख्नुस्।'), findsOneWidget);

      await tester.tap(find.text('नम्बर हातैले लेख्नुस्'));
      await tester.pumpAndSettle();
      await _keys(tester, '4006381333932'); // one digit wrong
      await _ok(tester);
      expect(find.text('अङ्क मिलेन, एक पटक फेरि हेर्नुस्'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('key-${Keys.backspace}')).last);
      await _keys(tester, '1');
      await _ok(tester);
      expect(find.byType(ScannerScreen), findsNothing, reason: 'closed with the typed code');
    });
  });

  group('screens', () {
    testWidgets('Sell: unknown code → add product → it is in the cart', (tester) async {
      final store = await _app(tester, scanner: FixedScanner('4006381333931'));
      await tester.tap(find.text('बेच्नुस्'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('स्क्यान'));
      await tester.pumpAndSettle();
      expect(find.text('यो सामान पसलमा छैन'), findsOneWidget);
      await tester.tap(find.text('नयाँ सामान थप्नुस्'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('name-ne')), 'कोक');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('field-price')));
      await tester.pumpAndSettle();
      await _keys(tester, '60');
      await _ok(tester);
      await tester.tap(find.text('सामान थप्नुस्'));
      await tester.pumpAndSettle();

      final coke = store.productByBarcode('4006381333931')!;
      expect(coke.nameNe, 'कोक');
      expect(tester.widget<Text>(find.byKey(const ValueKey('cart-total'))).data, 'रु 60');
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('Edit: change a price; unit is locked because there is stock', (tester) async {
      final store = await _app(tester);
      await _openEdit(tester, 'egg');
      expect(find.text('सामान मिलाउनुस्'), findsWidgets);
      expect(find.text('स्टक भएकोले एकाइ बदल्न मिल्दैन'), findsOneWidget);
      expect(find.text('केजी'), findsNothing, reason: 'only the current unit is offered');

      await tester.tap(find.byKey(const ValueKey('field-price')));
      await tester.pumpAndSettle();
      await _keys(tester, '22');
      await _ok(tester);
      await tester.tap(find.text('सुरक्षित गर्नुस्'));
      await tester.pumpAndSettle();

      expect(store.product('egg').pricePaisa, rs(22));
      expect(store.product('egg').stockMilli, 90 * milli);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('Edit: swap a product\'s code for the shop\'s own, then labels open', (tester) async {
      final store = await _app(tester);
      await _openEdit(tester, 'rice');
      await tester.scrollUntilVisible(find.text('demo-rice'), 200, scrollable: _formList);
      await tester.ensureVisible(find.byTooltip('बारकोड हटाउनुस्'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('बारकोड हटाउनुस्'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('make-own-code')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('make-own-code')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('सुरक्षित गर्नुस्'));
      await tester.pumpAndSettle();

      expect(store.product('rice').hasOwnCode, isTrue);
      expect(store.productByBarcode('demo-rice'), isNull);
      expect(find.text('लेबल प्रिन्ट'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('Edit an own-code product price → reprint prompt', (tester) async {
      final store = demoStore();
      final p = store.addProduct(
        nameNe: 'जिरा',
        pricePaisa: rs(40),
        costPaisa: rs(30),
        unit: Unit.packet,
        barcode: store.newInStoreCode(),
        ownCode: true,
        openingStockMilli: 5 * milli,
      );
      await _app(tester, store: store);
      await _openEdit(tester, p.id);
      await tester.tap(find.byKey(const ValueKey('field-price')));
      await tester.pumpAndSettle();
      await _keys(tester, '45');
      await _ok(tester);
      await tester.tap(find.text('सुरक्षित गर्नुस्'));
      await tester.pumpAndSettle();
      expect(find.text('नयाँ लेबल छाप्ने?'), findsOneWidget);
      await tester.tap(find.text('नयाँ लेबल छाप्नुस्'));
      await tester.pumpAndSettle();
      expect(find.text('लेबल प्रिन्ट'), findsOneWidget);
      expect(store.product(p.id).pricePaisa, rs(45));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('Hide a product; scanning its code on Sell offers to show it again', (tester) async {
      final store = await _app(tester, scanner: FixedScanner('demo-soap'));
      await _openEdit(tester, 'soap');
      await tester.scrollUntilVisible(find.byKey(const ValueKey('toggle-hidden')), 200, scrollable: _formList);
      await tester.tap(find.byKey(const ValueKey('toggle-hidden')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-yes')));
      await tester.pumpAndSettle();
      expect(store.product('soap').archived, isTrue);
      // Back on Stock (sheet still open over it): close the sheet.
      await tester.tap(find.byTooltip('बन्द गर्नुस्'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tile-soap')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('show-hidden')));
      expect(find.text('लुकाइएका सामान (1)'), findsOneWidget);

      // Sell: scan the hidden product's code.
      await tester.tap(find.byTooltip('पछाडि · Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('बेच्नुस्'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('स्क्यान'));
      await tester.pumpAndSettle();
      expect(find.text('साबुन लुकाइएको छ'), findsOneWidget);
      await tester.tap(find.text('फेरि देखाउनुस्'));
      await tester.pumpAndSettle();
      expect(store.product('soap').archived, isFalse);
      expect(tester.widget<Text>(find.byKey(const ValueKey('cart-total'))).data, 'रु 60');
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
