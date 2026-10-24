// Bill photo scenarios BL-1 … BL-22 (docs/stock-from-bill.md). The AI is a
// scripted reader; money/stock rules are also unit-tested in bill_test.dart.
import 'dart:typed_data';

import 'package:bhunte_ai/ai/demo_services.dart';
import 'package:bhunte_ai/app.dart';
import 'package:bhunte_ai/bills/bill_mapping.dart';
import 'package:bhunte_ai/bills/bill_reader.dart';
import 'package:bhunte_ai/bills/demo_bill_reader.dart';
import 'package:bhunte_ai/core/keypad_input.dart';
import 'package:bhunte_ai/core/money.dart';
import 'package:bhunte_ai/core/qty.dart';
import 'package:bhunte_ai/data/bill.dart';
import 'package:bhunte_ai/data/demo_data.dart';
import 'package:bhunte_ai/data/models.dart';
import 'package:bhunte_ai/data/shop_backend.dart';
import 'package:bhunte_ai/data/shop_store.dart';
import 'package:bhunte_ai/photos/image_shrink.dart';
import 'package:bhunte_ai/photos/photo_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

final _jpeg = img.encodeJpg(img.Image(width: 8, height: 8));

class FakePhotoSource implements PhotoSource {
  final List<int> sides = [];

  @override
  Future<PickedPhoto?> pick(BuildContext context, PhotoFrom from, {int maxSide = aiPhotoSide}) async {
    sides.add(maxSide);
    return PickedPhoto(jpeg: _jpeg);
  }

  @override
  Future<String?> readBarcode(PickedPhoto photo) async => null;

  @override
  Future<ProductImage?> thumbnail(PickedPhoto photo) async => null;
}

class RecordingReader extends DemoBillReader {
  RecordingReader(BillReadResult result) : super(delay: Duration.zero, result: result);
  int pages = 0;

  @override
  Future<BillReadResult> read(List<Uint8List> pages, List<Map<String, Object?>> catalog) {
    this.pages = pages.length;
    return super.read(pages, catalog);
  }
}

BillLineReading _line(
  String text, {
  int? qty,
  String qtyIn = 'unit',
  String? packWord,
  int? free,
  int? rate,
  int? amount,
  String? id,
  String match = 'high',
  String? nameNe,
  bool unsure = false,
  String? note,
}) => BillLineReading(
  text: text,
  qtyMilli: qty == null ? null : qty * milli,
  qtyIn: qtyIn,
  packWord: packWord,
  freeQtyMilli: free == null ? null : free * milli,
  ratePaisa: rate == null ? null : rs(rate),
  amountPaisa: amount == null ? null : rs(amount),
  productId: id,
  match: id == null ? 'none' : match,
  nameNe: nameNe,
  unsureNumbers: unsure,
  note: note,
);

/// BL-1's bill.
final _bl1 = BillReading(
  supplierName: 'राम ट्रेडर्स',
  supplierPhone: '9812345678',
  billNo: '1452',
  totalPaisa: rs(5365),
  lines: [
    _line('WAI WAI CHK 2 CTN', qty: 2, qtyIn: 'pack', packWord: 'CTN', rate: 390, amount: 780, id: 'waiwai'),
    _line('चिनी 25 kg', qty: 25, qtyIn: 'kg', rate: 105, amount: 2625, id: 'sugar'),
    _line('LUX SOAP', qty: 24, rate: 45, amount: 1080, id: 'soap'),
    _line('BISCUIT', qty: 40, rate: 22, amount: 880, id: 'biscuit'),
  ],
);

ShopStore _shop() {
  final s = demoStore();
  s.addProduct(nameNe: 'कोक 500ml', nameEn: 'Coke 500ml', pricePaisa: rs(60), costPaisa: rs(45), unit: Unit.piece);
  return s;
}

String _coke(ShopStore s) => s.products.firstWhere((p) => p.nameEn == 'Coke 500ml').id;

