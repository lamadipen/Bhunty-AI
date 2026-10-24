import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/barcode.dart';
import '../core/cash.dart';
import '../core/money.dart';
import '../core/nepal_time.dart';
import '../core/qty.dart';
import 'models.dart';
import 'proposed_action.dart';
import 'shop_backend.dart';

/// The shop's records and the only place that changes them.
///
/// All money and stock arithmetic happens here, in code (principle 3).
/// Each write updates this in-memory copy at once (so the UI never waits) and
/// hands a [ShopChange] to the [ShopBackend], which saves it as one batched
/// write. With no backend (the demo) the data lives only in memory.
/// A backend that listens for remote changes feeds them in with [replaceFromRemote].
class ShopStore extends ChangeNotifier {
  ShopStore({
    required String shopName,
    required List<Product> products,
    required List<Customer> customers,
    List<Sale> sales = const [],
    DateTime Function()? clock,
    ShopBackend? backend,
  }) : _shopName = shopName,
       _now = clock ?? DateTime.now,
       _backend = backend,
       _products = {for (final p in products) p.id: p},
       _customers = {for (final c in customers) c.id: c},
       _sales = [...sales];

  String _shopName;
  final DateTime Function() _now;
  final ShopBackend? _backend;
  final Map<String, Product> _products;
  final Map<String, Customer> _customers;
  final List<Sale> _sales;
  final List<LedgerEntry> _ledger = [];

  // Stock and price history recorded on this device (Firestore keeps the full history).
  final List<Delivery> _deliveries = [];
  final List<Batch> _batches = [];
  final List<PriceChange> _priceChanges = [];
  int _seq = 0;

  String _newId(String prefix) => _backend?.newId() ?? '$prefix-${_now().microsecondsSinceEpoch}-${++_seq}';

  String get shopName => _shopName;

  /// True when changes are saved to a backend (Firebase), false for the in-memory demo.
  bool get isSynced => _backend != null;

  /// Replaces cached data with what the backend reports. Pass only what changed.
  void replaceFromRemote({String? shopName, List<Product>? products, List<Customer>? customers, List<Sale>? sales}) {
    if (shopName != null) _shopName = shopName;
    if (products != null) {
      _products
        ..clear()
        ..addAll({for (final p in products) p.id: p});
    }
    if (customers != null) {
      _customers
        ..clear()
        ..addAll({for (final c in customers) c.id: c});
    }
    if (sales != null) {
      _sales
        ..clear()
        ..addAll(sales);
    }
    notifyListeners();
  }

  // ---- Reads ----

  Iterable<Product> get _visible => _products.values.where((p) => !p.archived);

  /// The catalog the shop works with; hidden products are left out.
  List<Product> get products => List.unmodifiable(_visible);
  List<Product> get favourites => _visible.where((p) => p.isFavourite).toList();
  List<Product> get lowStock => _visible.where((p) => p.isLow).toList();
  List<Product> get archivedProducts => _products.values.where((p) => p.archived).toList();

  Product product(String id) => _products[id] ?? (throw ArgumentError('No product $id'));

  /// Any product with this code, hidden ones too (callers decide what to do).
  Product? productByBarcode(String code) {
    for (final p in _products.values) {
      if (p.barcode == code) return p;
    }
    return null;
  }

  /// Highest balance first, like the udharo book.
  List<Customer> get customers => _customers.values.toList()..sort((a, b) => b.balancePaisa.compareTo(a.balancePaisa));
  Customer customer(String id) => _customers[id] ?? (throw ArgumentError('No customer $id'));

  int get totalUdharoPaisa => _customers.values.fold(0, (sum, c) => sum + c.balancePaisa);
  int get customersOwing => _customers.values.where((c) => c.balancePaisa > 0).length;

  List<Sale> get sales => List.unmodifiable(_sales);
  List<LedgerEntry> get ledger => List.unmodifiable(_ledger);
  List<Delivery> get deliveries => List.unmodifiable(_deliveries);

  /// Oldest first.
  List<Batch> batchesFor(String productId) => _batches.where((b) => b.productId == productId).toList();
  List<PriceChange> priceHistory(String productId) => _priceChanges.where((c) => c.productId == productId).toList();

