import 'dart:typed_data';

import '../core/qty.dart';
import '../data/models.dart';

/// One line as the `readBill` function returned it (already checked on the server).
class BillLineReading {
  const BillLineReading({
    required this.text,
    this.qtyMilli,
    this.qtyIn,
    this.packWord,
    this.freeQtyMilli,
    this.ratePaisa,
    this.amountPaisa,
    this.productId,
    this.match = 'none',
    this.nameNe,
    this.unsureNumbers = false,
    this.note,
  });

  final String text;
  final int? qtyMilli;

  /// "unit", "pack", "kg" or "litre".
  final String? qtyIn;
  final String? packWord;
  final int? freeQtyMilli;
  final int? ratePaisa;
  final int? amountPaisa;
  final String? productId;

  /// "high", "low" or "none".
  final String match;
  final String? nameNe;

  /// The AI was unsure of the quantity, rate or amount.
  final bool unsureNumbers;
  final String? note;

  factory BillLineReading.fromMap(Map<String, Object?> m) {
    String? s(String k) => m[k] is String && (m[k] as String).trim().isNotEmpty ? (m[k] as String).trim() : null;
    int? n(String k) => m[k] is int && (m[k] as int) > 0 ? m[k] as int : null;
    final confidence = m['confidence'];
    return BillLineReading(
      text: s('text') ?? '',
      qtyMilli: n('qtyMilli'),
      qtyIn: const {'unit', 'pack', 'kg', 'litre'}.contains(m['qtyIn']) ? m['qtyIn'] as String : null,
      packWord: s('packWord'),
      freeQtyMilli: n('freeQtyMilli'),
      ratePaisa: n('ratePaisa'),
      amountPaisa: n('amountPaisa'),
      productId: s('productId'),
      match: const {'high', 'low'}.contains(m['match']) ? m['match'] as String : 'none',
      nameNe: s('nameNe'),
      unsureNumbers: confidence is Map && confidence.values.contains('low'),
      note: s('note'),
    );
  }
}

/// What the AI read from a bill: text and numbers only; the app does the sums (BR15).
class BillReading {
  const BillReading({
    required this.lines,
    this.supplierName,
    this.supplierPhone,
    this.billNo,
    this.billDateText,
    this.totalPaisa,
    this.vatPaisa,
    this.discountPaisa,
    this.tooManyLines = false,
  });

  final List<BillLineReading> lines;
  final String? supplierName;
  final String? supplierPhone;
  final String? billNo;
  final String? billDateText;
  final int? totalPaisa;
  final int? vatPaisa;
  final int? discountPaisa;
  final bool tooManyLines;

  factory BillReading.fromMap(Map<String, Object?> m) {
    String? s(String k) => m[k] is String && (m[k] as String).trim().isNotEmpty ? (m[k] as String).trim() : null;
    int? n(String k) => m[k] is int && (m[k] as int) > 0 ? m[k] as int : null;
    final lines = m['lines'];
    return BillReading(
      lines: [
        if (lines is List)
          for (final l in lines)
            if (l is Map) BillLineReading.fromMap(l.cast<String, Object?>()),
      ].where((l) => l.text.isNotEmpty).toList(),
      supplierName: s('supplierName'),
      supplierPhone: s('supplierPhone'),
      billNo: s('billNo'),
      billDateText: s('billDateText'),
      totalPaisa: n('totalPaisa'),
      vatPaisa: n('vatPaisa'),
      discountPaisa: n('discountPaisa'),
      tooManyLines: m['tooManyLines'] == true,
    );
  }
}

/// Why a bill couldn't be read; the shopkeeper can always build it by hand.
enum BillReadProblem {
  offline('इन्टरनेट आएपछि बिल पढ्न सकिन्छ'),
  limitReached('आजको बिल पढ्ने सीमा सकियो — हातैले बिल बनाउनुस्'),
  unreadable('बिल पढ्न सकिएन — फेरि खिच्नुस् वा हातैले बिल बनाउनुस्'),
  unavailable('बिल पढ्ने सुविधा अहिले उपलब्ध छैन — हातैले बिल बनाउनुस्');

  const BillReadProblem(this.message);

  final String message;
}

sealed class BillReadResult {
  const BillReadResult();
}

final class BillRead extends BillReadResult {
  const BillRead(this.reading);
  final BillReading reading;
}

final class BillReadFailed extends BillReadResult {
  const BillReadFailed(this.problem);
  final BillReadProblem problem;
}

/// The shop's catalog as sent to the AI, so it can match lines to products (D4).
Map<String, Object?> catalogEntry(Product p) => {
  'id': p.id,
  'ne': p.nameNe,
  'en': p.nameEn,
  'unit': p.unit.name,
  if (p.hasPack) 'packName': p.packName,
  if (p.hasPack) 'packSize': p.packSizeMilli! / milli,
};

/// Client side of the `readBill` Cloud Function. Never throws.
abstract interface class BillReader {
  /// [pages] are JPEGs already shrunk to ≤ 1600 px.
  Future<BillReadResult> read(List<Uint8List> pages, List<Map<String, Object?>> catalog);
}

/// No AI backend: the manual bill is always there (F-17-like).
class NoBillReader implements BillReader {
  const NoBillReader();

  @override
  Future<BillReadResult> read(List<Uint8List> pages, List<Map<String, Object?>> catalog) async =>
      const BillReadFailed(BillReadProblem.unavailable);
}
