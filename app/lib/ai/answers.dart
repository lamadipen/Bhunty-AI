import '../core/money.dart';
import '../core/qty.dart';
import '../data/models.dart';
import '../data/shop_store.dart';
import 'assistant_service.dart';

/// A reply in the chat, built in code from the shop's data.
sealed class Answer {
  const Answer();
}

final class TextAnswer extends Answer {
  const TextAnswer(this.text, {this.offerOrderList = false});
  final String text;
  final bool offerOrderList;
}

final class StatAnswer extends Answer {
  const StatAnswer(this.stats);
  final TodayStats stats;
}

/// Fixed sentence templates; numbers always come from [store], never the model.
Answer answerQuery(QueryIntent q, ShopStore store) {
  switch (q.metric) {
    case QueryMetric.salesToday:
      return StatAnswer(store.today);
    case QueryMetric.lowStock:
      final low = store.lowStock;
      if (low.isEmpty) return const TextAnswer('सबै सामान पुग्दो छ।');
      final parts = [for (final p in low) '${p.nameNe} ${formatQty(p.stockMilli)} ${p.unit.ne}'];
      return TextAnswer('${joinNe(parts)} मात्र बाँकी छ। होलसेलको अर्डर लिस्ट बनाऊँ?', offerOrderList: true);
    case QueryMetric.customerBalance:
      final id = q.customerId;
      if (id == null) return const TextAnswer('कसको? नाम फेरि भन्नुस्।');
      final c = store.customer(id);
      return TextAnswer(
        c.balancePaisa == 0 ? '${c.name}को सबै चुक्ता छ।' : '${c.name}को ${formatRs(c.balancePaisa)} बाँकी छ।',
      );
  }
}

/// "क, ख र ग"
String joinNe(List<String> parts) {
  if (parts.length <= 1) return parts.join();
  return '${parts.sublist(0, parts.length - 1).join(', ')} र ${parts.last}';
}
