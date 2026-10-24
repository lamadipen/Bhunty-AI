import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/barcode.dart';
import '../core/nepal_time.dart';
import '../core/qty.dart';
import '../data/models.dart';
import '../data/shop_backend.dart';

/// Firestore field names follow docs/architecture.md. Money is int paisa,
/// quantities int milli-units — never doubles.

Map<String, Object?> productToMap(Product p) => {
  'name_ne': p.nameNe,
  'name_en': p.nameEn,
  'pricePaisa': p.pricePaisa,
  'costPaisa': p.costPaisa,
  'unit': p.unit.name,
  'stockMilli': p.stockMilli,
  'lowStockAtMilli': p.lowStockAtMilli,
  'barcode': p.barcode,
  'isFavourite': p.isFavourite,
  'letter': p.letter,
  'tileBg': p.tileBg,
  'tileInk': p.tileInk,
  'packName': p.packName,
  'packSizeMilli': p.packSizeMilli,
  'labelKind': p.labelKind?.name,
  'ownCode': p.ownCode,
  'archived': p.archived,
  'priceSetAt': p.priceSetAt == null ? null : Timestamp.fromDate(p.priceSetAt!),
};

Product productFromMap(String id, Map<String, dynamic> m) => Product(
  id: id,
  nameNe: m['name_ne'] as String? ?? '',
  nameEn: m['name_en'] as String? ?? '',
  pricePaisa: _int(m['pricePaisa']),
  costPaisa: _int(m['costPaisa']),
  unit: Unit.values.asNameMap()[m['unit']] ?? Unit.piece,
  stockMilli: _int(m['stockMilli']),
  lowStockAtMilli: _int(m['lowStockAtMilli']),
  barcode: m['barcode'] as String?,
  isFavourite: m['isFavourite'] as bool? ?? true,
  letter: m['letter'] as String? ?? _firstLetters(m['name_ne'] as String? ?? '?'),
  tileBg: _int(m['tileBg'], fallback: 0xFFE3F0E8),
  tileInk: _int(m['tileInk'], fallback: 0xFF14512F),
  packName: m['packName'] as String?,
  packSizeMilli: m['packSizeMilli'] as int?,
  labelKind: LabelKind.values.asNameMap()[m['labelKind']],
  // Older docs: only own codes ever had a labelKind.
  ownCode: m['ownCode'] as bool? ?? m['labelKind'] != null,
  archived: m['archived'] as bool? ?? false,
  priceSetAt: (m['priceSetAt'] as Timestamp?)?.toDate(),
);

Map<String, Object?> customerToMap(Customer c) => {
  'name': c.name,
  'initial': c.initial,
  'balancePaisa': c.balancePaisa,
  'lastNote': c.lastNote,
};

Customer customerFromMap(String id, Map<String, dynamic> m) {
  final name = m['name'] as String? ?? '';
  return Customer(
    id: id,
    name: name,
    initial: m['initial'] as String? ?? _firstLetters(name),
    balancePaisa: _int(m['balancePaisa']),
    lastNote: m['lastNote'] as String? ?? '',
  );
}

Map<String, Object?> ledgerToMap(LedgerEntry e) => {
  'type': e.type.name,
  'amountPaisa': e.amountPaisa,
  'saleId': e.saleId,
  'createdAt': Timestamp.fromDate(e.createdAt),
};

/// `day` is the Nepal-time date, so "today's sales" is one cheap equality query.
Map<String, Object?> saleToMap(Sale s, {required String createdBy}) => {
  'items': [
    for (final l in s.lines)
      {
        'productId': l.productId,
        'name': l.name,
        'qtyMilli': l.qtyMilli,
        'pricePaisa': l.pricePaisa,
        'lineTotalPaisa': l.lineTotalPaisa,
      },
  ],
  'subtotalPaisa': s.totalPaisa,
  'discountPaisa': 0,
  'totalPaisa': s.totalPaisa,
  // A list so split payments can be added without a migration.
  'payments': [
    {'method': s.method.name, 'amountPaisa': s.totalPaisa},
  ],
  'tenderedPaisa': s.tenderedPaisa,
  'changePaisa': s.changePaisa,
  'customerId': s.customerId,
  'createdAt': Timestamp.fromDate(s.createdAt),
  'day': nepalDayKey(s.createdAt),
  'createdBy': createdBy,
};