  int cartTotal(Map<String, int> cart) =>
      cart.entries.fold(0, (sum, e) => sum + lineTotal(product(e.key).pricePaisa, e.value));

  /// Computed from today's sales on the device, so it is right offline.
  TodayStats get today {
    final now = _now();
    var total = 0, cash = 0, qr = 0, udharo = 0, count = 0;
    final qty = <String, int>{};
    for (final s in _sales) {
      if (!isSameNepalDay(s.createdAt, now)) continue;
      count++;
      total += s.totalPaisa;
      switch (s.method) {
        case PaymentMethod.cash:
          cash += s.totalPaisa;
        case PaymentMethod.qr:
          qr += s.totalPaisa;
        case PaymentMethod.udharo:
          udharo += s.totalPaisa;
      }
      for (final l in s.lines) {
        qty[l.productId] = (qty[l.productId] ?? 0) + l.qtyMilli;
      }
    }
    final top =
        qty.entries.where((e) => _products.containsKey(e.key)).map((e) => TopItem(_products[e.key]!, e.value)).toList()
          ..sort((a, b) => b.qtyMilli.compareTo(a.qtyMilli));
    return TodayStats(
      totalPaisa: total,
      cashPaisa: cash,
      qrPaisa: qr,
      udharoPaisa: udharo,
      saleCount: count,
      topItems: top,
    );
  }

  // ---- Validation (the same checks the Cloud Function runs on tool calls) ----

  /// Nepali reason the action cannot be applied, or null if it is valid.
  String? validate(ProposedAction action) => switch (action) {
    AddToCart(:final productId, :final qtyMilli) =>
      !_products.containsKey(productId)
          ? 'सामान भेटिएन'
          : qtyMilli <= 0
          ? 'मात्रा मिलेन'
          : null,
    RecordCredit(:final customerId, :final amountPaisa) =>
      !_customers.containsKey(customerId)
          ? 'ग्राहक भेटिएन'
          : amountPaisa <= 0
          ? 'रकम मिलेन'
          : null,
    RecordPayment(:final customerId, :final amountPaisa) =>
      !_customers.containsKey(customerId)
          ? 'ग्राहक भेटिएन'
          : amountPaisa <= 0
          ? 'रकम मिलेन'
          : amountPaisa > _customers[customerId]!.balancePaisa
          ? 'बाँकी भन्दा बढी भयो'
          : null,
    AddStock(:final lines) =>
      lines.isEmpty
          ? 'कुनै सामान छैन'
          : lines.any((l) => !_products.containsKey(l.productId) || l.qtyMilli <= 0 || l.costPaisa < 0)
          ? 'सामान वा मात्रा मिलेन'
          : null,
  };

  /// Commits a confirmed action. Cart actions belong to the sell screen.
  void apply(ProposedAction action) {
    final problem = validate(action);
    if (problem != null) throw ArgumentError(problem);
    switch (action) {
      case AddToCart():
        throw StateError('Cart actions are applied by the sell screen');
      case RecordCredit(:final customerId, :final amountPaisa):
        recordCredit(customerId, amountPaisa);
      case RecordPayment(:final customerId, :final amountPaisa):
        recordPayment(customerId, amountPaisa);
      case AddStock(:final lines):
        addStock(lines, source: StockSource.voice);
    }
  }

  // ---- Writes ----

