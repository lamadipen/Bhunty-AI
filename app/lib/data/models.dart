import '../core/money.dart';
import '../core/qty.dart';

class Product {
  const Product({
    required this.id,
    required this.nameNe,
    required this.nameEn,
    required this.pricePaisa,
    required this.costPaisa,
    required this.unit,
    required this.stockMilli,
    required this.lowStockAtMilli,
    required this.letter,
    required this.tileBg,
    required this.tileInk,
    this.barcode,
    this.isFavourite = true,
    this.packName,
    this.packSizeMilli,
  });

  final String id;
  final String nameNe;
  final String nameEn;

  /// Price per one [unit].
  final int pricePaisa;
  final int costPaisa;
  final Unit unit;
  final int stockMilli;
  final int lowStockAtMilli;
  final String? barcode;
  final bool isFavourite;

  /// How the wholesaler sells it, e.g. "कार्टुन" holding 30 packets
  /// ([packSizeMilli] = 30000). Stock is always kept in selling units.
  final String? packName;
  final int? packSizeMilli;

  bool get hasPack => packName != null && (packSizeMilli ?? 0) > 0;

  /// Picture-grid placeholder until product photos exist: short Devanagari
  /// letters on a tinted tile (ARGB colours, so the data layer stays Flutter-free).
  final String letter;
  final int tileBg;
  final int tileInk;

  bool get isLow => stockMilli <= lowStockAtMilli;

  Product withStock(int stockMilli) => copyWith(stockMilli: stockMilli);

  Product withPack(String name, int sizeMilli) => Product(
    id: id,
    nameNe: nameNe,
    nameEn: nameEn,
    pricePaisa: pricePaisa,
    costPaisa: costPaisa,
    unit: unit,
    stockMilli: stockMilli,
    lowStockAtMilli: lowStockAtMilli,
    letter: letter,
    tileBg: tileBg,
    tileInk: tileInk,
    barcode: barcode,
    isFavourite: isFavourite,
    packName: name,
    packSizeMilli: sizeMilli,
  );

  Product copyWith({int? stockMilli, int? costPaisa}) => Product(
    id: id,
    nameNe: nameNe,
    nameEn: nameEn,
    pricePaisa: pricePaisa,
    costPaisa: costPaisa ?? this.costPaisa,
    unit: unit,
    stockMilli: stockMilli ?? this.stockMilli,
    lowStockAtMilli: lowStockAtMilli,
    letter: letter,
    tileBg: tileBg,
    tileInk: tileInk,
    barcode: barcode,
    isFavourite: isFavourite,
    packName: packName,
    packSizeMilli: packSizeMilli,
  );
}

class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.initial,
    required this.balancePaisa,
    required this.lastNote,
  });

  final String id;
  final String name;
  final String initial;

  /// What the customer owes the shop. Never negative.
  final int balancePaisa;

  /// Short line under the name, e.g. "आज · उधारो रु 350".
  final String lastNote;

  Customer copyWith({int? balancePaisa, String? lastNote}) => Customer(
    id: id,
    name: name,
    initial: initial,
    balancePaisa: balancePaisa ?? this.balancePaisa,
    lastNote: lastNote ?? this.lastNote,
  );
}

enum LedgerType { credit, payment }

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.customerId,
    required this.type,
    required this.amountPaisa,
    required this.createdAt,
    this.saleId,
  });

  final String id;
  final String customerId;
  final LedgerType type;
  final int amountPaisa;
  final DateTime createdAt;
  final String? saleId;
}

enum PaymentMethod { cash, qr, udharo }

class SaleLine {
  const SaleLine({
    required this.productId,
    required this.name,
    required this.qtyMilli,
    required this.pricePaisa,
    required this.lineTotalPaisa,
  });

  final String productId;
  final String name;
  final int qtyMilli;
  final int pricePaisa;
  final int lineTotalPaisa;
}

class Sale {
  const Sale({
    required this.id,
    required this.lines,
    required this.totalPaisa,
    required this.method,
    required this.createdAt,
    this.tenderedPaisa,
    this.changePaisa,
    this.customerId,
  });

  final String id;
  final List<SaleLine> lines;
  final int totalPaisa;
  final PaymentMethod method;
  final DateTime createdAt;
  final int? tenderedPaisa;
  final int? changePaisa;
  final String? customerId;
}

class StockLine {
  StockLine({required this.productId, required this.qtyMilli, required this.costPaisa, int? totalCostPaisa})
    : totalCostPaisa = totalCostPaisa ?? lineTotal(costPaisa, qtyMilli);

  final String productId;

  /// In selling units, even when entered as packs.
  final int qtyMilli;

  /// Cost per one selling unit (rounded when it came from a pack price).
  final int costPaisa;

  /// What the line cost in total, exactly as on the bill (e.g. 2 cartons × रु 900).
  final int totalCostPaisa;
}

/// One line the AI read from a wholesaler bill. Not stock until the user ticks it.
class BillLineProposal {
  const BillLineProposal({
    required this.label,
    required this.productId,
    required this.qtyMilli,
    required this.costPaisa,
    required this.confident,
    this.note,
  });

  /// Text as read from the bill.
  final String label;
  final String productId;
  final int qtyMilli;
  final int costPaisa;

  /// When false the row starts unticked and highlighted (principle 8).
  final bool confident;
  final String? note;
}

class TopItem {
  const TopItem(this.product, this.qtyMilli);
  final Product product;
  final int qtyMilli;
}

class TodayStats {
  const TodayStats({
    required this.totalPaisa,
    required this.cashPaisa,
    required this.qrPaisa,
    required this.udharoPaisa,
    required this.saleCount,
    required this.topItems,
  });

  final int totalPaisa;
  final int cashPaisa;
  final int qrPaisa;
  final int udharoPaisa;
  final int saleCount;
  final List<TopItem> topItems;
}
