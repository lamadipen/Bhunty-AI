import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/nepal_time.dart';
import '../data/demo_data.dart';
import '../data/models.dart';
import '../data/shop_backend.dart';
import '../data/shop_store.dart';
import 'firestore_mapping.dart';

/// Saves a `ShopStore`'s changes to `shops/{shopId}` and feeds remote changes back.
///
/// Every [ShopChange] becomes one `WriteBatch` using `FieldValue.increment` for
/// stock and balances. Batches are queued by Firestore while offline and the
/// local cache updates at once; `runTransaction` is never used because it
/// needs the server.
class FirestoreBackend implements ShopBackend {
  FirestoreBackend({required this.db, required this.shopId, required this.uid, this.onError});

  final FirebaseFirestore db;
  final String shopId;
  final String uid;

  /// Called when the server rejects a write (e.g. security rules). Firestore
  /// then rolls the local cache back and the listeners correct the store.
  final void Function(Object error)? onError;

  final List<StreamSubscription<Object?>> _subs = [];
  StreamSubscription<Object?>? _salesSub;
  Timer? _dayTimer;

  DocumentReference<Map<String, dynamic>> get shop => db.collection('shops').doc(shopId);
  CollectionReference<Map<String, dynamic>> get _products => shop.collection('products');
  CollectionReference<Map<String, dynamic>> get _customers => shop.collection('customers');
  CollectionReference<Map<String, dynamic>> get _sales => shop.collection('sales');

  @override
  String newId() => _sales.doc().id;

