import 'package:bhunte_ai/ai/assistant_service.dart';
import 'package:bhunte_ai/ai/demo_services.dart';
import 'package:bhunte_ai/app.dart';
import 'package:bhunte_ai/core/keypad_input.dart';
import 'package:bhunte_ai/core/money.dart';
import 'package:bhunte_ai/core/qty.dart';
import 'package:bhunte_ai/data/demo_data.dart';
import 'package:bhunte_ai/data/models.dart';
import 'package:bhunte_ai/data/shop_backend.dart';
import 'package:bhunte_ai/data/shop_store.dart';
import 'package:bhunte_ai/firebase/firestore_backend.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FixedScanner implements BarcodeScanner {
  FixedScanner(this.code);
  final String code;

  @override
  Future<String?> scan(BuildContext context) async => code;
}

Future<ShopStore> _pumpApp(WidgetTester tester, {BarcodeScanner? scanner, ShopStore? store}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
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

Future<void> _openStock(WidgetTester tester) async {
  await tester.tap(find.text('स्टक थप्नुस्'));
  await tester.pumpAndSettle();
}

Future<void> _tapKeys(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.byKey(ValueKey('key-$d')).last);
    await tester.pump();
  }
}

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(ValueKey(key))).data!;

void main() {
  group('helpers', () {
    test('packs and money', () {
      expect(packsToUnitsMilli(2 * milli, 30 * milli), 60 * milli);
      expect(packsToUnitsMilli(500, 24 * milli), 12 * milli); // half a carton of 24
      expect(unitCostFromPack(rs(900), 30 * milli), rs(30));
      expect(unitCostFromPack(rs(1000), 24 * milli), 4167); // रु 41.67, rounded
      expect(parseMoneyPaisa('25'), rs(25));
      expect(parseMoneyPaisa('22.5'), 2250);
      expect(parseMoneyPaisa('22.05'), 2205);
      expect(parseMoneyPaisa(''), 0);
    });
  });

  group('store', () {
    test('new product: validation catches the common mistakes', () {
      final s = demoStore();
      String? check({String name = 'नुन', int price = 2500, String? barcode, String? pack, int? size}) =>
          s.validateNewProduct(
            nameNe: name,
            pricePaisa: price,
            costPaisa: 2000,
            barcode: barcode,
            packName: pack,
            packSizeMilli: size,
          );
      expect(check(), isNull);
      expect(check(name: '  '), 'सामानको नाम लेख्नुस्');
      expect(check(name: 'चिनी'), 'यो नामको सामान पहिल्यै छ');
      expect(check(price: 0), 'बेच्ने मूल्य लेख्नुस्');
      expect(check(barcode: 'demo-egg'), 'यो बारकोड "अण्डा" मा छ');
      expect(check(pack: 'बोरा'), isNotNull);
      expect(check(pack: 'बोरा', size: 50 * milli), isNull);
    });

    test('new product with opening stock is explained by a stock entry', () {
      final changes = <ShopChange>[];
      final s = ShopStore(shopName: 'x', products: demoProducts(), customers: const [], backend: _Recorder(changes));
      final p = s.addProduct(
        nameNe: 'नुन',
        pricePaisa: rs(25),
        costPaisa: rs(20),
        unit: Unit.packet,
        openingStockMilli: 10 * milli,
        packName: 'बोरा',
        packSizeMilli: 50 * milli,
      );
      expect(s.product(p.id).stockMilli, 10 * milli);
      expect(p.hasPack, isTrue);
      expect(changes, hasLength(1), reason: 'one action, one batch');
      expect(changes.single.newProducts.single.stockMilli, 0);
      expect(changes.single.stockDeltas[p.id], 10 * milli);
      expect(changes.single.stockEntry!.totalPaisa, rs(200));
    });

    test('adding stock records the newest cost price', () {
      final s = demoStore();
      s.addStock([StockLine(productId: 'egg', qtyMilli: 30 * milli, costPaisa: rs(17))]);
      expect(s.product('egg').stockMilli, 120 * milli);
      expect(s.product('egg').costPaisa, rs(17));
    });
  });

  test('Firestore: new product, opening stock and cost update are saved', () async {
    final db = FakeFirebaseFirestore();
    final (store, backend) = await openFirestoreShop(db: db, uid: 'u1');
    addTearDown(backend.close);

    final p = store.addProduct(
      nameNe: 'नुन',
      pricePaisa: rs(25),
      costPaisa: rs(20),
      unit: Unit.packet,
      openingStockMilli: 10 * milli,
      packName: 'बोरा',
      packSizeMilli: 50 * milli,
    );
    await pumpEventQueue();
    store.addStock([StockLine(productId: 'waiwai', qtyMilli: 60 * milli, costPaisa: rs(19), totalCostPaisa: rs(1140))]);
    await pumpEventQueue();

    final salt = (await db.doc('shops/u1/products/${p.id}').get()).data()!;
    expect(salt['stockMilli'], 10 * milli);
    expect(salt['packName'], 'बोरा');
    expect(salt['packSizeMilli'], 50 * milli);
    expect(salt['sortOrder'], isA<int>());
    final ww = (await db.doc('shops/u1/products/waiwai').get()).data()!;
    expect(ww['stockMilli'], 66 * milli);
    expect(ww['costPaisa'], rs(19));
    expect(ww['packSizeMilli'], 30 * milli, reason: 'seeded with its carton');
    expect(store.products.last.nameNe, 'नुन', reason: 'new products go after the catalog');
  });

  group('screens', () {
    testWidgets('add 2 cartons of Wai Wai: 60 packets at the carton price', (tester) async {
      final store = await _pumpApp(tester);
      await _openStock(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('tile-waiwai')));
      await tester.tap(find.byKey(const ValueKey('tile-waiwai')));
      await tester.pumpAndSettle();

      expect(find.text('कार्टुनमा (×30)'), findsOneWidget);
      await _tapKeys(tester, '2');
      expect(_text(tester, 'stock-summary'), '+ 60 प्याकेट · जम्मा रु 1,080');
      await tester.tap(find.text('स्टकमा थप्नुस्'));
      await tester.pumpAndSettle();

      expect(store.product('waiwai').stockMilli, 66 * milli);
      expect(store.product('waiwai').costPaisa, rs(18));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('add loose units with a new cost', (tester) async {
      final store = await _pumpApp(tester);
      await _openStock(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('tile-egg')));
      await tester.tap(find.byKey(const ValueKey('tile-egg')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('stock-cost')));
      await tester.pumpAndSettle();
      await _tapKeys(tester, '17');
      await tester.tap(find.text('ठीक छ').last);
      await tester.pumpAndSettle();
      await _tapKeys(tester, '30');
      expect(_text(tester, 'stock-summary'), '+ 30 वटा · जम्मा रु 510');
      await tester.tap(find.text('स्टकमा थप्नुस्'));
      await tester.pumpAndSettle();

      expect(store.product('egg').stockMilli, 120 * milli);
      expect(store.product('egg').costPaisa, rs(17));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('scan an unknown barcode, fill the new product form, it joins the catalog', (tester) async {
      final store = await _pumpApp(tester, scanner: FixedScanner('8901234567890'));
      await _openStock(tester);
      await tester.ensureVisible(find.text('स्क्यान'));
      await tester.tap(find.text('स्क्यान'));
      await tester.pumpAndSettle();
      expect(find.text('नयाँ सामान'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('8901234567890'),
        200,
        scrollable: find
            .descendant(of: find.byKey(const ValueKey('new-product-list')), matching: find.byType(Scrollable))
            .first,
      );
      expect(find.text('8901234567890'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('name-ne')),
        -200,
        scrollable: find
            .descendant(of: find.byKey(const ValueKey('new-product-list')), matching: find.byType(Scrollable))
            .first,
      );

      // Saving without a name is caught.
      await tester.ensureVisible(find.text('सामान थप्नुस्'));
      await tester.tap(find.text('सामान थप्नुस्'));
      await tester.pump();
      expect(find.text('सामानको नाम लेख्नुस्'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('name-ne')), 'नुन');
      await tester.pumpAndSettle(); // focusing scrolls the field into view
      await tester.tap(find.text('प्याकेट').first);
      await tester.pump();
      Future<void> fill(String field, String digits) async {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey(field)),
          120,
          scrollable: find
              .descendant(of: find.byKey(const ValueKey('new-product-list')), matching: find.byType(Scrollable))
              .first,
        );
        await tester.tap(find.byKey(ValueKey(field)));
        await tester.pumpAndSettle();
        await _tapKeys(tester, digits);
        // Decimal pads confirm with a "ठीक छ" button, whole-number pads with the ✓ key.
        final okKey = find.byKey(const ValueKey('key-${Keys.ok}'));
        await tester.tap(okKey.evaluate().isNotEmpty ? okKey.last : find.text('ठीक छ').last);
        await tester.pumpAndSettle();
      }

      await fill('field-price', '25');
      await fill('field-cost', '20');
      await tester.scrollUntilVisible(
        find.text('नाफा: रु 5 प्रति प्याकेट'),
        120,
        scrollable: find
            .descendant(of: find.byKey(const ValueKey('new-product-list')), matching: find.byType(Scrollable))
            .first,
      );
      expect(find.text('नाफा: रु 5 प्रति प्याकेट'), findsOneWidget);
      await fill('field-opening', '10');
      await tester.ensureVisible(find.text('सामान थप्नुस्'));
      await tester.tap(find.text('सामान थप्नुस्'));
      await tester.pumpAndSettle();

      final salt = store.products.firstWhere((p) => p.nameNe == 'नुन');
      expect(salt.pricePaisa, rs(25));
      expect(salt.stockMilli, 10 * milli);
      expect(salt.barcode, '8901234567890');
      expect(find.text('हातैले थप्नुस्'), findsOneWidget, reason: 'back on the stock screen');
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('sell grid shows 7 items and "सबै" once the catalog is bigger', (tester) async {
      final store = demoStore();
      store.addProduct(nameNe: 'नुन', pricePaisa: rs(25), costPaisa: rs(20), unit: Unit.packet);
      await _pumpApp(tester, store: store);
      await tester.tap(find.text('बेच्नुस्'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tile-more')), findsOneWidget);
      expect(find.byKey(const ValueKey('tile-biscuit')), findsNothing, reason: '8th item moved behind "सबै"');
      await tester.tap(find.byKey(const ValueKey('tile-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tile-biscuit')).last);
      await tester.pumpAndSettle();
      expect(_text(tester, 'cart-total'), 'रु 30');
    });
  });
}

class _Recorder implements ShopBackend {
  _Recorder(this.changes);
  final List<ShopChange> changes;
  int _n = 0;

  @override
  String newId() => 'id-${++_n}';

  @override
  void commit(ShopChange change) => changes.add(change);
}
