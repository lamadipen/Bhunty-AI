import '../core/money.dart';
import '../core/qty.dart';

/// Why a bill row needs a look before it can be saved (docs/stock-from-bill.md §2.3).
/// (qty × rate ≠ the printed amount is checked from the numbers themselves: [BillRow.amountMismatch].)
enum RowIssue {
  /// The AI wasn't sure of a number it read.
  unsureNumbers,

  /// The AI wasn't sure which product this is (BR8).
  unsureMatch,

  /// "1 crate" for a product with no pack size yet (BR6).
  packUnknown,

  /// kg/litre on the bill for a product sold in pieces/packets, or the reverse (BR7).
  unitConflict,

  /// Matched to a hidden product (BR8).
  hiddenProduct,
}

/// One line of a delivery: read from a bill photo or added by hand.
/// Quantities are int milli-units, money int paisa (R10).
class BillRow {
  BillRow({
    this.productId,
    this.text,
    this.suggestedNameNe,
    this.unitHint,
    this.qtyMilli = 0,
    this.freeMilli = 0,
    this.inPacks = false,
    this.packWord,
    this.packSizeMilli,
    this.ratePaisa,
    this.amountPaisa,
    this.salePricePaisa,
    this.ticked = false,
    Set<RowIssue>? issues,
    this.note,
  }) : issues = issues ?? {};

  /// Null while it is a new item (not in the shop yet).
  String? productId;

  /// The line as printed on the bill; null for rows added by hand.
  final String? text;

  /// The AI's Nepali name for a new item.
  final String? suggestedNameNe;

  /// The unit the bill used (केजी/लिटर on the bill), for a new item's form.
  final Unit? unitHint;

  /// As on the bill: in packs when [inPacks], else in selling units. Free units are separate.
  int qtyMilli;
  int freeMilli;
  bool inPacks;

  /// The bill's word for the pack ("crate", "कार्टुन").
  String? packWord;

  /// Selling units per pack for this row: the product's, or what the user entered (BR6).
  int? packSizeMilli;

  /// Save [packSizeMilli] as the product's pack (BR6 switch "यो सामानमा सधैं").
  bool keepPack = true;

  /// Per pack (or unit) as printed.
  int? ratePaisa;

  /// The line amount as printed or entered; computed from the rate when missing (BR3).
  int? amountPaisa;

  /// Sale price from now on; null keeps the current one.
  int? salePricePaisa;
  bool ticked;

  /// A new item the shopkeeper chose not to add ("छोड्नुस्").
  bool skipped = false;
  final Set<RowIssue> issues;
  String? note;

  bool get fromBill => text != null;
  bool get isNew => productId == null;

  /// Stock this row adds, in selling units (free units included, BR11).
  int get unitsMilli {
    final q = qtyMilli + freeMilli;
    if (!inPacks) return q;
    final size = packSizeMilli;
    return size == null || size <= 0 ? 0 : packsToUnitsMilli(q, size);
  }

  /// What the line cost, exactly as on the bill; from qty × rate in code when not printed.
  int get totalPaisa => amountPaisa ?? (ratePaisa == null ? 0 : lineTotal(ratePaisa!, qtyMilli));

  /// Cost per selling unit (rounded); free units make it cheaper (BR11).
  int get unitCostPaisa => unitsMilli <= 0 ? 0 : unitCostFromPack(totalPaisa, unitsMilli);

  /// BR4: qty × rate vs the printed amount, within रु 1 of rounding.
  bool get amountMismatch {
    final rate = ratePaisa, amount = amountPaisa;
    if (rate == null || amount == null || qtyMilli <= 0) return false;
    return (lineTotal(rate, qtyMilli) - amount).abs() > 100;
  }

  /// Can be ticked: a known product, something arriving, nothing blocking.
  bool get canSave =>
      productId != null &&
      unitsMilli > 0 &&
      !amountMismatch &&
      !issues.contains(RowIssue.packUnknown) &&
      !issues.contains(RowIssue.unitConflict) &&
      !issues.contains(RowIssue.hiddenProduct);
}

