// Scenarios F-1 … F-17 from docs/product-photos.md (F-13, web files, is the
// same flow with the barcode left to the AI: covered by F-3).
import 'dart:typed_data';

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
import 'package:bhunte_ai/photos/cloud_photo_reader.dart';
import 'package:bhunte_ai/photos/image_shrink.dart';
import 'package:bhunte_ai/photos/photo_reader.dart';
import 'package:bhunte_ai/photos/photo_source.dart';
import 'package:bhunte_ai/photos/webcam_screen.dart';
import 'package:bhunte_ai/screens/home_screen.dart';
import 'package:bhunte_ai/screens/new_product_screen.dart';
import 'package:camera/camera.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

final _jpeg = img.encodeJpg(img.Image(width: 8, height: 8));
final _thumb = ProductImage(jpeg: _jpeg, width: 8, height: 8);

class FakePhotoSource implements PhotoSource {
  FakePhotoSource({this.barcode});

  /// What the on-phone reader finds in the barcode photo.
  final String? barcode;

  @override
  Future<PickedPhoto?> pick(BuildContext context, PhotoFrom from, {int maxSide = aiPhotoSide}) async =>
      PickedPhoto(jpeg: _jpeg, path: 'photo.jpg');

  @override
  Future<String?> readBarcode(PickedPhoto photo) async => barcode;

  @override
  Future<ProductImage?> thumbnail(PickedPhoto photo) async => _thumb;
}

class ScriptedReader implements PhotoReader {
  ScriptedReader(this.result);
  final PhotoReadResult result;
  final List<Set<PhotoRole>> sent = [];
  String? barcodeOnPhone;

  @override
  Future<PhotoReadResult> read(Map<PhotoRole, Uint8List> photos, {String? barcodeOnPhone}) async {
    sent.add(photos.keys.toSet());
    this.barcodeOnPhone = barcodeOnPhone;
    return result;
  }
}

const _waiwai = PhotoReading(
  nameNe: 'वाइवाइ चिकेन',
  nameEn: 'Wai Wai Chicken',
  sizeText: '70 g',
  unit: Unit.packet,
  mrpPaisa: 2500,
);

class _Recorder implements ShopBackend {
  final List<ShopChange> changes = [];
  int _n = 0;

  @override
  String newId() => 'id-${++_n}';

  @override
  void commit(ShopChange change) => changes.add(change);
}

