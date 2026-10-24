import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/money.dart';
import '../core/qty.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/product_tile.dart';

/// Today's numbers, all computed on the device from today's sales.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final t = store.today;
    Widget method(String label, int paisa, Color bg, Color fg) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Pill(label, bg: bg, fg: fg),
          const Spacer(),
          Text(formatRs(paisa), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ],
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'हिसाब', subtitle: "आजको · Today's report"),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  CardBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('आजको बिक्री', style: TextStyle(fontSize: 16, color: BColors.inkSoft)),
                        Text(
                          formatRs(t.totalPaisa),
                          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, height: 1.15),
                        ),
                        Text('${t.saleCount} पटक बिक्री', style: const TextStyle(fontSize: 15, color: BColors.inkSoft)),
                        const SizedBox(height: 12),
                        method('नगद', t.cashPaisa, BColors.greenTint, BColors.greenDark),
                        method('QR', t.qrPaisa, BColors.blueTint, BColors.blue),
                        method('उधारो', t.udharoPaisa, BColors.warnBg, BColors.warnInk),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  CardBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('धेरै बिकेको', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        if (t.topItems.isEmpty)
                          const Text('आज अहिलेसम्म बिक्री छैन', style: TextStyle(fontSize: 16, color: BColors.inkSoft)),
                        for (final item in t.topItems.take(5))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                ProductPicture(product: item.product, size: 40),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    item.product.nameNe,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Text(
                                  '${formatQty(item.qtyMilli)} ${item.product.unit.ne}',
                                  style: const TextStyle(fontSize: 17, color: BColors.inkSoft),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  CardBox(
                    color: store.lowStock.isEmpty ? BColors.white : BColors.warnCard,
                    borderColor: store.lowStock.isEmpty ? BColors.line : BColors.warnBorder,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('सकिँदै गरेको सामान', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        if (store.lowStock.isEmpty)
                          const Text('सबै सामान पुग्दो छ', style: TextStyle(fontSize: 16, color: BColors.inkSoft)),
                        for (final p in store.lowStock)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    p.nameNe,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Text(
                                  '${formatQty(p.stockMilli)} ${p.unit.ne} बाँकी',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    color: BColors.warnInk,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
