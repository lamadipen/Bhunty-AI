import 'package:bhunte_ai/core/money.dart';
import 'package:bhunte_ai/core/qty.dart';
import 'package:bhunte_ai/data/demo_data.dart';
import 'package:bhunte_ai/data/models.dart';
import 'package:bhunte_ai/data/proposed_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 18, 6); // 11:45 NPT

  test('demo shop matches the prototype numbers', () {
    final s = demoStore(clock: () => now);
    expect(s.today.totalPaisa, rs(4250));
    expect(s.today.cashPaisa, rs(3100));
    expect(s.today.qrPaisa, rs(1150));
    expect(s.totalUdharoPaisa, rs(12400));
    expect(s.lowStock.map((p) => p.id), ['waiwai', 'sugar', 'oil']);
    expect(s.today.topItems.first.product.id, 'waiwai');
  });

  test('cash sale computes total and change and takes stock down', () {
    final s = demoStore(clock: () => now);
    final sale = s.recordSale(
      cart: {'egg': 5 * milli, 'sugar': 500},
      method: PaymentMethod.cash,
      tenderedPaisa: rs(500),
    );
    expect(sale.totalPaisa, rs(100 + 60));
    expect(sale.changePaisa, rs(340));
    expect(s.product('egg').stockMilli, 85 * milli);
    expect(s.product('sugar').stockMilli, 2500);
    expect(s.today.totalPaisa, rs(4250 + 160));
  });

  test('udharo sale credits the customer in the same write', () {
    final s = demoStore(clock: () => now);
    s.recordSale(cart: {'oil': milli}, method: PaymentMethod.udharo, customerId: 'sita');
    expect(s.customer('sita').balancePaisa, rs(850 + 280));
    expect(s.ledger.single.saleId, isNotNull);
    expect(s.today.udharoPaisa, rs(280));
  });

  test('udharo sale without a customer is rejected', () {
    final s = demoStore(clock: () => now);
    expect(() => s.recordSale(cart: {'oil': milli}, method: PaymentMethod.udharo), throwsArgumentError);
  });

  test('payment cannot exceed what is owed', () {
    final s = demoStore(clock: () => now);
    expect(s.validate(RecordPayment(customerId: 'sita', amountPaisa: rs(900))), isNotNull);
    s.recordPayment('sita', rs(850));
    expect(s.customer('sita').balancePaisa, 0);
    expect(s.customer('sita').lastNote, 'सबै तिर्यो');
  });

  test('AI actions are validated before they are applied', () {
    final s = demoStore(clock: () => now);
    expect(() => s.apply(const RecordCredit(customerId: 'nobody', amountPaisa: 100)), throwsArgumentError);
    expect(s.validate(const AddToCart(productId: 'egg', qtyMilli: 0)), isNotNull);
    s.apply(RecordCredit(customerId: 'ram', amountPaisa: rs(350)));
    expect(s.customer('ram').balancePaisa, rs(3550));
  });

  test('stock from bill adds to stock', () {
    final s = demoStore(clock: () => now);
    s.addStock([StockLine(productId: 'waiwai', qtyMilli: 60 * milli, costPaisa: rs(18))]);
    expect(s.product('waiwai').stockMilli, 66 * milli);
    expect(s.lowStock.map((p) => p.id), isNot(contains('waiwai')));
  });
}