  /// Records a sale: one sale record, stock down per line, and for udharo a
  /// ledger credit — together, as one batch.
  Sale recordSale({
    required Map<String, int> cart,
    required PaymentMethod method,
    int? tenderedPaisa,
    String? customerId,
  }) {
    if (cart.isEmpty || cart.values.any((q) => q <= 0)) {
      throw ArgumentError('Cart is empty or has a zero quantity');
    }
    if (method == PaymentMethod.udharo && !_customers.containsKey(customerId)) {
      throw ArgumentError('Udharo sale needs a customer');
    }
    final lines = [
      for (final e in cart.entries)
        SaleLine(
          productId: e.key,
          name: product(e.key).nameNe,
          qtyMilli: e.value,
          pricePaisa: product(e.key).pricePaisa,
          lineTotalPaisa: lineTotal(product(e.key).pricePaisa, e.value),
        ),
    ];
    final total = lines.fold(0, (sum, l) => sum + l.lineTotalPaisa);
    if (method == PaymentMethod.cash && tenderedPaisa != null && tenderedPaisa < total) {
      throw ArgumentError('Tendered less than total');
    }
    final sale = Sale(
      id: _newId('sale'),
      lines: lines,
      totalPaisa: total,
      method: method,
      createdAt: _now(),
      tenderedPaisa: method == PaymentMethod.cash ? (tenderedPaisa ?? total) : null,
      changePaisa: method == PaymentMethod.cash
          ? changeDue(tenderedPaisa: tenderedPaisa ?? total, totalPaisa: total)
          : null,
      customerId: method == PaymentMethod.udharo ? customerId : null,
    );
    _sales.add(sale);
    for (final l in lines) {
      final p = _products[l.productId]!;
      // Stock may go below zero when the count was wrong; that is a signal, not an error.
      _products[l.productId] = p.withStock(p.stockMilli - l.qtyMilli);
    }
    final ledger = method == PaymentMethod.udharo
        ? _addLedger(customerId!, LedgerType.credit, total, saleId: sale.id)
        : null;
    _commit(
      ShopChange(
        sale: sale,
        stockDeltas: {for (final l in lines) l.productId: -l.qtyMilli},
        ledger: [?ledger],
        customerNotes: {if (ledger != null) ledger.customerId: _customers[ledger.customerId]!.lastNote},
      ),
    );
    return sale;
  }

  void recordCredit(String customerId, int amountPaisa) {
    final problem = validate(RecordCredit(customerId: customerId, amountPaisa: amountPaisa));
    if (problem != null) throw ArgumentError(problem);
    _commitLedger(_addLedger(customerId, LedgerType.credit, amountPaisa));
  }

  void recordPayment(String customerId, int amountPaisa) {
    final problem = validate(RecordPayment(customerId: customerId, amountPaisa: amountPaisa));
    if (problem != null) throw ArgumentError(problem);
    _commitLedger(_addLedger(customerId, LedgerType.payment, amountPaisa));
  }

  /// Nepali reason these stock lines can't be saved, or null.
  String? validateStock(List<StockLine> lines) =>
      validate(AddStock(lines: lines)) ??
      (lines.any((l) => l.salePricePaisa != null && l.salePricePaisa! <= 0) ? 'बेच्ने मूल्य मिलेन' : null) ??
      (lines.any((l) => l.totalCostPaisa < 0) ? 'किनेको मूल्य मिलेन' : null);

  /// Stock arrived: one delivery, one batch per line, each with its own cost
  /// and sale price; a batch at a new price changes the product's price.
  /// One write (docs/product-addition.md, R2–R3).
  Delivery addStock(
    List<StockLine> lines, {
    StockSource source = StockSource.manual,
    String? supplierName,
    String? supplierPhone,
    String? billNo,
  }) {
    final problem = validateStock(lines);
    if (problem != null) throw ArgumentError(problem);
    final change = _stockChange(
      lines,
      source,
      supplierName: supplierName,
      supplierPhone: supplierPhone,
      billNo: billNo,
    );
    _commit(change);
    return change.delivery!;
  }

