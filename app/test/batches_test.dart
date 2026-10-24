// Scenarios from docs/product-addition.md, by ID. Keep the two in step.
import 'package:bhunte_ai/ai/demo_services.dart';
import 'package:bhunte_ai/app.dart';
import 'package:bhunte_ai/core/keypad_input.dart';
import 'package:bhunte_ai/core/money.dart';
import 'package:bhunte_ai/core/qty.dart';
import 'package:bhunte_ai/data/models.dart';
import 'package:bhunte_ai/data/shop_backend.dart';
import 'package:bhunte_ai/data/shop_store.dart';
import 'package:bhunte_ai/firebase/firestore_backend.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The common start for the S-scenarios: वाइवाइ stock 10, cost ₹10, price ₹15,
/// pack कार्टुन × 30, one earlier batch (10 @ ₹10, price ₹15).
ShopStore _waiwaiShop({DateTime Function()? clock}) {
  final s = ShopStore(shopName: 'test', products: const [], customers: const [], clock: clock);
  s.addProduct(
    nameNe: 'वाइवाइ',
    pricePaisa: rs(15),
    costPaisa: rs(10),
    unit: Unit.packet,
    openingStockMilli: 10 * milli,
    packName: 'कार्टुन',
    packSizeMilli: 30 * milli,
  );
  s.addProduct(nameNe: 'अण्डा', pricePaisa: rs(20), costPaisa: rs(16), unit: Unit.piece, openingStockMilli: 90 * milli);
  return s;
}

String _id(ShopStore s, String name) => s.products.firstWhere((p) => p.nameNe == name).id;