/// Header of a delivery. Everything optional (R11, BR12).
class BillHeader {
  const BillHeader({
    this.supplierName,
    this.supplierPhone,
    this.billNo,
    this.billDateText,
    this.totalPaisa,
    this.vatPaisa,
    this.discountPaisa,
  });

  final String? supplierName;
  final String? supplierPhone;
  final String? billNo;

  /// As printed (e.g. "२०८१/०७/०८") until Bikram Sambat dates are built.
  final String? billDateText;

  /// The printed (or typed) bill total, for the check (BR5).
  final int? totalPaisa;
  final int? vatPaisa;
  final int? discountPaisa;

  BillHeader copyWith({
    String? supplierName,
    String? supplierPhone,
    String? billNo,
    int? totalPaisa,
    bool clearTotal = false,
  }) => BillHeader(
    supplierName: supplierName ?? this.supplierName,
    supplierPhone: supplierPhone ?? this.supplierPhone,
    billNo: billNo ?? this.billNo,
    billDateText: billDateText,
    totalPaisa: clearTotal ? null : (totalPaisa ?? this.totalPaisa),
    vatPaisa: vatPaisa,
    discountPaisa: discountPaisa,
  );
}

/// A delivery being checked on the bill screen. Nothing here is saved until
/// `ShopStore.receiveBill` (BR1). All arithmetic is done here, in code (BR15).
class BillDraft {
  BillDraft({List<BillRow>? rows, this.header = const BillHeader(), this.fromPhoto = false, this.notice})
    : rows = rows ?? [];

  final List<BillRow> rows;
  BillHeader header;

  /// Read from a bill photo (source `bill_photo`) rather than built by hand (`manual`).
  final bool fromPhoto;

  /// Something to say about the whole bill, e.g. too many lines for one read (BL-21).
  final String? notice;

  List<BillRow> get ticked => rows.where((r) => r.ticked && r.canSave).toList();

  /// Sum of every line, ticked or not, as on the bill.
  int get linesTotalPaisa => rows.fold(0, (s, r) => s + r.totalPaisa);

  /// VAT added and discount taken off the whole bill.
  int get extrasPaisa => (header.vatPaisa ?? 0) - (header.discountPaisa ?? 0);

  /// What the ticked lines will cost, with their share of VAT and discount (Q1).
  int get tickedTotalPaisa => batchTotals().fold(0, (s, t) => s + t);

  /// BR5: lines − discount + VAT vs the bill total, within रु 1. Null when there's no total to compare.
  int? get totalDifferencePaisa {
    final total = header.totalPaisa;
    if (total == null || rows.isEmpty) return null;
    final diff = total - (linesTotalPaisa + extrasPaisa);
    return diff.abs() > 100 ? diff : null;
  }

  /// Each ticked line's batch total: its amount plus its share of VAT and
  /// discount, in proportion to the whole bill. When every line is ticked the
  /// rounding goes to the last one, so the delivery equals the bill (BL-14).
  List<int> batchTotals() {
    final lines = ticked;
    final all = linesTotalPaisa, extras = extrasPaisa;
    if (extras == 0 || all <= 0) return [for (final r in lines) r.totalPaisa];
    final totals = [for (final r in lines) r.totalPaisa + (extras * r.totalPaisa / all).round()];
    if (lines.length == rows.length && totals.isNotEmpty) {
      totals[totals.length - 1] += all + extras - totals.fold(0, (s, t) => s + t);
    }
    return totals;
  }
}

final _notWord = RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true);

/// How a bill line is remembered (BR9): lower case, punctuation as spaces, single spaces.
String normaliseBillText(String text) {
  final t = text.toLowerCase().replaceAll(_notWord, ' ').trim();
  return t.length > 120 ? t.substring(0, 120) : t;
}

/// "रु 13 दरले" style helper for rows.
String rateLabel(int paisa) => '${formatRs(paisa)} दरले';
