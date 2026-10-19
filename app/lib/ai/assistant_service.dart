import 'package:flutter/widgets.dart' show BuildContext;

import '../data/models.dart';
import '../data/proposed_action.dart';

/// Where the user pressed the mic. The backend uses it to narrow which tools
/// the model may call.
enum VoiceContext { sell, stock, chat }

/// Read-only questions. Answers are computed in code from the shop's data and
/// filled into fixed sentences; the model only picks the metric.
enum QueryMetric { salesToday, lowStock, customerBalance }

/// What the model made of the user's words: a tool call, never a write.
sealed class AssistantIntent {
  const AssistantIntent();
}

final class ActionIntent extends AssistantIntent {
  const ActionIntent(this.action);
  final ProposedAction action;
}

final class QueryIntent extends AssistantIntent {
  const QueryIntent(this.metric, {this.customerId});
  final QueryMetric metric;
  final String? customerId;
}

final class UnclearIntent extends AssistantIntent {
  const UnclearIntent(this.reason);
  final String reason;
}

class Heard {
  const Heard(this.transcript, this.intent);
  final String transcript;
  final AssistantIntent intent;
}

/// Client side of the Cloud Functions AI wrapper (parseVoice, parseBill, askBhunte).
/// Implementations must degrade gracefully offline (principle 7).
abstract interface class AssistantService {
  /// Records speech, transcribes it and parses it into an intent.
  Future<Heard> listen(VoiceContext context);

  /// Records a customer's name for a new udharo account.
  Future<String> listenForName();

  /// Photographs a wholesaler bill and reads its lines.
  Future<List<BillLineProposal>> readBill();
}

/// Barcode/QR scanning. The real one opens the camera screen, so it needs a context.
abstract interface class BarcodeScanner {
  /// A checked product code (see `checkProductCode`), or null if the user cancelled.
  Future<String?> scan(BuildContext context);
}