Future<ShopStore> _pumpApp(WidgetTester tester, {required PhotoReader reader, PhotoSource? source}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final store = demoStore();
  await tester.pumpWidget(
    BhunteApp(
      store: store,
      assistant: DemoAssistantService(delay: Duration.zero),
      scanner: DemoBarcodeScanner(delay: Duration.zero),
      photoReader: reader,
      photoSource: source ?? FakePhotoSource(),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _key(WidgetTester tester, String key) => _tap(tester, find.byKey(ValueKey(key)));

/// Stock → सामानको फोटो → the given slots filled.
Future<void> _capture(WidgetTester tester, List<String> slots) async {
  await tester.tap(find.text('स्टक थप्नुस्'));
  await tester.pumpAndSettle();
  await _tap(tester, find.text('सामानको फोटो'));
  for (final s in slots) {
    await _key(tester, 'camera-$s');
  }
}

String _field(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

Finder get _formList =>
    find.descendant(of: find.byKey(const ValueKey('new-product-list')), matching: find.byType(Scrollable)).first;

Future<void> _pad(WidgetTester tester, String field, String digits) async {
  await tester.scrollUntilVisible(find.byKey(ValueKey(field)), 120, scrollable: _formList);
  await tester.tap(find.byKey(ValueKey(field)));
  await tester.pumpAndSettle();
  for (final d in digits.split('')) {
    await tester.tap(find.byKey(ValueKey('key-$d')).last);
    await tester.pump();
  }
  final okKey = find.byKey(const ValueKey('key-${Keys.ok}'));
  await tester.tap(okKey.evaluate().isNotEmpty ? okKey.last : find.text('ठीक छ').last);
  await tester.pumpAndSettle();
}

void main() {
  group('helpers', () {
    test('PR4/F-10: the size goes into the name, except for loose goods', () {
      expect(nameWithSize('वाइवाइ चिकेन', '70 g', Unit.packet), 'वाइवाइ चिकेन 70g');
      expect(nameWithSize('Coke', '1 L', Unit.piece), 'Coke 1L');
      expect(nameWithSize('Dettol 125g', '125 g', Unit.piece), 'Dettol 125g', reason: 'already in the name');
      expect(nameWithSize('जिरा मसिनो चामल', '25 kg', Unit.kg), 'जिरा मसिनो चामल');
      expect(nameWithSize('चाउचाउ', null, Unit.packet), 'चाउचाउ');
    });

    test('F-9: the app also drops malformed fields from the reply', () {
      final r = PhotoReading.fromMap({
        'nameNe': '  वाइवाइ ',
        'unit': 'box',
        'mrpPaisa': -5,
        'confidence': {'nameNe': 'low', 'unit': 'high'},
        'extra': 'ignored',
      });
      expect(r.nameNe, 'वाइवाइ');
      expect(r.unit, isNull);
      expect(r.mrpPaisa, isNull);
      expect(r.lowConfidence, {'nameNe'});
    });

    test('Cloud Function errors map to what the form says', () {
      expect(CloudPhotoReader.problemFor('resource-exhausted', 'limit-reached'), PhotoReadProblem.limitReached);
      expect(CloudPhotoReader.problemFor('failed-precondition', 'unreadable'), PhotoReadProblem.unreadable);
      expect(CloudPhotoReader.problemFor('unavailable', 'ai-unavailable'), PhotoReadProblem.unavailable);
      expect(CloudPhotoReader.problemFor('unavailable', 'Failed to connect'), PhotoReadProblem.offline);
      expect(CloudPhotoReader.problemFor('not-found', null), PhotoReadProblem.unavailable, reason: 'not deployed');
      expect(CloudPhotoReader.problemFor('unauthenticated', null), PhotoReadProblem.unavailable);
    });

    test('F-15: a 12 MP photo shrinks to 1024 px for the AI and a ≤ 60 KB 256 px thumbnail', () async {
      final big = img.encodeJpg(img.Image(width: 4000, height: 3000)..clear(img.ColorRgb8(200, 120, 40)));
      final ai = img.decodeJpg(await shrinkToJpeg(big))!;
      expect([ai.width, ai.height], [1024, 768]);
      final thumb = await makeThumbnail(big);
      expect([thumb.width, thumb.height], [256, 192]);
      expect(thumb.jpeg.length, lessThanOrEqualTo(ProductImage.maxBytes));
    });
  });

  group('store', () {
    test('the thumbnail is saved in the same change as the new product', () {
      final rec = _Recorder();
      final s = ShopStore(shopName: 'x', products: demoProducts(), customers: const [], backend: rec);
      final p = s.addProduct(
        nameNe: 'वाइवाइ चिकेन 70g',
        pricePaisa: rs(25),
        costPaisa: rs(18),
        unit: Unit.packet,
        openingStockMilli: 30 * milli,
        image: _thumb,
      );
      expect(rec.changes, hasLength(1));
      expect(rec.changes.single.images[p.id], same(_thumb));
      expect(s.image(p.id), same(_thumb));
    });

    test('F-12: replace and remove; too-large thumbnails are refused', () {
      final rec = _Recorder();
      final s = ShopStore(shopName: 'x', products: demoProducts(), customers: const [], backend: rec);
      s.setProductImage('rice', _thumb);
      expect(s.image('rice'), same(_thumb));
      s.setProductImage('rice', null);
      expect(s.image('rice'), isNull);
      expect(rec.changes.last.images, {'rice': null});
      final huge = ProductImage(jpeg: Uint8List(ProductImage.maxBytes + 1), width: 256, height: 256);
      expect(() => s.setProductImage('rice', huge), throwsArgumentError);
      expect(
        () => s.addProduct(nameNe: 'नुन', pricePaisa: 100, costPaisa: 0, unit: Unit.piece, image: huge),
        throwsArgumentError,
      );
    });

    test('F-11/F-12 Firestore: productImages doc + hasImage, read back, then removed', () async {
      final db = FakeFirebaseFirestore();
      final (store, backend) = await openFirestoreShop(db: db, uid: 'u1');
      addTearDown(backend.close);

      store.setProductImage('rice', _thumb);
      await pumpEventQueue();
      final doc = (await db.doc('shops/u1/productImages/rice').get()).data()!;
      expect(doc['jpegBase64'], isA<String>());
      expect(doc['updatedBy'], 'u1');
      expect((await db.doc('shops/u1/products/rice').get()).data()!['hasImage'], isTrue);

      // A second device opening the shop gets the thumbnail from Firestore.
      final (other, otherBackend) = await openFirestoreShop(db: db, uid: 'u1');
      addTearDown(otherBackend.close);
      await pumpEventQueue();
      expect(other.image('rice')!.jpeg, _jpeg);

      store.setProductImage('rice', null);
      await pumpEventQueue();
      expect((await db.doc('shops/u1/productImages/rice').get()).exists, isFalse);
      expect((await db.doc('shops/u1/products/rice').get()).data()!['hasImage'], isFalse);
    });
  });

  group('screens', () {
    testWidgets('F-1/F-14: three photos fill name, unit, barcode and MRP hint; never price or stock', (tester) async {
      final reader = ScriptedReader(const PhotoRead(_waiwai));
      final store = await _pumpApp(
        tester,
        reader: reader,
        source: FakePhotoSource(barcode: '8901234567890'),
      );
      await _capture(tester, ['front', 'barcode', 'label']);
      await _key(tester, 'read-photos');

      // D5: the barcode was read on the phone, so its photo isn't sent to the AI.
      expect(reader.sent.single, {PhotoRole.front, PhotoRole.label});
      expect(reader.barcodeOnPhone, '8901234567890');

      expect(_field(tester, 'name-ne'), 'वाइवाइ चिकेन 70g');
      expect(_field(tester, 'name-en'), 'Wai Wai Chicken 70g');
      expect(find.byKey(const ValueKey('ai-nameNe')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-unit')), findsOneWidget);
      expect(find.byKey(const ValueKey('form-photo')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('mrp-hint')), 120, scrollable: _formList);
      expect(find.text('प्याकेटमा MRP: रु 25'), findsOneWidget);
      expect(find.text('बेच्ने मूल्य · प्रति प्याकेट'), findsOneWidget);
      expect(find.text('रु —'), findsNWidgets(2), reason: 'price and cost stay empty (PR2)');

      await _pad(tester, 'field-price', '25');
      await _pad(tester, 'field-cost', '18');
      await _pad(tester, 'field-opening', '30');
      await tester.scrollUntilVisible(find.text('8901234567890'), 120, scrollable: _formList);
      await _tap(tester, find.text('सामान थप्नुस्'));

      final p = store.products.firstWhere((p) => p.nameNe == 'वाइवाइ चिकेन 70g');
      expect(p.pricePaisa, rs(25));
      expect(p.costPaisa, rs(18));
      expect(p.stockMilli, 30 * milli);
      expect(p.unit, Unit.packet);
      expect(p.barcode, '8901234567890');
      expect(store.image(p.id), same(_thumb));
      await tester.ensureVisible(find.byKey(ValueKey('thumb-${p.id}')));
      expect(find.byKey(ValueKey('thumb-${p.id}')), findsOneWidget, reason: 'grid tile shows the photo');
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('F-2/F-3: the phone can\'t read the barcode: the AI\'s checked digits fill it, tagged', (tester) async {
      final reader = ScriptedReader(
        const PhotoRead(PhotoReading(nameNe: 'वाइवाइ', barcode: '8901234567890', lowConfidence: {'barcode'})),
      );
      await _pumpApp(tester, reader: reader);
      await _capture(tester, ['front', 'barcode']);
      await _key(tester, 'read-photos');

      expect(reader.sent.single, {PhotoRole.front, PhotoRole.barcode});
      await tester.scrollUntilVisible(find.text('8901234567890'), 120, scrollable: _formList);
      expect(find.byKey(const ValueKey('ai-barcode')), findsOneWidget);
      expect(find.text('भुन्टेले भरेको · जाँच्नुस्'), findsOneWidget);
    });

    testWidgets('F-3: digits that fail the check are dropped and the form says to scan', (tester) async {
      final reader = ScriptedReader(const PhotoRead(PhotoReading(nameNe: 'वाइवाइ', barcode: '8901234567891')));
      await _pumpApp(tester, reader: reader);
      await _capture(tester, ['barcode', 'label']);
      await _key(tester, 'read-photos');

      expect(find.textContaining('बारकोड पढ्न सकिएन'), findsOneWidget);
      expect(find.text('8901234567891'), findsNothing);
      expect(find.byKey(const ValueKey('form-photo')), findsNothing, reason: 'no front photo, no thumbnail');
    });

    testWidgets('F-4: a barcode already in the shop offers adding stock instead', (tester) async {
      final reader = ScriptedReader(const PhotoRead(_waiwai));
      await _pumpApp(
        tester,
        reader: reader,
        source: FakePhotoSource(barcode: 'demo-egg'),
      );
      await _capture(tester, ['barcode']);
      await _key(tester, 'read-photos');

      expect(find.text('पहिल्यै छ: अण्डा'), findsOneWidget);
      expect(reader.sent, isEmpty, reason: 'no AI read for a known product');
      await _key(tester, 'existing-add-stock');
      expect(find.text('स्टकमा थप्नुस्'), findsOneWidget, reason: 'add-stock sheet for अण्डा');
    });

    testWidgets('F-5/F-17/F-8: without the AI the form opens with the photo and the phone barcode', (tester) async {
      for (final (problem, note) in [
        (PhotoReadProblem.offline, 'इन्टरनेट आएपछि फोटोबाट भर्न सकिन्छ'),
        (PhotoReadProblem.unavailable, 'फोटोबाट भर्ने सुविधा अहिले उपलब्ध छैन'),
        (PhotoReadProblem.limitReached, 'आजको फोटो पढ्ने सीमा सकियो — हातैले भर्नुस्'),
      ]) {
        await _pumpApp(
          tester,
          reader: ScriptedReader(PhotoReadFailed(problem)),
          source: FakePhotoSource(barcode: '8901234567890'),
        );
        await _capture(tester, ['front', 'barcode', 'label']);
        await _key(tester, 'read-photos');

        expect(find.text(note), findsOneWidget);
        expect(find.byKey(const ValueKey('form-photo')), findsOneWidget);
        expect(_field(tester, 'name-ne'), isEmpty);
        await tester.scrollUntilVisible(find.text('8901234567890'), 120, scrollable: _formList);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('F-6: an unsure name is highlighted until the user changes it', (tester) async {
      await _pumpApp(
        tester,
        reader: ScriptedReader(const PhotoRead(PhotoReading(nameNe: 'वाइवाइ', lowConfidence: {'nameNe'}))),
      );
      await _capture(tester, ['front']);
      await _key(tester, 'read-photos');

      expect(find.text('भुन्टेले भरेको · जाँच्नुस्'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('name-ne')), 'वाइवाइ चिकेन');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-nameNe')), findsNothing);
    });

    testWidgets('F-7: unreadable photos stay on the capture screen; "हातैले भर्नुस्" carries on', (tester) async {
      await _pumpApp(tester, reader: ScriptedReader(const PhotoReadFailed(PhotoReadProblem.unreadable)));
      await _capture(tester, ['front', 'label']);
      await _key(tester, 'read-photos');

      expect(find.text('फोटोबाट पढ्न सकिएन — अर्को फोटो खिच्नुस् वा हातैले भर्नुस्'), findsOneWidget);
      expect(find.byKey(const ValueKey('slot-front')), findsOneWidget);
      await _key(tester, 'fill-by-hand');
      expect(find.byKey(const ValueKey('new-product-list')), findsOneWidget);
      expect(find.byKey(const ValueKey('form-photo')), findsOneWidget);
    });

    testWidgets('F-16: leaving without saving saves nothing', (tester) async {
      final store = await _pumpApp(tester, reader: ScriptedReader(const PhotoRead(_waiwai)));
      final before = store.products.length;
      await _capture(tester, ['front']);
      await _key(tester, 'read-photos');
      await tester.tap(find.byTooltip('पछाडि · Back'));
      await tester.pumpAndSettle();
      expect(store.products.length, before);
      expect(find.text('हातैले थप्नुस्'), findsOneWidget, reason: 'back on the stock screen');
    });

    testWidgets('form button "फोटोबाट भर्नुस्" fills the open form', (tester) async {
      await _pumpApp(tester, reader: ScriptedReader(const PhotoRead(_waiwai)));
      await tester.tap(find.text('स्टक थप्नुस्'));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('नयाँ सामान'));
      await _key(tester, 'fill-from-photos');
      await _key(tester, 'camera-label');
      await _key(tester, 'read-photos');
      expect(_field(tester, 'name-ne'), 'वाइवाइ चिकेन 70g');
    });

    testWidgets('F-11/F-12: edit a product to add, then remove its photo', (tester) async {
      final store = await _pumpApp(tester, reader: const NoPhotoReader());
      Future<void> edit() async {
        NewProductScreen.edit(tester.element(find.byType(HomeScreen)), store.product('rice'));
        await tester.pumpAndSettle();
      }

      await edit();
      expect(find.byKey(const ValueKey('fill-from-photos')), findsNothing, reason: 'AI fill is for new products');
      await _key(tester, 'add-photo');
      await _key(tester, 'photo-from-camera');
      expect(find.byKey(const ValueKey('form-photo')), findsOneWidget);
      await _tap(tester, find.text('सुरक्षित गर्नुस्'));
      expect(store.image('rice'), same(_thumb));
      await tester.pump(const Duration(seconds: 3)); // let the toast go

      await edit();
      await _key(tester, 'remove-photo');
      await _tap(tester, find.text('सुरक्षित गर्नुस्'));
      expect(store.image('rice'), isNull);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('desktop webcam', () {
    /// Opens the webcam screen; the returned list receives what it pops.
    Future<List<WebcamResult?>> openWebcam(
      WidgetTester tester,
      Future<List<CameraDescription>> Function() cameras,
    ) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final results = <WebcamResult?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () async => results.add(
                await Navigator.of(
                  c,
                ).push<WebcamResult>(MaterialPageRoute(builder: (_) => WebcamScreen(findCameras: cameras))),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('no camera: says so, can retry, and offers choosing a file instead', (tester) async {
      var asked = 0;
      final results = await openWebcam(tester, () async {
        asked++;
        return [];
      });
      expect(find.textContaining('क्यामेरा भेटिएन'), findsOneWidget);
      expect(find.byKey(const ValueKey('webcam-take')), findsNothing);

      await _key(tester, 'webcam-retry');
      expect(asked, 2, reason: 'retry looks for cameras again');

      await _key(tester, 'webcam-files');
      expect(results.single, isA<WebcamUseFiles>());
    });

    testWidgets('permission refused: explains how to allow it in the browser', (tester) async {
      await openWebcam(tester, () async => throw CameraException('CameraAccessDenied', 'denied'));
      expect(find.textContaining('अनुमति छैन'), findsOneWidget);
      expect(find.byKey(const ValueKey('webcam-files')), findsOneWidget);
    });
  });
}
