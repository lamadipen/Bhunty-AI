import 'package:bhunte_ai/ai/demo_services.dart';
import 'package:bhunte_ai/app.dart';
import 'package:bhunte_ai/core/money.dart';
import 'package:bhunte_ai/data/demo_data.dart';
import 'package:bhunte_ai/data/shop_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ShopStore> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final store = demoStore();
  await tester.pumpWidget(
    BhunteApp(
      store: store,
      assistant: DemoAssistantService(delay: Duration.zero),
      scanner: DemoBarcodeScanner(delay: Duration.zero),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('home shows today and the main actions', (tester) async {
    await _pumpApp(tester);
    expect(find.text('भुन्टे'), findsOneWidget);
    expect(find.text('रु 4,250'), findsOneWidget);
    expect(find.text('बेच्नुस्'), findsOneWidget);
    expect(find.text('3 सामान सकिँदैछ'), findsOneWidget);
  });

  testWidgets('tap-only cash sale: two Wai Wai, pay with रु 100, change रु 50', (tester) async {
    final store = await _pumpApp(tester);
    await tester.tap(find.text('बेच्नुस्'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tile-waiwai')));
    await tester.tap(find.byKey(const ValueKey('tile-waiwai')));
    await tester.pump();
    expect(find.byKey(const ValueKey('cart-total')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('cart-total'))).data, 'रु 50');

    await tester.tap(find.text('पैसा लिनुस्'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('नगद · Cash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('रु 100'));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const ValueKey('change'))).data, 'रु 50');

    await tester.tap(find.text('सकियो'));
    await tester.pumpAndSettle();
    expect(find.text('बिक्री सकियो'), findsOneWidget);
    expect(find.text('नगद · फिर्ता रु 50'), findsOneWidget);
    expect(store.today.totalPaisa, rs(4250 + 50));
  });

  testWidgets('voice add needs a ✓ before it reaches the cart', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('बेच्नुस्'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('बोल्नुस्'));
    await tester.pumpAndSettle();
    expect(find.text('अण्डा × 5'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('cart-total'))).data, 'रु 0');

    await tester.tap(find.text('ठीक छ'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('cart-total'))).data, 'रु 100');
    await tester.pump(const Duration(seconds: 2)); // let the toast expire
  });
}
