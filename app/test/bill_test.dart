// Manual bill and the shared bill logic (docs/stock-from-bill.md: BR*, MB-*, and
// the money parts of BL-*). Bill-photo screens are in bill_photo_test.dart.
import 'package:bhunte_ai/ai/assistant_service.dart';
import 'package:bhunte_ai/ai/demo_services.dart';
import 'package:bhunte_ai/app.dart';
import 'package:bhunte_ai/core/keypad_input.dart';
import 'package:bhunte_ai/core/money.dart';
import 'package:bhunte_ai/core/qty.dart';
import 'package:bhunte_ai/data/bill.dart';
import 'package:bhunte_ai/data/demo_data.dart';
import 'package:bhunte_ai/data/shop_backend.dart';
import 'package:bhunte_ai/data/shop_store.dart';
import 'package:bhunte_ai/firebase/firestore_backend.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Recorder implements ShopBackend {
  final List<ShopChange> changes = [];
  int _n = 0;

  @override
  String newId() => 'id-${++_n}';

  @override
  void commit(ShopChange change) => changes.add(change);
}

class FixedScanner implements BarcodeScanner {
  FixedScanner(this.code);
  final String code;

  @override
  Future<String?> scan(BuildContext context) async => code;
}

/// A ticked row as the bill screen makes it.
BillRow _row(String id, {int qty = 0, int? rate, int? amount, bool packs = false, int? packSize, String? text}) =>
    BillRow(
      productId: id,
      text: text,
      qtyMilli: qty,
      inPacks: packs,
      packSizeMilli: packSize,
      ratePaisa: rate,
      amountPaisa: amount,
      ticked: true,
    );