  ShopChange _stockChange(
    List<StockLine> lines,
    StockSource source, {
    List<Product> newProducts = const [],
    List<PriceChange> extraPriceChanges = const [],
    String? supplierName,
    String? supplierPhone,
    String? billNo,
  }) {
    final now = _now();
    final deliveryId = _newId('delivery');
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    final deltas = <String, int>{};
    final costs = <String, int>{};
    final batches = <Batch>[];
    final prices = <PriceChange>[...extraPriceChanges];
    for (final l in lines) {
      final p = _products[l.productId]!;
      final salePrice = l.salePricePaisa ?? p.pricePaisa;
      final batch = Batch(
        id: _newId('batch'),
        deliveryId: deliveryId,
        productId: p.id,
        productName: p.nameNe,
        qtyMilli: l.qtyMilli,
        packName: l.packsMilli == null ? null : p.packName,
        packSizeMilli: l.packsMilli == null ? null : p.packSizeMilli,
        packsMilli: l.packsMilli,
        unitCostPaisa: l.costPaisa,
        totalCostPaisa: l.totalCostPaisa,
        salePricePaisa: salePrice,
        source: source,
        createdAt: now,
      );
      batches.add(batch);
      var updated = p.copyWith(stockMilli: p.stockMilli + l.qtyMilli, costPaisa: l.costPaisa);
      if (salePrice != p.pricePaisa) {
        prices.add(
          PriceChange(
            id: _newId('price'),
            productId: p.id,
            oldPricePaisa: p.pricePaisa,
            newPricePaisa: salePrice,
            reason: PriceReason.stock,
            batchId: batch.id,
            createdAt: now,
          ),
        );
        updated = updated.copyWith(pricePaisa: salePrice, priceSetAt: now);
      }
      _products[p.id] = updated;
      deltas[p.id] = (deltas[p.id] ?? 0) + l.qtyMilli;
      costs[p.id] = l.costPaisa;
    }
    final delivery = Delivery(
      id: deliveryId,
      source: source,
      totalCostPaisa: batches.fold(0, (sum, b) => sum + b.totalCostPaisa),
      batchCount: batches.length,
      createdAt: now,
      supplierName: clean(supplierName),
      supplierPhone: clean(supplierPhone),
      billNo: clean(billNo),
    );
    _deliveries.add(delivery);
    _batches.addAll(batches);
    _priceChanges.addAll(prices);
    return ShopChange(
      newProducts: newProducts,
      stockDeltas: deltas,
      costUpdates: costs,
      delivery: delivery,
      batches: batches,
      priceChanges: prices,
    );
  }

  /// Remembers whether this product's own label prints as a barcode or a QR code.
  void setLabelKind(String productId, LabelKind kind) {
    final p = product(productId);
    if (!p.hasOwnCode || p.labelKind == kind) return;
    _products[productId] = p.copyWith(labelKind: kind);
    _commit(ShopChange(labelKinds: {productId: kind}));
  }

  /// A new in-store code that no product in this shop uses yet.
  String newInStoreCode({Random? random}) =>
      generateInStoreEan13(taken: {for (final p in _products.values) ?p.barcode}, random: random);

  /// Nepali reason a new product can't be added, or null.
  String? validateNewProduct({
    required String nameNe,
    required int pricePaisa,
    required int costPaisa,
    String? barcode,
    String? packName,
    int? packSizeMilli,
  }) => validateProduct(
    nameNe: nameNe,
    pricePaisa: pricePaisa,
    costPaisa: costPaisa,
    barcode: barcode,
    packName: packName,
    packSizeMilli: packSizeMilli,
  );

  /// Checks a new or edited product ([excludeId] = the product being edited).
  String? validateProduct({
    String? excludeId,
    required String nameNe,
    required int pricePaisa,
    required int costPaisa,
    String? barcode,
    String? packName,
    int? packSizeMilli,
  }) {
    final name = nameNe.trim();
    if (name.isEmpty) return 'सामानको नाम लेख्नुस्';
    for (final p in _products.values) {
      if (p.id != excludeId && p.nameNe.trim() == name) {
        return p.archived
            ? 'यो नामको सामान लुकाइएको छ — "लुकाइएका सामान" बाट फेरि देखाउनुस्'
            : 'यो नामको सामान पहिल्यै छ';
      }
    }
    if (pricePaisa <= 0) return 'बेच्ने मूल्य लेख्नुस्';
    if (costPaisa < 0) return 'किनेको मूल्य मिलेन';
    if (barcode != null && barcode.isNotEmpty) {
      final other = productByBarcode(barcode);
      if (other != null && other.id != excludeId) {
        return other.archived ? 'यो कोड लुकाइएको "${other.nameNe}" मा छ' : 'यो बारकोड "${other.nameNe}" मा छ';
      }
    }
    if (packName != null && (packSizeMilli ?? 0) <= milli) return 'एक $packNameमा कति छ, लेख्नुस्';
    return null;
  }

