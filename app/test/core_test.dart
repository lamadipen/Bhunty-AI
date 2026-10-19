import 'package:bhunte_ai/core/cash.dart';
import 'package:bhunte_ai/core/keypad_input.dart';
import 'package:bhunte_ai/core/money.dart';
import 'package:bhunte_ai/core/nepal_time.dart';
import 'package:bhunte_ai/core/qty.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('money', () {
    test('Indian grouping', () {
      expect(groupIndian(0), '0');
      expect(groupIndian(950), '950');
      expect(groupIndian(4250), '4,250');
      expect(groupIndian(123456), '1,23,456');
      expect(groupIndian(12345678), '1,23,45,678');
      expect(groupIndian(-4250), '-4,250');
    });

    test('formatRs shows paisa only when present', () {
      expect(formatRs(rs(4250)), 'रु 4,250');
      expect(formatRs(2250), 'रु 22.50');
      expect(formatRs(-50), 'रु -0.50');
    });

    test('lineTotal handles loose goods and rounds half up', () {
      expect(lineTotal(rs(25), 3 * milli), rs(75));
      expect(lineTotal(rs(120), 500), rs(60)); // आधा केजी चिनी
      expect(lineTotal(rs(120), 250), rs(30));
      expect(lineTotal(333, 1500), 500); // 499.5 → 500
    });
  });

  group('qty', () {
    test('format and parse round-trip', () {
      expect(formatQty(2000), '2');
      expect(formatQty(2500), '2.5');
      expect(formatQty(250), '0.25');
      expect(parseQtyMilli('2.5'), 2500);
      expect(parseQtyMilli('0.25'), 250);
      expect(parseQtyMilli('12'), 12000);
      expect(parseQtyMilli(''), 0);
    });
  });

  group('cash', () {
    test('suggests exact then next real notes', () {
      expect(suggestTenders(rs(75)), [rs(75), rs(100), rs(500), rs(1000)]);
      expect(suggestTenders(rs(4250)), [rs(4250), rs(4300), rs(4500), rs(5000)]);
      expect(suggestTenders(rs(500)), [rs(500), rs(1000)]);
    });

    test('change is never negative', () {
      expect(changeDue(tenderedPaisa: rs(100), totalPaisa: rs(75)), rs(25));
      expect(changeDue(tenderedPaisa: rs(50), totalPaisa: rs(75)), 0);
    });
  });

  group('keypad', () {
    test('no leading zeros, one decimal point, backspace', () {
      expect(applyKey('', '0'), '0');
      expect(applyKey('0', '5'), '5');
      expect(applyKey('', Keys.doubleZero), '');
      expect(applyKey('5', Keys.doubleZero), '500');
      expect(applyKey('2', Keys.dot), '2', reason: 'decimal not allowed for pieces');
      expect(applyKey('2', Keys.dot, allowDecimal: true), '2.');
      expect(applyKey('2.5', Keys.dot, allowDecimal: true), '2.5');
      expect(applyKey('', Keys.dot, allowDecimal: true), '0.');
      expect(applyKey('0.125', '5', allowDecimal: true), '0.125');
      expect(applyKey('123', '4', maxDigits: 3), '123');
      expect(applyKey('12', Keys.backspace), '1');
    });
  });

  group('nepal time', () {
    test('day boundary is Nepal midnight, not UTC', () {
      // 18:14 UTC = 23:59 NPT; 18:15 UTC = 00:00 NPT next day.
      expect(nepalDayKey(DateTime.utc(2026, 10, 18, 18, 14)), '2026-10-18');
      expect(nepalDayKey(DateTime.utc(2026, 10, 18, 18, 15)), '2026-10-19');
    });
  });
}
