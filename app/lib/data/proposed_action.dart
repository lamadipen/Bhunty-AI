import 'models.dart';

/// A change the AI suggests. Mirrors the LLM tool definitions in
/// docs/architecture.md. Nothing here touches data: the app shows a confirm
/// card and only a user tap passes it to `ShopStore.apply` (or the cart).
sealed class ProposedAction {
  const ProposedAction();
}

final class AddToCart extends ProposedAction {
  const AddToCart({required this.productId, required this.qtyMilli});
  final String productId;
  final int qtyMilli;
}

final class RecordCredit extends ProposedAction {
  const RecordCredit({required this.customerId, required this.amountPaisa});
  final String customerId;
  final int amountPaisa;
}

final class RecordPayment extends ProposedAction {
  const RecordPayment({required this.customerId, required this.amountPaisa});
  final String customerId;
  final int amountPaisa;
}

final class AddStock extends ProposedAction {
  const AddStock({required this.lines});
  final List<StockLine> lines;
}