  /// Adds a product to the catalog with its first price change (`initial`).
  /// Opening stock is its first batch (source `opening`), so every unit of
  /// stock is explained by a batch. [costPaisa] is per selling unit; with
  /// [openingPacksMilli] the opening stock was counted in packs.
  Product addProduct({
    required String nameNe,
    String nameEn = '',
    required int pricePaisa,
    required int costPaisa,
    required Unit unit,
    int openingStockMilli = 0,
    int? openingPacksMilli,
    int? openingTotalCostPaisa,
    int? lowStockAtMilli,
    String? barcode,
    bool ownCode = false,
    String? packName,
    int? packSizeMilli,
    LabelKind? labelKind,
  }) {
    final problem = validateNewProduct(
      nameNe: nameNe,
      pricePaisa: pricePaisa,
      costPaisa: costPaisa,
      barcode: barcode,
      packName: packName,
      packSizeMilli: packSizeMilli,
    );
    if (problem != null) throw ArgumentError(problem);
    final name = nameNe.trim();
    final look = _tilePalette[_products.length % _tilePalette.length];
    final code = (barcode == null || barcode.isEmpty) ? null : barcode;
    final own = ownCode && code != null;
    final p = Product(
      id: _newId('prod'),
      nameNe: name,
      nameEn: nameEn.trim(),
      pricePaisa: pricePaisa,
      costPaisa: costPaisa,
      unit: unit,
      stockMilli: 0,
      lowStockAtMilli: lowStockAtMilli ?? 0,
      letter: String.fromCharCodes(name.runes.take(2)),
      tileBg: look.$1,
      tileInk: look.$2,
      barcode: code,
      ownCode: own,
      packName: packName,
      packSizeMilli: packName == null ? null : packSizeMilli,
      labelKind: own ? (labelKind ?? LabelKind.barcode) : null,
      priceSetAt: _now(),
    );
    _products[p.id] = p;
    PriceChange initial({String? batchId}) => PriceChange(
      id: _newId('price'),
      productId: p.id,
      newPricePaisa: pricePaisa,
      reason: PriceReason.initial,
      batchId: batchId,
      createdAt: p.priceSetAt!,
    );
    if (openingStockMilli > 0) {
      final change = _stockChange(
        [
          StockLine(
            productId: p.id,
            qtyMilli: openingStockMilli,
            costPaisa: costPaisa,
            totalCostPaisa: openingTotalCostPaisa,
            packsMilli: packName == null ? null : openingPacksMilli,
          ),
        ],
        StockSource.opening,
        newProducts: [p],
      );
      // The initial price is linked to the opening batch.
      final first = initial(batchId: change.batches.single.id);
      _priceChanges.add(first);
      _commit(
        ShopChange(
          newProducts: change.newProducts,
          stockDeltas: change.stockDeltas,
          costUpdates: change.costUpdates,
          delivery: change.delivery,
          batches: change.batches,
          priceChanges: [first],
        ),
      );
    } else {
      final first = initial();
      _priceChanges.add(first);
      _commit(ShopChange(newProducts: [p], priceChanges: [first]));
    }
    return _products[p.id]!;
  }

  /// Saves edits to a product's details. Stock is never edited here: it only
  /// changes through sales and stock entries.
  Product updateProduct(
    String id, {
    required String nameNe,
    String nameEn = '',
    required int pricePaisa,
    required int costPaisa,
    required Unit unit,
    int? lowStockAtMilli,
    String? barcode,
    bool ownCode = false,
    String? packName,
    int? packSizeMilli,
    LabelKind? labelKind,
  }) {
    final old = product(id);
    final problem =
        validateProduct(
          excludeId: id,
          nameNe: nameNe,
          pricePaisa: pricePaisa,
          costPaisa: costPaisa,
          barcode: barcode,
          packName: packName,
          packSizeMilli: packSizeMilli,
        ) ??
        (unit != old.unit && !canChangeUnit(old) ? 'स्टक भएपछि एकाइ बदल्न मिल्दैन' : null);
    if (problem != null) throw ArgumentError(problem);
    final name = nameNe.trim();
    final code = (barcode == null || barcode.isEmpty) ? null : barcode;
    final own = ownCode && code != null;
    final p = Product(
      id: id,
      nameNe: name,
      nameEn: nameEn.trim(),
      pricePaisa: pricePaisa,
      costPaisa: costPaisa,
      unit: unit,
      stockMilli: old.stockMilli,
      lowStockAtMilli: lowStockAtMilli ?? 0,
      letter: name == old.nameNe ? old.letter : String.fromCharCodes(name.runes.take(2)),
      tileBg: old.tileBg,
      tileInk: old.tileInk,
      barcode: code,
      ownCode: own,
      isFavourite: old.isFavourite,
      packName: packName,
      packSizeMilli: packName == null ? null : packSizeMilli,
      labelKind: own ? (labelKind ?? old.labelKind ?? LabelKind.barcode) : null,
      archived: old.archived,
      priceSetAt: pricePaisa == old.pricePaisa ? old.priceSetAt : _now(),
    );
    _products[id] = p;
    final changes = <PriceChange>[
      if (pricePaisa != old.pricePaisa)
        PriceChange(
          id: _newId('price'),
          productId: id,
          oldPricePaisa: old.pricePaisa,
          newPricePaisa: pricePaisa,
          reason: PriceReason.manual,
          createdAt: p.priceSetAt!,
        ),
    ];
    _priceChanges.addAll(changes);
    _commit(ShopChange(updatedProducts: [p], priceChanges: changes));
    return p;
  }