void main() {
  group('A — creating products', () {
    test('A-1 barcode + opening stock: product, opening delivery, batch, initial price', () {
      final s = ShopStore(shopName: 't', products: const [], customers: const []);
      final p = s.addProduct(
        nameNe: 'कोक 250ml',
        pricePaisa: rs(60),
        costPaisa: rs(50),
        unit: Unit.piece,
        openingStockMilli: 24 * milli,
        barcode: '4006381333931',
      );
      expect(p.pricePaisa, rs(60));
      expect(p.costPaisa, rs(50));
      expect(p.stockMilli, 24 * milli);
      expect(p.ownCode, isFalse);
      final d = s.deliveries.single;
      expect((d.source, d.totalCostPaisa, d.batchCount), (StockSource.opening, rs(1200), 1));
      final b = s.batchesFor(p.id).single;
      expect((b.qtyMilli, b.unitCostPaisa, b.totalCostPaisa, b.salePricePaisa), (24 * milli, rs(50), rs(1200), rs(60)));
      final pc = s.priceHistory(p.id).single;
      expect((pc.reason, pc.oldPricePaisa, pc.newPricePaisa, pc.batchId), (PriceReason.initial, null, rs(60), b.id));
      expect(s.productByBarcode('4006381333931')?.id, p.id);
    });

    test('A-3 no stock: no delivery or batch, but an initial price', () {
      final s = ShopStore(shopName: 't', products: const [], customers: const []);
      final p = s.addProduct(nameNe: 'मह 500g', pricePaisa: rs(450), costPaisa: rs(400), unit: Unit.piece);
      expect(p.stockMilli, 0);
      expect(s.deliveries, isEmpty);
      expect(s.batchesFor(p.id), isEmpty);
      expect(s.priceHistory(p.id).single.newPricePaisa, rs(450));
    });

    test('A-4 opening stock in cartons', () {
      final s = ShopStore(shopName: 't', products: const [], customers: const []);
      final p = s.addProduct(
        nameNe: 'वाइवाइ',
        pricePaisa: rs(25),
        costPaisa: unitCostFromPack(rs(540), 30 * milli),
        unit: Unit.packet,
        openingStockMilli: packsToUnitsMilli(2 * milli, 30 * milli),
        openingPacksMilli: 2 * milli,
        openingTotalCostPaisa: lineTotal(rs(540), 2 * milli),
        packName: 'कार्टुन',
        packSizeMilli: 30 * milli,
      );
      expect(p.stockMilli, 60 * milli);
      final b = s.batchesFor(p.id).single;
      expect(b.enteredAsPack, isTrue);
      expect((b.packName, b.packSizeMilli, b.packsMilli), ('कार्टुन', 30 * milli, 2 * milli));
      expect((b.unitCostPaisa, b.totalCostPaisa, b.salePricePaisa), (rs(18), rs(1080), rs(25)));
    });

    test('A-5 loose goods by the kg', () {
      final s = ShopStore(shopName: 't', products: const [], customers: const []);
      final p = s.addProduct(
        nameNe: 'चिनी',
        pricePaisa: rs(120),
        costPaisa: rs(105),
        unit: Unit.kg,
        openingStockMilli: 25 * milli,
      );
      expect(s.batchesFor(p.id).single.totalCostPaisa, rs(2625));
      final sale = s.recordSale(cart: {p.id: 500}, method: PaymentMethod.cash);
      expect(sale.totalPaisa, rs(60));
      expect(s.product(p.id).stockMilli, 24500);
    });

    test('A-6 a pack cost that does not divide evenly keeps the exact bill total', () {
      final s = _waiwaiShop();
      final id = _id(s, 'वाइवाइ');
      s.addStock([
        StockLine(
          productId: id,
          qtyMilli: 24 * milli,
          costPaisa: unitCostFromPack(rs(1000), 24 * milli),
          totalCostPaisa: rs(1000),
          packsMilli: milli,
        ),
      ]);
      final b = s.batchesFor(id).last;
      expect(b.unitCostPaisa, 4167);
      expect(b.totalCostPaisa, rs(1000));
    });
  });

  group('S — receiving stock', () {
    test('S-1 same cost, same price: batch only, no price change', () {
      final s = _waiwaiShop();
      final id = _id(s, 'वाइवाइ');
      s.addStock([StockLine(productId: id, qtyMilli: 20 * milli, costPaisa: rs(10), salePricePaisa: rs(15))]);
      expect(s.product(id).stockMilli, 30 * milli);
      expect(s.batchesFor(id).last.salePricePaisa, rs(15));
      expect(s.priceHistory(id).map((c) => c.reason), [PriceReason.initial]);
    });

    test('S-2 cost up, price up: new batch, price change, all stock sells at ₹18', () {
      final s = _waiwaiShop();
      final id = _id(s, 'वाइवाइ');
      final earlier = s.recordSale(cart: {id: milli}, method: PaymentMethod.cash);
      s.addStock([StockLine(productId: id, qtyMilli: 10 * milli, costPaisa: rs(13), salePricePaisa: rs(18))]);

      final p = s.product(id);
      expect((p.stockMilli, p.costPaisa, p.pricePaisa), (19 * milli, rs(13), rs(18)));
      final batches = s.batchesFor(id);
      expect(batches.map((b) => (b.unitCostPaisa, b.salePricePaisa)), [(rs(10), rs(15)), (rs(13), rs(18))]);
      expect(batches.last.totalCostPaisa, rs(130));
      final pc = s.priceHistory(id).last;
      expect(
        (pc.reason, pc.oldPricePaisa, pc.newPricePaisa, pc.batchId),
        (PriceReason.stock, rs(15), rs(18), batches.last.id),
      );
      expect(s.recordSale(cart: {id: 3 * milli}, method: PaymentMethod.cash).totalPaisa, rs(54));
      expect(earlier.lines.single.pricePaisa, rs(15), reason: 'past sales keep their price');
    });

    test('S-3 cost up, price kept: no price change', () {
      final s = _waiwaiShop();
      final id = _id(s, 'वाइवाइ');
      s.addStock([StockLine(productId: id, qtyMilli: 10 * milli, costPaisa: rs(13))]);
      expect(s.product(id).pricePaisa, rs(15));
      expect(s.product(id).costPaisa, rs(13));
      expect(s.batchesFor(id).last.salePricePaisa, rs(15));
      expect(s.priceHistory(id), hasLength(1));
    });

    test('S-4 cost down, price down', () {
      final s = _waiwaiShop();
      final id = _id(s, 'वाइवाइ');
      s.addStock([StockLine(productId: id, qtyMilli: 10 * milli, costPaisa: rs(9), salePricePaisa: rs(14))]);
      expect(s.priceHistory(id).last.oldPricePaisa, rs(15));
      expect(s.product(id).pricePaisa, rs(14));
    });

    test('S-5 cartons in, priced per packet', () {
      final s = _waiwaiShop();
      final id = _id(s, 'वाइवाइ');
      s.addStock([
        StockLine(
          productId: id,
          qtyMilli: 60 * milli,
          costPaisa: rs(13),
          totalCostPaisa: rs(780),
          packsMilli: 2 * milli,
          salePricePaisa: rs(18),
        ),
      ]);
      final b = s.batchesFor(id).last;
      expect((b.enteredAsPack, b.packsMilli, b.unitCostPaisa, b.totalCostPaisa), (true, 2 * milli, rs(13), rs(780)));
      expect(s.product(id).pricePaisa, rs(18));
    });

    test('S-8 stock that had gone negative', () {
      final s = _waiwaiShop();
      final id = _id(s, 'वाइवाइ');
      s.recordSale(cart: {id: 13 * milli}, method: PaymentMethod.cash);
      expect(s.product(id).stockMilli, -3 * milli);
      s.addStock([StockLine(productId: id, qtyMilli: 10 * milli, costPaisa: rs(10))]);
      expect(s.product(id).stockMilli, 7 * milli);
      expect(s.batchesFor(id).last.qtyMilli, 10 * milli);
    });

    test('S-9 supplier and bill number are optional', () {
      final s = _waiwaiShop();
      final id = _id(s, 'वाइवाइ');
      final withInfo = s.addStock(
        [StockLine(productId: id, qtyMilli: 10 * milli, costPaisa: rs(13))],
        supplierName: 'राम ट्रेडर्स',
        supplierPhone: '9812345678',
        billNo: '1452',
      );
      expect((withInfo.supplierName, withInfo.supplierPhone, withInfo.billNo), ('राम ट्रेडर्स', '9812345678', '1452'));
      final without = s.addStock([StockLine(productId: id, qtyMilli: milli, costPaisa: rs(13))], supplierName: '  ');
      expect((without.supplierName, without.supplierPhone, without.billNo), (null, null, null));
    });

    test('S-10 one bill with two products: 1 delivery, 2 batches, 1 price change', () {
      final s = _waiwaiShop();
      final ww = _id(s, 'वाइवाइ'), egg = _id(s, 'अण्डा');
      final d = s.addStock([
        StockLine(productId: ww, qtyMilli: 10 * milli, costPaisa: rs(13), salePricePaisa: rs(18)),
        StockLine(productId: egg, qtyMilli: 30 * milli, costPaisa: rs(16), salePricePaisa: rs(20)),
      ]);
      expect((d.batchCount, d.totalCostPaisa), (2, rs(130 + 480)));
      expect(s.batchesFor(ww).last.deliveryId, d.id);
      expect(s.batchesFor(egg).last.deliveryId, d.id);
      expect(s.priceHistory(ww).last.reason, PriceReason.stock);
      expect(s.priceHistory(egg).map((c) => c.reason), [PriceReason.initial]);
    });

    test('S-11 no quantity is refused; no cost is saved and flagged', () {
      final s = _waiwaiShop();
      final id = _id(s, 'वाइवाइ');
      expect(s.validateStock([StockLine(productId: id, qtyMilli: 0, costPaisa: rs(10))]), isNotNull);
      s.addStock([StockLine(productId: id, qtyMilli: 5 * milli, costPaisa: 0)]);
      expect(s.batchesFor(id).last.costMissing, isTrue);
    });
  });

  group('P — price changes', () {
    test('P-1 manual change: price history, no batch, stock unchanged', () {
      final s = _waiwaiShop();
      final id = _id(s, 'वाइवाइ');
      s.updateProduct(id, nameNe: 'वाइवाइ', pricePaisa: rs(17), costPaisa: rs(10), unit: Unit.packet);
      final pc = s.priceHistory(id).last;
      expect((pc.reason, pc.oldPricePaisa, pc.newPricePaisa), (PriceReason.manual, rs(15), rs(17)));
      expect(s.batchesFor(id), hasLength(1));
      expect(s.product(id).stockMilli, 10 * milli);
    });

    test('P-2 the latest by time wins, whichever kind', () {
      var t = DateTime.utc(2026, 10, 19, 4, 15); // 10:00 NPT
      final s = _waiwaiShop(clock: () => t);
      final id = _id(s, 'वाइवाइ');
      s.addStock([StockLine(productId: id, qtyMilli: 10 * milli, costPaisa: rs(13), salePricePaisa: rs(18))]);
      expect(s.product(id).pricePaisa, rs(18));
      t = t.add(const Duration(hours: 1));
      s.updateProduct(id, nameNe: 'वाइवाइ', pricePaisa: rs(17), costPaisa: rs(13), unit: Unit.packet);
      expect(s.product(id).pricePaisa, rs(17));
      expect(s.product(id).priceSetAt, t);
      t = t.add(const Duration(hours: 1));
      s.addStock([StockLine(productId: id, qtyMilli: 5 * milli, costPaisa: rs(13), salePricePaisa: rs(17))]);
      expect(s.product(id).pricePaisa, rs(17));
      expect(s.priceHistory(id).map((c) => c.reason), [PriceReason.initial, PriceReason.stock, PriceReason.manual]);
    });

    test('P-3 saving the same price writes no price change', () {
      final s = _waiwaiShop();
      final id = _id(s, 'वाइवाइ');
      s.updateProduct(
        id,
        nameNe: 'वाइवाइ',
        pricePaisa: rs(15),
        costPaisa: rs(10),
        unit: Unit.packet,
        lowStockAtMilli: 5,
      );
      expect(s.priceHistory(id), hasLength(1));
    });
  });

  test('E-1 batches keep the name the product had at the time', () {
    final s = _waiwaiShop();
    final id = _id(s, 'वाइवाइ');
    s.updateProduct(id, nameNe: 'वाइवाइ चाउचाउ', pricePaisa: rs(15), costPaisa: rs(10), unit: Unit.packet);
    s.addStock([StockLine(productId: id, qtyMilli: milli, costPaisa: rs(10))]);
    expect(s.batchesFor(id).map((b) => b.productName), ['वाइवाइ', 'वाइवाइ चाउचाउ']);
  });

  group('Firestore', () {
    test('S-2 writes a delivery, a batch and a price change in one go; product price moves', () async {
      final db = FakeFirebaseFirestore();
      final (store, backend) = await openFirestoreShop(db: db, uid: 'u1');
      addTearDown(backend.close);
      final d = store.addStock(
        [StockLine(productId: 'waiwai', qtyMilli: 10 * milli, costPaisa: rs(13), salePricePaisa: rs(30))],
        supplierName: 'राम ट्रेडर्स',
        billNo: '1452',
      );
      await pumpEventQueue();

      final delivery = (await db.doc('shops/u1/deliveries/${d.id}').get()).data()!;
      expect((delivery['source'], delivery['totalCostPaisa'], delivery['billNo']), ('manual', rs(130), '1452'));
      final batch = (await db.collection('shops/u1/batches').get()).docs.single.data();
      expect((batch['productId'], batch['salePricePaisa'], batch['enteredAs']), ('waiwai', rs(30), 'unit'));
      final pc = (await db.collection('shops/u1/priceChanges').get()).docs.single.data();
      expect((pc['reason'], pc['oldPricePaisa'], pc['newPricePaisa']), ('stock', rs(25), rs(30)));
      final ww = (await db.doc('shops/u1/products/waiwai').get()).data()!;
      expect((ww['pricePaisa'], ww['costPaisa'], ww['stockMilli']), (rs(30), rs(13), 16 * milli));
      expect(ww['priceSetAt'], isNotNull);
    });

    test('A-1 new product writes product, opening delivery, batch and initial price', () async {
      final db = FakeFirebaseFirestore();
      final (store, backend) = await openFirestoreShop(db: db, uid: 'u1');
      addTearDown(backend.close);
      final p = store.addProduct(
        nameNe: 'कोक',
        pricePaisa: rs(60),
        costPaisa: rs(50),
        unit: Unit.piece,
        openingStockMilli: 24 * milli,
      );
      await pumpEventQueue();
      expect((await db.doc('shops/u1/products/${p.id}').get()).data()!['stockMilli'], 24 * milli);
      expect((await db.collection('shops/u1/deliveries').get()).docs.single['source'], 'opening');
      expect((await db.collection('shops/u1/priceChanges').get()).docs.single['reason'], 'initial');
    });
  });

  group('screens', () {
    Future<ShopStore> app(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = _waiwaiShop();
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
      return store;
    }

    Future<void> keys(WidgetTester tester, String digits) async {
      for (final d in digits.split('')) {
        await tester.tap(find.byKey(ValueKey('key-$d')).last);
        await tester.pump();
      }
    }

    testWidgets('S-2 on the add-stock sheet: price pre-filled, changed to ₹18', (tester) async {
      final store = await app(tester);
      final id = _id(store, 'वाइवाइ');
      await tester.ensureVisible(find.byKey(ValueKey('tile-$id')));
      await tester.tap(find.byKey(ValueKey('tile-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('प्याकेटमा'));
      await tester.pumpAndSettle();
      expect(find.text('रु 15'), findsWidgets, reason: 'current price pre-filled');

      await tester.tap(find.byKey(const ValueKey('stock-cost')));
      await tester.pumpAndSettle();
      await keys(tester, '13');
      await tester.tap(find.text('ठीक छ').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('stock-price')));
      await tester.pumpAndSettle();
      await keys(tester, '18');
      await tester.tap(find.text('ठीक छ').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('price-change-note')), findsOneWidget);
      await keys(tester, '10');
      await tester.ensureVisible(find.text('स्टकमा थप्नुस्'));
      await tester.tap(find.text('स्टकमा थप्नुस्'));
      await tester.pumpAndSettle();

      final p = store.product(id);
      expect((p.stockMilli, p.costPaisa, p.pricePaisa), (20 * milli, rs(13), rs(18)));
      expect(store.priceHistory(id).last.reason, PriceReason.stock);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('A-4 new product form: opening stock and cost in cartons', (tester) async {
      final store = await app(tester);
      await tester.tap(find.text('नयाँ सामान'));
      await tester.pumpAndSettle();
      final list = find
          .descendant(of: find.byKey(const ValueKey('new-product-list')), matching: find.byType(Scrollable))
          .first;
      Future<void> pad(String key, String digits) async {
        // Back to the top, then down to the field (fields above may not be built).
        await tester.drag(list, const Offset(0, 3000));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.byKey(ValueKey(key)), 120, scrollable: list);
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        await keys(tester, digits);
        final ok = find.byKey(const ValueKey('key-${Keys.ok}'));
        await tester.tap(ok.evaluate().isNotEmpty ? ok.last : find.text('ठीक छ').last);
        await tester.pumpAndSettle();
      }

      await tester.enterText(find.byKey(const ValueKey('name-ne')), 'रारा');
      await tester.pumpAndSettle();
      await tester.tap(find.text('प्याकेट').first);
      await tester.pumpAndSettle();
      await pad('field-price', '25');
      await tester.ensureVisible(find.text('कार्टुन').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('कार्टुन').first);
      await tester.pumpAndSettle();
      await pad('field-pack', '30');
      await tester.ensureVisible(find.text('कार्टुनमा'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('कार्टुनमा'));
      await tester.pumpAndSettle();
      await pad('field-cost', '540');
      await pad('field-opening', '2');
      await tester.tap(find.text('सामान थप्नुस्'));
      await tester.pumpAndSettle();

      final p = store.products.firstWhere((x) => x.nameNe == 'रारा');
      expect((p.stockMilli, p.costPaisa, p.pricePaisa), (60 * milli, rs(18), rs(25)));
      final b = store.batchesFor(p.id).single;
      expect((b.packsMilli, b.totalCostPaisa), (2 * milli, rs(1080)));
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