Sale saleFromMap(String id, Map<String, dynamic> m) {
  final payments = (m['payments'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final method = payments.isEmpty ? null : PaymentMethod.values.asNameMap()[payments.first['method']];
  return Sale(
    id: id,
    lines: [
      for (final l in ((m['items'] as List?) ?? const []).cast<Map<String, dynamic>>())
        SaleLine(
          productId: l['productId'] as String,
          name: l['name'] as String? ?? '',
          qtyMilli: _int(l['qtyMilli']),
          pricePaisa: _int(l['pricePaisa']),
          lineTotalPaisa: _int(l['lineTotalPaisa']),
        ),
    ],
    totalPaisa: _int(m['totalPaisa']),
    method: method ?? PaymentMethod.cash,
    createdAt: (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    tenderedPaisa: m['tenderedPaisa'] as int?,
    changePaisa: m['changePaisa'] as int?,
    customerId: m['customerId'] as String?,
  );
}

Map<String, Object?> deliveryToMap(Delivery d, {required String createdBy}) => {
  'source': d.source.wire,
  'supplierName': d.supplierName,
  'supplierPhone': d.supplierPhone,
  'billNo': d.billNo,
  'billDateText': d.billDateText,
  'billTotalPaisa': d.billTotalPaisa,
  'vatPaisa': d.vatPaisa,
  'discountPaisa': d.discountPaisa,
  'totalCostPaisa': d.totalCostPaisa,
  'batchCount': d.batchCount,
  'createdAt': Timestamp.fromDate(d.createdAt),
  'createdBy': createdBy,
};

Map<String, Object?> batchToMap(Batch b, {required String createdBy}) => {
  'deliveryId': b.deliveryId,
  'productId': b.productId,
  'productName': b.productName,
  'qtyMilli': b.qtyMilli,
  'enteredAs': b.enteredAsPack ? 'pack' : 'unit',
  'packName': b.packName,
  'packSizeMilli': b.packSizeMilli,
  'packsMilli': b.packsMilli,
  'unitCostPaisa': b.unitCostPaisa,
  'totalCostPaisa': b.totalCostPaisa,
  'salePricePaisa': b.salePricePaisa,
  'costMissing': b.costMissing,
  'source': b.source.wire,
  'billLineText': b.billLineText,
  'createdAt': Timestamp.fromDate(b.createdAt),
  'createdBy': createdBy,
};

/// `billAliases/{id}`: a bill line's normalised text → the product it is (BR9).
/// The id is the text itself, URI-encoded, so every device writes the same doc.
String billAliasId(String normalisedText) => Uri.encodeComponent(normalisedText);

Map<String, Object?> priceChangeToMap(PriceChange c, {required String createdBy}) => {
  'productId': c.productId,
  'oldPricePaisa': c.oldPricePaisa,
  'newPricePaisa': c.newPricePaisa,
  'reason': c.reason.name,
  'batchId': c.batchId,
  'createdAt': Timestamp.fromDate(c.createdAt),
  'createdBy': createdBy,
};

/// `productImages/{productId}`: the thumbnail as base64 (rules cap it at 80,000 characters).
Map<String, Object?> productImageToMap(ProductImage i, {required String updatedBy}) => {
  'jpegBase64': base64Encode(i.jpeg),
  'width': i.width,
  'height': i.height,
  'updatedAt': FieldValue.serverTimestamp(),
  'updatedBy': updatedBy,
};

ProductImage? productImageFromMap(Map<String, dynamic> m) {
  final data = m['jpegBase64'];
  if (data is! String || data.isEmpty) return null;
  try {
    return ProductImage(jpeg: base64Decode(data), width: _int(m['width']), height: _int(m['height']));
  } on FormatException {
    return null;
  }
}

/// Tap-grid order: `sortOrder` first (missing = last), then English name.
int compareProductDocs(DocumentSnapshot<Map<String, dynamic>> a, DocumentSnapshot<Map<String, dynamic>> b) {
  final byOrder = _int(
    a.data()?['sortOrder'],
    fallback: 1 << 30,
  ).compareTo(_int(b.data()?['sortOrder'], fallback: 1 << 30));
  if (byOrder != 0) return byOrder;
  return (a.data()?['name_en'] as String? ?? '').compareTo(b.data()?['name_en'] as String? ?? '');
}

int _int(Object? v, {int fallback = 0}) => v is int ? v : (v is num ? v.round() : fallback);

String _firstLetters(String name) => String.fromCharCodes(name.runes.take(2));