  /// The unit can change only while there is no stock (it would change what the count means).
  bool canChangeUnit(Product p) => p.stockMilli == 0;

  /// Hides a product from grids and scanning, or shows it again. Nothing is deleted.
  void setArchived(String id, bool archived) {
    final old = product(id);
    if (old.archived == archived) return;
    final p = Product(
      id: old.id,
      nameNe: old.nameNe,
      nameEn: old.nameEn,
      pricePaisa: old.pricePaisa,
      costPaisa: old.costPaisa,
      unit: old.unit,
      stockMilli: old.stockMilli,
      lowStockAtMilli: old.lowStockAtMilli,
      letter: old.letter,
      tileBg: old.tileBg,
      tileInk: old.tileInk,
      barcode: old.barcode,
      ownCode: old.ownCode,
      isFavourite: old.isFavourite,
      packName: old.packName,
      packSizeMilli: old.packSizeMilli,
      labelKind: old.labelKind,
      archived: archived,
      priceSetAt: old.priceSetAt,
    );
    _products[id] = p;
    _commit(ShopChange(updatedProducts: [p]));
  }

  Customer addCustomer(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Name is empty');
    final c = Customer(
      id: _newId('cust'),
      name: trimmed,
      initial: String.fromCharCodes(trimmed.runes.take(2)),
      balancePaisa: 0,
      lastNote: 'नयाँ ग्राहक',
    );
    _customers[c.id] = c;
    _commit(ShopChange(newCustomers: [c]));
    return c;
  }

  /// Updates the cached balance and returns the entry; the caller commits it.
  LedgerEntry _addLedger(String customerId, LedgerType type, int amountPaisa, {String? saleId}) {
    final c = _customers[customerId]!;
    final balance = type == LedgerType.credit ? c.balancePaisa + amountPaisa : c.balancePaisa - amountPaisa;
    final entry = LedgerEntry(
      id: _newId('ledger'),
      customerId: customerId,
      type: type,
      amountPaisa: amountPaisa,
      createdAt: _now(),
      saleId: saleId,
    );
    _ledger.add(entry);
    _customers[customerId] = c.copyWith(
      balancePaisa: balance,
      lastNote: balance == 0
          ? 'सबै तिर्यो'
          : 'आज · ${type == LedgerType.credit ? 'उधारो' : 'तिर्यो'} ${formatRs(amountPaisa)}',
    );
    return entry;
  }

  void _commitLedger(LedgerEntry e) =>
      _commit(ShopChange(ledger: [e], customerNotes: {e.customerId: _customers[e.customerId]!.lastNote}));

  void _commit(ShopChange change) {
    _backend?.commit(change);
    notifyListeners();
  }
}

/// Tile colours for new products (background, ink), from the design palette.
const _tilePalette = [
  (0xFFF6E3B4, 0xFF6B4A00),
  (0xFFDCE8F5, 0xFF1E3E73),
  (0xFFE3F0E8, 0xFF14512F),
  (0xFFF5DDE6, 0xFF7A1F45),
  (0xFFEAE6F4, 0xFF3E2F73),
  (0xFFF3E7DA, 0xFF6A3F17),
];
