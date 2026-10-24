import 'dart:typed_data';

import '../core/money.dart';
import '../core/qty.dart';
import 'bill_reader.dart';

/// Scripted stand-in for `readBill` so the demo shows every kind of row:
/// ready lines, a sum that doesn't add up, an unclear number and a new item.
/// Tests pass [result].
class DemoBillReader implements BillReader {
  DemoBillReader({this.delay = const Duration(milliseconds: 1200), this.result});

  final Duration delay;
  final BillReadResult? result;
  int calls = 0;
  List<Map<String, Object?>> lastCatalog = const [];

  @override
  Future<BillReadResult> read(List<Uint8List> pages, List<Map<String, Object?>> catalog) async {
    calls++;
    lastCatalog = catalog;
    await Future<void>.delayed(delay);
    return result ??
        BillRead(
          BillReading(
            supplierName: 'राम ट्रेडर्स',
            supplierPhone: '9812345678',
            billNo: '1452',
            billDateText: '२०८१/०७/०८',
            totalPaisa: rs(8769),
            lines: [
              BillLineReading(
                text: 'WAI WAI CHICKEN 2 CTN',
                qtyMilli: 2 * milli,
                qtyIn: 'pack',
                packWord: 'CTN',
                ratePaisa: rs(540),
                amountPaisa: rs(1080),
                productId: 'waiwai',
                match: 'high',
              ),
              BillLineReading(
                text: 'चिनी 25 kg',
                qtyMilli: 25 * milli,
                qtyIn: 'kg',
                ratePaisa: rs(105),
                amountPaisa: rs(2625),
                productId: 'sugar',
                match: 'high',
              ),
              BillLineReading(
                text: 'LUX SOAP',
                qtyMilli: 24 * milli,
                qtyIn: 'unit',
                ratePaisa: rs(45),
                amountPaisa: rs(108),
                productId: 'soap',
                match: 'high',
              ),
              BillLineReading(
                text: 'दूध',
                qtyMilli: 8 * milli,
                qtyIn: 'unit',
                ratePaisa: rs(48),
                amountPaisa: rs(384),
                productId: 'milk',
                match: 'high',
                unsureNumbers: true,
                note: '3 हो कि 8?',
              ),
              BillLineReading(
                text: 'Real Juice Mango 1L',
                qtyMilli: 12 * milli,
                qtyIn: 'unit',
                ratePaisa: rs(300),
                amountPaisa: rs(3600),
                nameNe: 'रियल जुस आँप',
              ),
            ],
          ),
        );
  }
}