void main() {
  group('mapping AI lines to rows', () {
    test('BL-1: confident lines start ticked; packs from the product; header kept', () {
      final d = draftFromReading(_bl1, _shop());
      expect(d.fromPhoto, isTrue);
      expect(d.rows.every((r) => r.ticked), isTrue);
      expect(d.rows.first.unitsMilli, 60 * milli);
      expect(d.rows.first.unitCostPaisa, rs(13));
      expect(d.header.supplierName, 'राम ट्रेडर्स');
      expect(d.tickedTotalPaisa, rs(5365));
      expect(d.totalDifferencePaisa, isNull);
    });

    test('BL-2/BL-9/BL-17/BL-18: doubts become unticked rows with the reason', () {
      final s = _shop();
      s.setArchived('milk', true);
      final d = draftFromReading(
        BillReading(
          lines: [
            _line('LUX SOAP', qty: 24, rate: 45, amount: 108, id: 'soap'),
            _line('अण्डा', qty: 30, rate: 16, amount: 480, id: 'egg', unsure: true, note: '3 हो कि 8?'),
            _line('चिनी 2 pcs', qty: 2, rate: 105, amount: 210, id: 'sugar'),
            _line('MILK', qty: 8, rate: 48, amount: 384, id: 'milk'),
            _line('XYZ', qty: 1, rate: 10, amount: 10, id: 'not-a-product'),
            _line('BISC?', qty: 10, rate: 22, amount: 220, id: 'biscuit', match: 'low'),
          ],
        ),
        s,
      );
      final [soap, egg, sugar, milk, xyz, bisc] = d.rows;
      expect(soap.amountMismatch, isTrue);
      expect(soap.ticked, isFalse);
      expect(egg.issues, {RowIssue.unsureNumbers});
      expect(egg.note, '3 हो कि 8?');
      expect(sugar.issues, contains(RowIssue.unitConflict));
      expect(milk.issues, contains(RowIssue.hiddenProduct));
      expect(xyz.isNew, isTrue);
      expect(bisc.issues, {RowIssue.unsureMatch});
      expect(d.rows.where((r) => r.ticked), isEmpty);
    });

    test('BL-5/BL-8: unknown pack size flagged; free items counted', () {
      final s = _shop();
      final d = draftFromReading(
        BillReading(
          lines: [
            _line(
              'COKE 500ML 1 CRATE',
              qty: 1,
              qtyIn: 'pack',
              packWord: 'crate',
              rate: 1080,
              amount: 1080,
              id: _coke(s),
            ),
            _line('BISCUIT 12+1', qty: 12, free: 1, rate: 22, amount: 264, id: 'biscuit'),
          ],
        ),
        s,
      );
      expect(d.rows.first.issues, {RowIssue.packUnknown});
      expect(d.rows.first.canSave, isFalse);
      expect(d.rows.last.unitsMilli, 13 * milli);
      expect(d.rows.last.ticked, isTrue);
    });

    test('BL-7: a remembered bill name beats the AI', () {
      final s = _shop();
      s.receiveBill(
        BillDraft(
          rows: [
            BillRow(
              productId: 'waiwai',
              text: 'WAI WAI CHK 70G',
              qtyMilli: 10 * milli,
              amountPaisa: rs(140),
              ticked: true,
            ),
          ],
          fromPhoto: true,
        ),
      );
      final d = draftFromReading(
        BillReading(
          lines: [_line('wai-wai chk 70g', qty: 5, rate: 14, amount: 70, id: 'biscuit', match: 'low')],
        ),
        s,
      );
      expect(d.rows.single.productId, 'waiwai');
      expect(d.rows.single.issues, isEmpty);
      expect(d.rows.single.ticked, isTrue);
    });

    test('BL-21: too many lines → a notice on the bill', () {
      final d = draftFromReading(BillReading(lines: [_line('X', qty: 1, amount: 10)], tooManyLines: true), _shop());
      expect(d.notice, contains('धेरै लाइन'));
    });
  });

  group('bill photo screens', () {
    late FakePhotoSource source;

    Future<ShopStore> pumpApp(WidgetTester tester, BillReader reader, {ShopStore? store}) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final s = store ?? _shop();
      source = FakePhotoSource();
      await tester.pumpWidget(
        BhunteApp(
          store: s,
          assistant: DemoAssistantService(delay: Duration.zero),
          scanner: DemoBarcodeScanner(delay: Duration.zero),
          photoSource: source,
          billReader: reader,
        ),
      );
      await tester.pumpAndSettle();
      return s;
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    Future<void> key(WidgetTester tester, String k) => tap(tester, find.byKey(ValueKey(k)));

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

    /// Stock → बिलको फोटो → [pages] photos → पढ्नुस्.
    Future<void> readBill(WidgetTester tester, {int pages = 1}) async {
      await tester.tap(find.text('स्टक थप्नुस्'));
      await tester.pumpAndSettle();
      await tap(tester, find.text('बिलको फोटो'));
      for (var i = 0; i < pages; i++) {
        await key(tester, 'camera-page$i');
      }
      await key(tester, 'read-bill');
    }

    testWidgets('BL-1: read, change one price, save → one delivery with 4 batches', (tester) async {
      final store = await pumpApp(tester, RecordingReader(BillRead(_bl1)));
      await readBill(tester);

      expect(source.sides, [billPageSide], reason: 'bill pages are taken larger');
      expect(find.text('बिल जाँच्नुस्'), findsOneWidget);
      final billList = find
          .descendant(of: find.byKey(const ValueKey('bill-list')), matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(find.text('भुन्टेले भरेको'), 200, scrollable: billList);
      expect(find.text('भुन्टेले भरेको'), findsOneWidget);
      expect(find.text('राम ट्रेडर्स · 9812345678 · बिल 1452'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('bill-ticked-total'))).data, 'रु 5,365');

      // चिनी: open its row, sale price ₹120 → ₹125.
      await tester.scrollUntilVisible(find.byKey(const ValueKey('row-summary-1')), -200, scrollable: billList);
      await key(tester, 'row-summary-1');
      await tester.tap(find.byKey(const ValueKey('stock-price')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('key-${Keys.backspace}')).last);
      }
      await keys(tester, '125');
      await padOk(tester);
      await key(tester, 'stock-save');
      await key(tester, 'bill-save');

      expect(find.byKey(const ValueKey('bill-saved')), findsOneWidget);
      final d = store.deliveries.single;
      expect(d.source, StockSource.billPhoto);
      expect(d.batchCount, 4);
      expect(d.totalCostPaisa, rs(5365));
      expect(d.supplierPhone, '9812345678');
      expect(d.billNo, '1452');
      expect(store.product('waiwai').stockMilli, 66 * milli);
      expect(store.product('sugar').pricePaisa, rs(125));
      expect(store.priceHistory('sugar').last.reason, PriceReason.stock);
      expect(store.productIdForBillText('wai wai chk 2 ctn'), 'waiwai');
    });

    testWidgets('BL-2/BL-3: a sum that doesn\'t add up blocks the row until checked; bill total banner', (
      tester,
    ) async {
      final store = await pumpApp(
        tester,
        RecordingReader(
          BillRead(
            BillReading(
              totalPaisa: rs(1560),
              lines: [
                _line('LUX SOAP', qty: 24, rate: 45, amount: 108, id: 'soap'),
                _line('EGG', qty: 30, rate: 16, amount: 480, id: 'egg'),
              ],
            ),
          ),
        ),
      );
      await readBill(tester);
      expect(find.text('हिसाब मिलेन: 24 × रु 45 = रु 1,080, बिलमा रु 108'), findsOneWidget);
      expect(find.byKey(const ValueKey('bill-total-warning')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('bill-ticked-total'))).data, 'रु 480');

      await key(tester, 'row-summary-0');
      await key(tester, 'stock-save'); // keeps 24 @ ₹45
      expect(find.textContaining('हिसाब मिलेन'), findsNothing);
      expect(find.byKey(const ValueKey('bill-total-warning')), findsNothing, reason: '1,080 + 480 = 1,560');
      await key(tester, 'bill-save');
      expect(store.batchesFor('soap').single.totalCostPaisa, rs(1080));
    });

    testWidgets('BL-5: crate size entered, kept on the product, same save', (tester) async {
      final store = _shop();
      final coke = _coke(store);
      await pumpApp(
        tester,
        RecordingReader(
          BillRead(
            BillReading(
              lines: [
                _line(
                  'COKE 500ML 1 CRATE',
                  qty: 1,
                  qtyIn: 'pack',
                  packWord: 'crate',
                  rate: 1080,
                  amount: 1080,
                  id: coke,
                ),
              ],
            ),
          ),
        ),
        store: store,
      );
      await readBill(tester);
      expect(find.text('एक crateमा कति वटा?'), findsOneWidget);
      await key(tester, 'pack-size-0');
      await keys(tester, '24');
      await padOk(tester);
      expect(find.byKey(const ValueKey('keep-pack-0')), findsOneWidget);
      await key(tester, 'bill-save');
      expect(store.product(coke).stockMilli, 24 * milli);
      expect(store.product(coke).packName, 'crate');
      expect(store.product(coke).packSizeMilli, 24 * milli);
      expect(store.batchesFor(coke).single.unitCostPaisa, rs(45));
    });

    testWidgets('BL-6: a new item becomes a product, then its batch on save', (tester) async {
      final store = await pumpApp(
        tester,
        RecordingReader(
          BillRead(
            BillReading(
              lines: [_line('Real Juice Mango 1L', qty: 12, rate: 300, amount: 3600, nameNe: 'रियल जुस आँप')],
            ),
          ),
        ),
      );
      await readBill(tester);
      expect(find.byKey(const ValueKey('bill-save')), findsOneWidget);
      await key(tester, 'make-0');
      expect(find.text('बिलबाट थपिन्छ'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('name-ne'))).controller!.text, 'रियल जुस आँप');
      final list = find
          .descendant(of: find.byKey(const ValueKey('new-product-list')), matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(find.byKey(const ValueKey('field-price')), 120, scrollable: list);
      expect(find.text('रु 300'), findsOneWidget, reason: 'cost from the bill');
      await tester.tap(find.byKey(const ValueKey('field-price')));
      await tester.pumpAndSettle();
      await keys(tester, '360');
      await padOk(tester);
      await tap(tester, find.text('सामान थप्नुस्'));

      final juice = store.products.firstWhere((p) => p.nameNe == 'रियल जुस आँप');
      expect(juice.stockMilli, 0, reason: 'D8: no opening stock');
      expect(find.byKey(const ValueKey('tick-0')), findsOneWidget, reason: 'row linked');
      await key(tester, 'bill-save');
      expect(store.product(juice.id).stockMilli, 12 * milli);
      expect(store.batchesFor(juice.id).single.unitCostPaisa, rs(300));
      await tester.pump(const Duration(seconds: 3)); // let the toast go
    });

    testWidgets('BL-7: correcting a match is remembered for the next bill', (tester) async {
      final reading = BillReading(
        lines: [_line('WAI WAI CHK 70G', qty: 10, rate: 14, amount: 140, id: 'biscuit', match: 'low')],
      );
      final store = await pumpApp(tester, RecordingReader(BillRead(reading)));
      await readBill(tester);
      expect(find.text('सामान मिलेको पक्का छैन'), findsOneWidget);
      await key(tester, 'choose-0');
      await tap(tester, find.byKey(const ValueKey('tile-waiwai')).last);
      await key(tester, 'bill-save');
      expect(store.product('waiwai').stockMilli, 16 * milli);
      expect(store.product('biscuit').stockMilli, 40 * milli);
      expect(draftFromReading(reading, store).rows.single.productId, 'waiwai');
    });

    testWidgets('BL-10: two pages are sent together and make one bill', (tester) async {
      final reader = RecordingReader(BillRead(_bl1));
      final store = await pumpApp(tester, reader);
      await readBill(tester, pages: 2);
      expect(reader.pages, 2);
      await key(tester, 'bill-save');
      expect(store.deliveries, hasLength(1));
    });

    testWidgets('BL-11/BL-12/BL-13: reading fails → message and a manual bill', (tester) async {
      for (final problem in BillReadProblem.values) {
        final store = await pumpApp(tester, RecordingReader(BillReadFailed(problem)));
        await readBill(tester);
        expect(find.text(problem.message), findsOneWidget);
        expect(find.byKey(const ValueKey('slot-page0')), findsOneWidget, reason: 'pages stay');
        await key(tester, 'bill-by-hand');
        expect(find.text('हातैले बिल'), findsOneWidget);
        expect(store.deliveries, isEmpty);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('BL-19/BL-20: nothing ticked can\'t be saved; leaving asks and saves nothing', (tester) async {
      final store = await pumpApp(
        tester,
        RecordingReader(
          BillRead(BillReading(lines: [_line('EGG', qty: 30, rate: 16, amount: 480, id: 'egg', unsure: true)])),
        ),
      );
      await readBill(tester);
      await tester.tap(find.byKey(const ValueKey('bill-save')));
      await tester.pumpAndSettle();
      expect(store.deliveries, isEmpty, reason: 'disabled with nothing ticked');
      expect(find.text('स्टकमा थप्नुस् (0)'), findsOneWidget);
      await tester.tap(find.byTooltip('पछाडि · Back'));
      await tester.pumpAndSettle();
      expect(find.text('पढेको बिल हराउँछ। केही पनि स्टकमा जाँदैन।'), findsOneWidget);
      await key(tester, 'leave-yes');
      expect(store.deliveries, isEmpty);
      expect(store.productIdForBillText('egg'), isNull);
    });
  });
}
