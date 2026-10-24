import '../core/barcode.dart';
import 'models.dart';

/// How stock came in. Stored in Firestore as [wire].
enum StockSource {
  opening('opening'),
  manual('manual'),
  billPhoto('bill_photo'),
  productPhoto('product_photo'),
  voice('voice');

  const StockSource(this.wire);

  final String wire;
}

/// One bill, or one save on the stock screen. Groups the batches that came
/// in together. See docs/product-addition.md.
class Delivery {
  const Delivery({
    required this.id,
    required this.source,
    required this.totalCostPaisa,
    required this.batchCount,
    required this.createdAt,
    this.supplierName,
    this.supplierPhone,
    this.billNo,
  });

  final String id;
  final StockSource source;
  final int totalCostPaisa;
  final int batchCount;
  final DateTime createdAt;

  /// Optional; suppliers are identified by phone number when given.
  final String? supplierName;
  final String? supplierPhone;
  final String? billNo;
}

/// One product's stock arriving in one delivery, with its own cost and sale
/// price. Never edited or deleted (R2, R8).
class Batch {
  const Batch({
    required this.id,
    required this.deliveryId,
    required this.productId,
    required this.productName,
    required this.qtyMilli,
    required this.unitCostPaisa,
    required this.totalCostPaisa,
    required this.salePricePaisa,
    required this.source,
    required this.createdAt,
    this.packName,
    this.packSizeMilli,
    this.packsMilli,
  });

  final String id;
  final String deliveryId;
  final String productId;

  /// Copied so reports keep the name the product had at the time.
  final String productName;

  /// Selling units added.
  final int qtyMilli;

  /// Set when it was entered in packs (e.g. 2 कार्टुन × 30).
  final String? packName;
  final int? packSizeMilli;
  final int? packsMilli;

  final int unitCostPaisa;

  /// Exactly as on the bill.
  final int totalCostPaisa;

  /// The sale price in effect after this batch.
  final int salePricePaisa;
  final StockSource source;
  final DateTime createdAt;

  bool get enteredAsPack => packsMilli != null;

  /// Saved without a cost (S-11): flagged for follow-up in reports.
  bool get costMissing => totalCostPaisa == 0;
}

enum PriceReason { initial, stock, manual }

/// Every time a product's sale price is set or changed. The newest one is the
/// product's price (R1, R6).
class PriceChange {
  const PriceChange({
    required this.id,
    required this.productId,
    required this.newPricePaisa,
    required this.reason,
    required this.createdAt,
    this.oldPricePaisa,
    this.batchId,
  });

  final String id;
  final String productId;
  final int? oldPricePaisa;
  final int newPricePaisa;
  final PriceReason reason;
  final String? batchId;
  final DateTime createdAt;
}

/// Everything one user action changed. `ShopStore` has already done the
/// arithmetic; a backend only persists it, as one atomic write.
class ShopChange {
  const ShopChange({
    this.sale,
    this.stockDeltas = const {},
    this.ledger = const [],
    this.customerNotes = const {},
    this.newCustomers = const [],
    this.newProducts = const [],
    this.costUpdates = const {},
    this.labelKinds = const {},
    this.updatedProducts = const [],
    this.delivery,
    this.batches = const [],
    this.priceChanges = const [],
    this.images = const {},
  });

  final Sale? sale;

  /// productId → change in stock, in milli-units (negative for a sale).
  final Map<String, int> stockDeltas;

  /// Each entry moves its customer's balance: credit up, payment down.
  final List<LedgerEntry> ledger;

  /// customerId → new "last activity" line for the udharo list.
  final Map<String, String> customerNotes;
  final List<Customer> newCustomers;

  /// Created with zero stock; opening stock arrives through [stockDeltas].
  final List<Product> newProducts;

  /// productId → unit cost of its newest batch.
  final Map<String, int> costUpdates;

  /// productId → how its own label is printed.
  final Map<String, LabelKind> labelKinds;

  /// Edited details (name, price, code, hidden…). Their stock must not be
  /// written from here: other devices may have changed it.
  final List<Product> updatedProducts;

  final Delivery? delivery;
  final List<Batch> batches;

  /// A `stock` change also moves its product's price; `initial` and `manual`
  /// changes travel with [newProducts] / [updatedProducts].
  final List<PriceChange> priceChanges;

  /// productId → its new thumbnail, or null to remove it.
  final Map<String, ProductImage?> images;
}

/// Where a `ShopStore` saves its changes. None (the demo) keeps everything in memory.
abstract interface class ShopBackend {
  /// A new document id, unique across devices.
  String newId();

  /// Persists [change] as one atomic write. Must not wait for the network:
  /// offline writes are queued and synced later.
  void commit(ShopChange change);
}
