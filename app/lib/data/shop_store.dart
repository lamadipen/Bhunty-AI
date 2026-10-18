import 'package:flutter/foundation.dart';

import '../core/cash.dart';
import '../core/money.dart';
import '../core/nepal_time.dart';
import 'models.dart';
import 'proposed_action.dart';

/// The shop's records and the only place that changes them.
///
/// All money and stock arithmetic happens here, in code (principle 3).
/// This in-memory version runs the demo; a Firestore-backed version will keep
/// the same methods and write each one as a single batched write (see
/// docs/architecture.md — transactions do not work offline).
class ShopStore extends ChangeNotifier {
  ShopStore({
    required this.shopName,
    required List<Product> products,
    required List<Customer> customers,
    List<Sale> sales = const [],
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now,
       _products = {for (final p in products) p.id: p},
       _customers = {for (final c in customers) c.id: c},
       _sales = [...sales];

  final String shopName;
  final DateTime Function() _now;
  final Map<String, Product> _products;
  final Map<String, Customer> _customers;
  final List<Sale> _sales;
  final List<LedgerEntry> _ledger = [];
  int _seq = 0;

  String _newId(String prefix) => '$prefix-${_now().microsecondsSinceEpoch}-${++_seq}';

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
        addStock(lines);
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
    if (method == PaymentMethod.udharo) {
      _addLedger(customerId!, LedgerType.credit, total, saleId: sale.id, notify: false);
    }
    notifyListeners();
    return sale;
  }

  void recordCredit(String customerId, int amountPaisa) {
    final problem = validate(RecordCredit(customerId: customerId, amountPaisa: amountPaisa));
    if (problem != null) throw ArgumentError(problem);
    _addLedger(customerId, LedgerType.credit, amountPaisa);
  }

  void recordPayment(String customerId, int amountPaisa) {
    final problem = validate(RecordPayment(customerId: customerId, amountPaisa: amountPaisa));
    if (problem != null) throw ArgumentError(problem);
    _addLedger(customerId, LedgerType.payment, amountPaisa);
  }

  void addStock(List<StockLine> lines) {
    final problem = validate(AddStock(lines: lines));
    if (problem != null) throw ArgumentError(problem);
    for (final l in lines) {
      final p = _products[l.productId]!;
      _products[l.productId] = p.withStock(p.stockMilli + l.qtyMilli);
    }
    notifyListeners();
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
    notifyListeners();
    return c;
  }

  void _addLedger(String customerId, LedgerType type, int amountPaisa, {String? saleId, bool notify = true}) {
    final c = _customers[customerId]!;
    final balance = type == LedgerType.credit ? c.balancePaisa + amountPaisa : c.balancePaisa - amountPaisa;
    _ledger.add(
      LedgerEntry(
        id: _newId('ledger'),
        customerId: customerId,
        type: type,
        amountPaisa: amountPaisa,
        createdAt: _now(),
        saleId: saleId,
      ),
    );
    _customers[customerId] = c.copyWith(
      balancePaisa: balance,
      lastNote: balance == 0
          ? 'सबै तिर्यो'
          : 'आज · ${type == LedgerType.credit ? 'उधारो' : 'तिर्यो'} ${formatRs(amountPaisa)}',
    );
    if (notify) notifyListeners();
  }
}
