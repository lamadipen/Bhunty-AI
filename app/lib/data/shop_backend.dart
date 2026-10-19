import 'models.dart';

enum StockSource {
  billPhoto('bill_photo'),
  productPhoto('product_photo'),
  voice('voice'),
  manual('manual');

  const StockSource(this.wire);

  /// Value stored in Firestore.
  final String wire;
}

class StockEntry {
  const StockEntry({
    required this.id,
    required this.source,
    required this.lines,
    required this.totalPaisa,
    required this.createdAt,
  });

  final String id;
  final StockSource source;
  final List<StockLine> lines;
  final int totalPaisa;
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
    this.stockEntry,
  });

  final Sale? sale;

  /// productId → change in stock, in milli-units (negative for a sale).
  final Map<String, int> stockDeltas;

  /// Each entry moves its customer's balance: credit up, payment down.
  final List<LedgerEntry> ledger;

  /// customerId → new "last activity" line for the udharo list.
  final Map<String, String> customerNotes;
  final List<Customer> newCustomers;
  final StockEntry? stockEntry;
}

/// Where a `ShopStore` saves its changes. None (the demo) keeps everything in memory.
abstract interface class ShopBackend {
  /// A new document id, unique across devices.
  String newId();

  /// Persists [change] as one atomic write. Must not wait for the network:
  /// offline writes are queued and synced later.
  void commit(ShopChange change);
}
