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

  List<Product> get products => List.unmodifiable(_products.values);
  List<Product> get favourites => _products.values.where((p) => p.isFavourite).toList();
  List<Product> get lowStock => _products.values.where((p) => p.isLow).toList();

  Product product(String id) => _products[id] ?? (throw ArgumentError('No product $id'));
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

  /// Stock arrived. Each product's cost becomes the newest cost paid for it.
  void addStock(List<StockLine> lines, {StockSource source = StockSource.manual}) {
    final problem = validate(AddStock(lines: lines));
    if (problem != null) throw ArgumentError(problem);
    _commit(_stockChange(lines, source));
  }

  ShopChange _stockChange(List<StockLine> lines, StockSource source, {List<Product> newProducts = const []}) {
    final deltas = <String, int>{};
    final costs = <String, int>{};
    for (final l in lines) {
      final p = _products[l.productId]!;
      _products[l.productId] = p.copyWith(stockMilli: p.stockMilli + l.qtyMilli, costPaisa: l.costPaisa);
      deltas[l.productId] = (deltas[l.productId] ?? 0) + l.qtyMilli;
      if (l.costPaisa != p.costPaisa) costs[l.productId] = l.costPaisa;
    }
    return ShopChange(
      newProducts: newProducts,
      stockDeltas: deltas,
      costUpdates: costs,
      stockEntry: StockEntry(
        id: _newId('stock'),
        source: source,
        lines: lines,
        totalPaisa: lines.fold(0, (sum, l) => sum + l.totalCostPaisa),
        createdAt: _now(),
      ),
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
  }) {
    final name = nameNe.trim();
    if (name.isEmpty) return 'सामानको नाम लेख्नुस्';
    if (_products.values.any((p) => p.nameNe.trim() == name)) return 'यो नामको सामान पहिल्यै छ';
    if (pricePaisa <= 0) return 'बेच्ने मूल्य लेख्नुस्';
    if (costPaisa < 0) return 'किनेको मूल्य मिलेन';
    if (barcode != null && barcode.isNotEmpty && productByBarcode(barcode) != null) {
      return 'यो बारकोड अर्को सामानमा छ';
    }
    if (packName != null && (packSizeMilli ?? 0) <= milli) return 'एक $packNameमा कति छ, लेख्नुस्';
    return null;
  }

  /// Adds a product to the catalog. Opening stock is recorded as a stock entry,
  /// so every unit of stock is explained by an entry.
  Product addProduct({
    required String nameNe,
    String nameEn = '',
    required int pricePaisa,
    required int costPaisa,
    required Unit unit,
    int openingStockMilli = 0,
    int? lowStockAtMilli,
    String? barcode,
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
      barcode: (barcode == null || barcode.isEmpty) ? null : barcode,
      packName: packName,
      packSizeMilli: packName == null ? null : packSizeMilli,
      labelKind: (barcode != null && isInStoreCode(barcode)) ? (labelKind ?? LabelKind.barcode) : null,
    );
    _products[p.id] = p;
    if (openingStockMilli > 0) {
      _commit(
        _stockChange(
          [StockLine(productId: p.id, qtyMilli: openingStockMilli, costPaisa: costPaisa)],
          StockSource.manual,
          newProducts: [p],
        ),
      );
    } else {
      _commit(ShopChange(newProducts: [p]));
    }
    return _products[p.id]!;
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