  @override
  void commit(ShopChange c) {
    final batch = db.batch();
    // New products first: later writes in this batch may update them.
    for (final p in c.newProducts) {
      batch.set(_products.doc(p.id), {
        ...productToMap(p),
        // After the seeded catalog, in the order they were added.
        'sortOrder': DateTime.now().millisecondsSinceEpoch,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    for (final p in c.updatedProducts) {
      final fields = productToMap(p)..remove('stockMilli');
      batch.set(_products.doc(p.id), {...fields, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    }
    final sale = c.sale;
    if (sale != null) {
      batch.set(_sales.doc(sale.id), {...saleToMap(sale, createdBy: uid), 'syncedAt': FieldValue.serverTimestamp()});
    }
    final productFields = <String, Map<String, Object?>>{};
    c.stockDeltas.forEach(
      (id, delta) => productFields.putIfAbsent(id, () => {})['stockMilli'] = FieldValue.increment(delta),
    );
    c.costUpdates.forEach((id, cost) => productFields.putIfAbsent(id, () => {})['costPaisa'] = cost);
    c.labelKinds.forEach((id, kind) => productFields.putIfAbsent(id, () => {})['labelKind'] = kind.name);
    // A batch at a new price moves the product's price (initial/manual travel with the product doc).
    for (final pc in c.priceChanges.where((pc) => pc.reason == PriceReason.stock)) {
      productFields.putIfAbsent(pc.productId, () => {})
        ..['pricePaisa'] = pc.newPricePaisa
        ..['priceSetAt'] = Timestamp.fromDate(pc.createdAt);
    }
    productFields.forEach((id, fields) => batch.update(_products.doc(id), fields));
    for (final nc in c.newCustomers) {
      batch.set(_customers.doc(nc.id), {...customerToMap(nc), 'createdAt': FieldValue.serverTimestamp()});
    }
    final customerFields = <String, Map<String, Object?>>{};
    for (final e in c.ledger) {
      batch.set(_customers.doc(e.customerId).collection('ledger').doc(e.id), ledgerToMap(e));
      final delta = e.type == LedgerType.credit ? e.amountPaisa : -e.amountPaisa;
      final fields = customerFields.putIfAbsent(e.customerId, () => {});
      fields['balancePaisa'] = FieldValue.increment(delta);
      fields['lastActivityAt'] = Timestamp.fromDate(e.createdAt);
    }
    c.customerNotes.forEach((id, note) => customerFields.putIfAbsent(id, () => {})['lastNote'] = note);
    customerFields.forEach((id, fields) => batch.set(_customers.doc(id), fields, SetOptions(merge: true)));
    final delivery = c.delivery;
    if (delivery != null) {
      batch.set(shop.collection('deliveries').doc(delivery.id), deliveryToMap(delivery, createdBy: uid));
    }
    for (final b in c.batches) {
      batch.set(shop.collection('batches').doc(b.id), batchToMap(b, createdBy: uid));
    }
    for (final pc in c.priceChanges) {
      batch.set(shop.collection('priceChanges').doc(pc.id), priceChangeToMap(pc, createdBy: uid));
    }
    // Not awaited: offline, this future only completes after the next sync.
    unawaited(
      batch.commit().catchError((Object e) {
        debugPrint('Bhunte: write rejected: $e');
        onError?.call(e);
      }),
    );
  }

  /// Starts listening and keeps [store] in step with Firestore (including the
  /// offline cache). Completes once products, customers and today's sales
  /// have each been delivered once.
  Future<void> attach(ShopStore store, {DateTime Function() clock = DateTime.now}) async {
    final products = Completer<void>(), customers = Completer<void>(), sales = Completer<void>();
    void done(Completer<void> c) => c.isCompleted ? null : c.complete();
    void fail(Completer<void> c, Object e) =>
        c.isCompleted ? debugPrint('Bhunte: listen error: $e') : c.completeError(e);

    _subs.add(
      shop.snapshots().listen((s) {
        final name = s.data()?['name'] as String?;
        if (name != null) store.replaceFromRemote(shopName: name);
      }),
    );
    _subs.add(
      _products.snapshots().listen((q) {
        // Firestore returns documents by id; keep the tap grid in the shop's own order.
        final docs = [...q.docs]..sort(compareProductDocs);
        store.replaceFromRemote(products: [for (final d in docs) productFromMap(d.id, d.data())]);
        done(products);
      }, onError: (Object e) => fail(products, e)),
    );
    _subs.add(
      _customers.snapshots().listen((q) {
        store.replaceFromRemote(customers: [for (final d in q.docs) customerFromMap(d.id, d.data())]);
        done(customers);
      }, onError: (Object e) => fail(customers, e)),
    );

    var day = nepalDayKey(clock());
    void listenSales() {
      _salesSub?.cancel();
      _salesSub = _sales.where('day', isEqualTo: day).snapshots().listen((q) {
        store.replaceFromRemote(sales: [for (final d in q.docs) saleFromMap(d.id, d.data())]);
        done(sales);
      }, onError: (Object e) => fail(sales, e));
    }

    listenSales();
    // Roll "today" over at Nepal midnight while the app stays open.
    _dayTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = nepalDayKey(clock());
      if (now != day) {
        day = now;
        listenSales();
      }
    });

    await Future.wait([products.future, customers.future, sales.future]);
  }

  void close() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _salesSub?.cancel();
    _dayTimer?.cancel();
  }
}

/// Opens (and on first login creates) the signed-in owner's shop.
///
/// For now one owner has one shop and its id is the owner's uid; helper
/// accounts will need a membership list (see docs/review.md, roles).
Future<(ShopStore, FirestoreBackend)> openFirestoreShop({
  required FirebaseFirestore db,
  required String uid,
  DateTime Function()? clock,
  void Function(Object error)? onError,
}) async {
  final backend = FirestoreBackend(db: db, shopId: uid, uid: uid, onError: onError);
  final snap = await backend.shop.get();
  if (!snap.exists) {
    // First login is online (OTP needs the network), so this create is awaited.
    final batch = db.batch();
    batch.set(backend.shop, {
      'name': 'मेरो पसल',
      'ownerUid': uid,
      'currency': 'NPR',
      'createdAt': FieldValue.serverTimestamp(),
    });
    final products = demoProducts();
    for (var i = 0; i < products.length; i++) {
      batch.set(backend.shop.collection('products').doc(products[i].id), {
        ...productToMap(products[i]),
        'sortOrder': i,
      });
    }
    await batch.commit();
  }
  final store = ShopStore(
    shopName: snap.data()?['name'] as String? ?? 'मेरो पसल',
    products: const [],
    customers: const [],
    clock: clock,
    backend: backend,
  );
  await backend.attach(store, clock: clock ?? DateTime.now);
  return (store, backend);
}
