import '../core/qty.dart';
import '../data/bill.dart';
import '../data/shop_store.dart';
import 'bill_reader.dart';

/// Turns what the AI read into bill rows (docs/stock-from-bill.md D4–D7):
/// remembered bill names first, then the AI's match (only if the product
/// exists), packs from the product, and every doubt as a row issue. Only rows
/// with no doubt start ticked.
BillDraft draftFromReading(BillReading reading, ShopStore store) {
  final rows = <BillRow>[];
  for (final l in reading.lines) {
    final remembered = store.productIdForBillText(l.text);
    final aiId = l.productId != null && store.hasProduct(l.productId!) ? l.productId : null;
    final id = remembered ?? aiId;
    final p = id == null ? null : store.product(id);
    final issues = <RowIssue>{};
    if (p != null && p.archived) issues.add(RowIssue.hiddenProduct);
    if (remembered == null && aiId != null && l.match != 'high') issues.add(RowIssue.unsureMatch);
    if (l.unsureNumbers || l.qtyMilli == null) issues.add(RowIssue.unsureNumbers);

    final inPacks = l.qtyIn == 'pack';
    int? packSize;
    if (inPacks && p != null) {
      if (p.hasPack) {
        packSize = p.packSizeMilli;
      } else {
        issues.add(RowIssue.packUnknown);
      }
    }
    // BR7: never convert between loose and counted goods by guess.
    final billLoose = l.qtyIn == 'kg' || l.qtyIn == 'litre';
    if (p != null && !inPacks && l.qtyIn != null) {
      final same = billLoose ? p.unit.name == l.qtyIn : !p.unit.isLoose;
      if (!same) issues.add(RowIssue.unitConflict);
    }
    final row = BillRow(
      productId: id,
      text: l.text,
      suggestedNameNe: l.nameNe,
      unitHint: l.qtyIn == 'kg' ? Unit.kg : (l.qtyIn == 'litre' ? Unit.litre : null),
      qtyMilli: l.qtyMilli ?? 0,
      freeMilli: l.freeQtyMilli ?? 0,
      inPacks: inPacks,
      packWord: l.packWord,
      packSizeMilli: packSize,
      ratePaisa: l.ratePaisa,
      amountPaisa: l.amountPaisa,
      issues: issues,
      note: l.note,
    );
    row.ticked = issues.isEmpty && row.canSave;
    rows.add(row);
  }
  return BillDraft(
    rows: rows,
    fromPhoto: true,
    notice: reading.tooManyLines ? 'धेरै लाइन — बाँकी सामान अर्को फोटोमा खिच्नुस्' : null,
    header: BillHeader(
      supplierName: reading.supplierName,
      supplierPhone: reading.supplierPhone,
      billNo: reading.billNo,
      billDateText: reading.billDateText,
      totalPaisa: reading.totalPaisa,
      vatPaisa: reading.vatPaisa,
      discountPaisa: reading.discountPaisa,
    ),
  );
}