void main() {
  group('bill arithmetic', () {
    test('BR3/BL-4: packs, unit cost from the exact amount', () {
      final r = _row('waiwai', qty: 2 * milli, rate: rs(390), amount: rs(780), packs: true, packSize: 30 * milli);
      expect(r.unitsMilli, 60 * milli);
      expect(r.totalPaisa, rs(780));
      expect(r.unitCostPaisa, rs(13));
      expect(r.amountMismatch, isFalse);
    });

    test('BL-8: free units add stock, not cost', () {
      final r = _row('biscuit', qty: 12 * milli, rate: rs(22), amount: rs(264))..freeMilli = milli;
      expect(r.unitsMilli, 13 * milli);
      expect(r.totalPaisa, rs(264));
      expect(r.unitCostPaisa, 2031);
    });

    test('BR4/BL-2/BL-22: amount checked against qty × rate; computed when missing', () {
      expect(_row('soap', qty: 24 * milli, rate: rs(45), amount: rs(108)).amountMismatch, isTrue);
      expect(
        _row('soap', qty: 3 * milli, rate: 3333, amount: rs(100)).amountMismatch,
        isFalse,
        reason: 'रु 1 rounding',
      );
      final noAmount = _row('soap', qty: 10 * milli, rate: rs(18));
      expect(noAmount.totalPaisa, rs(180));
      expect(
        BillRow(productId: 'soap', qtyMilli: 24 * milli, ratePaisa: rs(45), amountPaisa: rs(108)).canSave,
        isFalse,
      );
    });

    test('BR5/BL-3: bill total compared with lines − discount + VAT', () {
      final bill = BillDraft(
        rows: [_row('soap', qty: 10 * milli, rate: rs(100))],
        header: const BillHeader(totalPaisa: 110000),
      );
      expect(bill.totalDifferencePaisa, rs(100));
      bill.header = const BillHeader(totalPaisa: 100050);
      expect(bill.totalDifferencePaisa, isNull, reason: 'within रु 1');
    });

    test('BL-14/Q1: VAT and discount spread into the batches; all ticked → exactly the bill', () {
      final bill = BillDraft(
        rows: [
          _row('soap', qty: 30 * milli, rate: rs(100)), // 3,000
          _row('egg', qty: 70 * milli, rate: rs(100)), // 7,000
        ],
        header: BillHeader(discountPaisa: rs(200), vatPaisa: rs(1274), totalPaisa: rs(11074)),
      );
      final totals = bill.batchTotals();
      expect(totals, [rs(3000) + 32220, rs(11074) - rs(3000) - 32220]);
      expect(totals.reduce((a, b) => a + b), rs(11074));
      expect(bill.totalDifferencePaisa, isNull);
      bill.rows.first.ticked = false;
      expect(bill.batchTotals(), [rs(7000) + 75180], reason: 'its share only');
    });

    test('BR9: bill text normalised for remembering', () {
      expect(normaliseBillText('  WAI-WAI  Chk. 70G '), 'wai wai chk 70g');
      expect(normaliseBillText('चिनी (१ केजी)'), 'चिनी १ केजी');
    });
  });

  group('store', () {
    ShopStore store(_Recorder rec) =>
        ShopStore(shopName: 'x', products: demoProducts(), customers: const [], backend: rec);

    test('MB-1/BR2: one delivery, a batch per ticked row, one write', () {
      final rec = _Recorder();
      final s = store(rec);
      final bill = BillDraft(
        rows: [
          _row('waiwai', qty: 2 * milli, rate: rs(390), amount: rs(780), packs: true, packSize: 30 * milli),
          _row('egg', qty: 90 * milli, rate: rs(16)),
          _row('soap', qty: 24 * milli, rate: rs(45))..salePricePaisa = rs(65),
          _row('milk', qty: 5 * milli, rate: rs(48))..ticked = false,
        ],
        header: const BillHeader(supplierName: 'राम ट्रेडर्स', billNo: '1452'),
      );
      final d = s.receiveBill(bill);

      expect(rec.changes, hasLength(1));
      final c = rec.changes.single;
      expect(d.source, StockSource.manual);
      expect(d.batchCount, 3);
      expect(d.totalCostPaisa, rs(3300));
      expect(d.supplierName, 'राम ट्रेडर्स');
      expect(c.batches.first.packsMilli, 2 * milli);
      expect(c.batches.first.unitCostPaisa, rs(13));
      expect(c.stockDeltas, {'waiwai': 60 * milli, 'egg': 90 * milli, 'soap': 24 * milli});
      expect(c.priceChanges.single.newPricePaisa, rs(65), reason: 'MB-5');
      expect(c.billAliases, isEmpty, reason: 'manual rows have no bill text');
      expect(s.product('milk').stockMilli, 20 * milli, reason: 'unticked: nothing');
    });

    test('BL-5/BR6: a bill pack for a product with none, kept on the product in the same write', () {
      final rec = _Recorder();
      final s = store(rec);
      final row = BillRow(
        productId: 'soap',
        text: 'Soap 1 crate',
        qtyMilli: milli,
        inPacks: true,
        packWord: 'crate',
        packSizeMilli: 24 * milli,
        amountPaisa: rs(1080),
        ticked: true,
      );
      s.receiveBill(BillDraft(rows: [row], fromPhoto: true));
      final c = rec.changes.single;
      expect(c.delivery!.source, StockSource.billPhoto);
      expect(c.batches.single.qtyMilli, 24 * milli);
      expect(c.batches.single.packName, 'crate');
      expect(c.batches.single.unitCostPaisa, rs(45));
      expect(c.batches.single.billLineText, 'Soap 1 crate');
      expect(c.updatedProducts.single.packSizeMilli, 24 * milli);
      expect(s.product('soap').packName, 'crate');
      expect(c.billAliases, {'soap 1 crate': 'soap'});
      expect(s.productIdForBillText('SOAP  1 Crate!'), 'soap');
    });

    test('BL-15: same product on two lines stays two batches; the last cost wins', () {
      final rec = _Recorder();
      final s = store(rec);
      s.receiveBill(
        BillDraft(
          rows: [
            _row('waiwai', qty: milli, amount: rs(390), packs: true, packSize: 30 * milli),
            _row('waiwai', qty: 10 * milli, rate: rs(14)),
          ],
        ),
      );
      expect(rec.changes.single.batches, hasLength(2));
      expect(s.product('waiwai').stockMilli, 46 * milli);
      expect(s.product('waiwai').costPaisa, rs(14));
    });

    test('Firestore: delivery fields, batch text and remembered names saved and read back', () async {
      final db = FakeFirebaseFirestore();
      final (s, backend) = await openFirestoreShop(db: db, uid: 'u1');
      addTearDown(backend.close);
      final row = _row('egg', qty: 30 * milli, rate: rs(16), text: 'EGGS (TRAY)');
      s.receiveBill(
        BillDraft(
          rows: [row],
          fromPhoto: true,
          header: BillHeader(billDateText: '२०८१/०७/०८', totalPaisa: rs(480)),
        ),
      );
      await pumpEventQueue();
      final delivery = (await db.collection('shops/u1/deliveries').get()).docs.single.data();
      expect(delivery['source'], 'bill_photo');
      expect(delivery['billDateText'], '२०८१/०७/०८');
      expect(delivery['billTotalPaisa'], rs(480));
      final batch = (await db.collection('shops/u1/batches').get()).docs.single.data();
      expect(batch['billLineText'], 'EGGS (TRAY)');
      final alias = (await db.collection('shops/u1/billAliases').get()).docs.single.data();
      expect(alias, containsPair('text', 'eggs tray'));
      expect(alias, containsPair('productId', 'egg'));

      final (other, otherBackend) = await openFirestoreShop(db: db, uid: 'u1');
      addTearDown(otherBackend.close);
      await pumpEventQueue();
      expect(other.productIdForBillText('Eggs tray'), 'egg');
    });
  });

  group('manual bill screen', () {
    Future<ShopStore> pumpApp(WidgetTester tester, {BarcodeScanner? scanner}) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final s = demoStore();
      await tester.pumpWidget(
        BhunteApp(
          store: s,
          assistant: DemoAssistantService(delay: Duration.zero),
          scanner: scanner ?? DemoBarcodeScanner(delay: Duration.zero),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('स्टक थप्नुस्'));
      await tester.pumpAndSettle();
      return s;
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    Future<void> keys(WidgetTester tester, String digits) async {
      for (final d in digits.split('')) {
        await tester.tap(find.byKey(ValueKey('key-$d')).last);
        await tester.pump();
      }
    }

    Future<void> padOk(WidgetTester tester) async {
      final okKey = find.byKey(const ValueKey('key-${Keys.ok}'));
      await tester.tap(okKey.evaluate().isNotEmpty ? okKey.last : find.text('ठीक छ').last);
      await tester.pumpAndSettle();
    }

    /// In the add sheet: qty on the keypad, optionally the rate and the sale price.
    Future<void> fillSheet(WidgetTester tester, String qty, {String? cost, String? price}) async {
      await keys(tester, qty);
      if (cost != null) {
        await tester.tap(find.byKey(const ValueKey('stock-cost')));
        await tester.pumpAndSettle();
        await keys(tester, cost);
        await padOk(tester);
      }
      if (price != null) {
        await tester.tap(find.byKey(const ValueKey('stock-price')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('key-${Keys.backspace}')).last);
        await tester.tap(find.byKey(const ValueKey('key-${Keys.backspace}')).last);
        await tester.pump();
        await keys(tester, price);
        await padOk(tester);
      }
      await tap(tester, find.byKey(const ValueKey('stock-save')));
    }

    Finder tile(String id) =>
        find.descendant(of: find.byKey(const ValueKey('bill-list')), matching: find.byKey(ValueKey('tile-$id')));

    testWidgets('MB-1/MB-5: three products, one with a new price, saved as one delivery', (tester) async {
      final store = await pumpApp(tester);
      await tap(tester, find.byKey(const ValueKey('manual-bill')));
      expect(find.text('हातैले बिल'), findsOneWidget);

      await tap(tester, tile('waiwai'));
      expect(find.text('कार्टुनमा (×30)'), findsOneWidget);
      await fillSheet(tester, '2', cost: '390');
      await tap(tester, tile('egg'));
      await fillSheet(tester, '90', cost: '16');
      await tap(tester, tile('soap'));
      await fillSheet(tester, '24', cost: '45', price: '65');

      expect(tester.widget<Text>(find.byKey(const ValueKey('bill-ticked-total'))).data, 'रु 3,300');
      expect(find.text('बेच्ने: रु 60 → रु 65'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('bill-save')));

      expect(find.byKey(const ValueKey('bill-saved')), findsOneWidget);
      expect(store.deliveries.single.batchCount, 3);
      expect(store.deliveries.single.totalCostPaisa, rs(3300));
      expect(store.deliveries.single.source, StockSource.manual);
      expect(store.product('waiwai').stockMilli, 66 * milli);
      expect(store.product('egg').stockMilli, 180 * milli);
      expect(store.product('soap').pricePaisa, rs(65));
      await tap(tester, find.text('ठीक छ'));
      expect(find.text('हातैले थप्नुस्'), findsOneWidget, reason: 'back on the stock screen');
    });

    testWidgets('MB-3/MB-4: same product opens its row; edit and remove before saving', (tester) async {
      final store = await pumpApp(tester);
      await tap(tester, find.byKey(const ValueKey('manual-bill')));
      await tap(tester, tile('egg'));
      await fillSheet(tester, '30', cost: '16');
      await tap(tester, tile('egg'));
      expect(find.text('ठीक छ'), findsWidgets, reason: 'editing the row, not adding');
      await tester.tap(find.byKey(const ValueKey('key-${Keys.backspace}')).last);
      await tester.tap(find.byKey(const ValueKey('key-${Keys.backspace}')).last);
      await fillSheet(tester, '60');
      expect(find.byKey(const ValueKey('row-1')), findsNothing, reason: 'still one row');
      expect(tester.widget<Text>(find.byKey(const ValueKey('row-summary-0'))).data, contains('+ 60 वटा'));

      await tap(tester, tile('soap'));
      await fillSheet(tester, '10', cost: '45');
      await tap(tester, find.byKey(const ValueKey('remove-1')));
      expect(tester.widget<Text>(find.byKey(const ValueKey('bill-ticked-total'))).data, 'रु 960');
      expect(store.deliveries, isEmpty, reason: 'nothing written before save');
    });

    testWidgets('MB-6: typed bill total that does not match', (tester) async {
      await pumpApp(tester);
      await tap(tester, find.byKey(const ValueKey('manual-bill')));
      await tap(tester, tile('egg'));
      await fillSheet(tester, '10', cost: '16');
      await tap(tester, find.byKey(const ValueKey('bill-total')));
      await keys(tester, '200');
      await padOk(tester);
      expect(find.byKey(const ValueKey('bill-total-warning')), findsOneWidget);
      expect(find.textContaining('बिलको जम्मा मिलेन'), findsOneWidget);
    });

    testWidgets('MB-8: leaving with rows asks first; cancel keeps the bill', (tester) async {
      final store = await pumpApp(tester);
      await tap(tester, find.byKey(const ValueKey('manual-bill')));
      await tap(tester, tile('egg'));
      await fillSheet(tester, '10', cost: '16');
      await tester.tap(find.byTooltip('पछाडि · Back'));
      await tester.pumpAndSettle();
      expect(find.text('बिल नसकी जाने?'), findsOneWidget);
      await tester.tap(find.text('रद्द'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('row-0')), findsOneWidget);
      await tester.tap(find.byTooltip('पछाडि · Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('leave-yes')));
      await tester.pumpAndSettle();
      expect(find.text('हातैले थप्नुस्'), findsOneWidget);
      expect(store.deliveries, isEmpty);
    });

    testWidgets('MB-2: an unknown scanned code makes the product, then its line', (tester) async {
      final store = await pumpApp(tester, scanner: FixedScanner('8901234567890'));
      await tap(tester, find.byKey(const ValueKey('manual-bill')));
      await tap(tester, find.byKey(const ValueKey('bill-scan')));
      expect(find.text('नयाँ सामान'), findsWidgets);
      expect(find.text('बिलबाट थपिन्छ'), findsOneWidget, reason: 'no opening stock on the form');
      await tester.enterText(find.byKey(const ValueKey('name-ne')), 'नुन');
      await tester.pumpAndSettle();
      final list = find
          .descendant(of: find.byKey(const ValueKey('new-product-list')), matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(find.byKey(const ValueKey('field-price')), 120, scrollable: list);
      await tester.tap(find.byKey(const ValueKey('field-price')));
      await tester.pumpAndSettle();
      await keys(tester, '25');
      await padOk(tester);
      await tap(tester, find.text('सामान थप्नुस्'));

      expect(find.text('कति वटा आयो?'), findsOneWidget, reason: 'its line sheet opens next');
      await fillSheet(tester, '20', cost: '18');
      await tap(tester, find.byKey(const ValueKey('bill-save')));
      final salt = store.productByBarcode('8901234567890')!;
      expect(salt.stockMilli, 20 * milli);
      expect(store.batchesFor(salt.id).single.source, StockSource.manual);
    });
  });
}
