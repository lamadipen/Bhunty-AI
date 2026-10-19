import 'package:bhunte_ai/core/money.dart';
import 'package:bhunte_ai/core/qty.dart';
import 'package:bhunte_ai/data/models.dart';
import 'package:bhunte_ai/data/shop_backend.dart';
import 'package:bhunte_ai/firebase/firestore_backend.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const uid = 'owner-1';
  final now = DateTime.utc(2026, 10, 18, 6); // 11:45 NPT
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  Future<Map<String, dynamic>> doc(String path) async => (await db.doc('shops/$uid/$path').get()).data()!;

  test('first login creates the shop and seeds the sample catalog', () async {
    final (store, backend) = await openFirestoreShop(db: db, uid: uid, clock: () => now);
    addTearDown(backend.close);

    final shop = (await db.doc('shops/$uid').get()).data()!;
    expect(shop['ownerUid'], uid);
    expect(store.products, hasLength(8));
    // Same order as the sample catalog, not Firestore's id order.
    expect(store.favourites.map((p) => p.id).take(3), ['waiwai', 'egg', 'milk']);
    expect(store.product('waiwai').stockMilli, 6 * milli);
    expect(store.isSynced, isTrue);
    expect(store.today.totalPaisa, 0);
  });

  test('a cash sale is one batch: sale doc and stock decrement', () async {
    final (store, backend) = await openFirestoreShop(db: db, uid: uid, clock: () => now);
    addTearDown(backend.close);

    final sale = store.recordSale(
      cart: {'egg': 5 * milli, 'sugar': 500},
      method: PaymentMethod.cash,
      tenderedPaisa: rs(500),
    );
    await pumpEventQueue();

    final saleDoc = await doc('sales/${sale.id}');
    expect(saleDoc['totalPaisa'], rs(160));
    expect(saleDoc['changePaisa'], rs(340));
    expect(saleDoc['day'], '2026-10-18');
    expect(saleDoc['createdBy'], uid);
    expect(saleDoc['payments'], [
      {'method': 'cash', 'amountPaisa': rs(160)},
    ]);
    expect((await doc('products/egg'))['stockMilli'], 85 * milli);
    expect((await doc('products/sugar'))['stockMilli'], 2500);
    // The listener brought the same numbers back into the store.
    expect(store.product('egg').stockMilli, 85 * milli);
    expect(store.today.totalPaisa, rs(160));
  });

  test('udharo: new customer, sale on credit, then a payment', () async {
    final (store, backend) = await openFirestoreShop(db: db, uid: uid, clock: () => now);
    addTearDown(backend.close);

    // The fake interleaves the ops of un-awaited batches (real Firestore applies a
    // client's batches atomically and in order), so let each one land first.
    final c = store.addCustomer('श्याम दाइ');
    await pumpEventQueue();
    store.recordSale(cart: {'oil': milli}, method: PaymentMethod.udharo, customerId: c.id);
    await pumpEventQueue();
    store.recordPayment(c.id, rs(80));
    await pumpEventQueue();

    final cust = await doc('customers/${c.id}');
    expect(cust['name'], 'श्याम दाइ');
    expect(cust['balancePaisa'], rs(280 - 80));
    expect(cust['lastNote'], 'आज · तिर्यो रु 80');
    final ledger = await db.collection('shops/$uid/customers/${c.id}/ledger').get();
    expect(ledger.docs.map((d) => d['type']).toSet(), {'credit', 'payment'});
    expect(store.customer(c.id).balancePaisa, rs(200));
  });

  test('stock from a bill records the entry and increments stock', () async {
    final (store, backend) = await openFirestoreShop(db: db, uid: uid, clock: () => now);
    addTearDown(backend.close);

    store.addStock([
      StockLine(productId: 'waiwai', qtyMilli: 60 * milli, costPaisa: rs(18)),
    ], source: StockSource.billPhoto);
    await pumpEventQueue();

    expect((await doc('products/waiwai'))['stockMilli'], 66 * milli);
    final entries = await db.collection('shops/$uid/stockEntries').get();
    expect(entries.docs.single['source'], 'bill_photo');
    expect(entries.docs.single['totalPaisa'], rs(18 * 60));
  });

  test('changes from another device reach the store', () async {
    final (store, backend) = await openFirestoreShop(db: db, uid: uid, clock: () => now);
    addTearDown(backend.close);

    await db.doc('shops/$uid/products/rice').update({'stockMilli': 7 * milli});
    await db.doc('shops/$uid').update({'name': 'राम किराना पसल'});
    await pumpEventQueue();

    expect(store.product('rice').stockMilli, 7 * milli);
    expect(store.shopName, 'राम किराना पसल');
  });

  test('reopening reads everything back; yesterday\'s sales are not "today"', () async {
    var clock = now;
    final (first, b1) = await openFirestoreShop(db: db, uid: uid, clock: () => clock);
    first.recordSale(cart: {'rice': 2 * milli}, method: PaymentMethod.qr);
    await pumpEventQueue();
    b1.close();

    final (again, b2) = await openFirestoreShop(db: db, uid: uid, clock: () => clock);
    addTearDown(b2.close);
    expect(again.today.qrPaisa, rs(180));
    expect(again.product('rice').stockMilli, 58 * milli);
    b2.close();

    clock = now.add(const Duration(days: 1));
    final (tomorrow, b3) = await openFirestoreShop(db: db, uid: uid, clock: () => clock);
    addTearDown(b3.close);
    expect(tomorrow.today.totalPaisa, 0);
  });
}
