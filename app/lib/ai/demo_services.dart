import '../core/money.dart';
import '../core/qty.dart';
import '../data/models.dart';
import '../data/proposed_action.dart';
import 'assistant_service.dart';

/// Scripted stand-in for the AI backend, matching the prototype's demo turns.
/// Swap for a Cloud Functions client once the backend exists.
class DemoAssistantService implements AssistantService {
  DemoAssistantService({this.delay = const Duration(milliseconds: 1100)});

  final Duration delay;
  final Map<VoiceContext, int> _turn = {};

  static final _scripts = <VoiceContext, List<Heard>>{
    VoiceContext.sell: [
      Heard('पाँच वटा अण्डा', ActionIntent(AddToCart(productId: 'egg', qtyMilli: 5 * milli))),
      Heard('दुई केजी चिनी', ActionIntent(AddToCart(productId: 'sugar', qtyMilli: 2 * milli))),
      Heard('दस वटा वाइवाइ', ActionIntent(AddToCart(productId: 'waiwai', qtyMilli: 10 * milli))),
      Heard('आधा केजी चिनी', ActionIntent(AddToCart(productId: 'sugar', qtyMilli: 500))),
    ],
    VoiceContext.stock: [
      Heard(
        '२० वटा साबुन आयो',
        ActionIntent(
          AddStock(
            lines: [StockLine(productId: 'soap', qtyMilli: 20 * milli, costPaisa: rs(45))],
          ),
        ),
      ),
    ],
    VoiceContext.chat: [
      Heard('राम दाइलाई ३५० उधारो लेखिदेऊ', ActionIntent(RecordCredit(customerId: 'ram', amountPaisa: rs(350)))),
      Heard('कुन सामान सकिँदैछ?', QueryIntent(QueryMetric.lowStock)),
      Heard('राम दाइको कति बाँकी छ?', QueryIntent(QueryMetric.customerBalance, customerId: 'ram')),
      Heard('आज कति बिक्यो?', QueryIntent(QueryMetric.salesToday)),
    ],
  };

  @override
  Future<Heard> listen(VoiceContext context) async {
    await Future<void>.delayed(delay);
    final script = _scripts[context]!;
    final i = _turn[context] ?? 0;
    _turn[context] = i + 1;
    return script[i % script.length];
  }

  @override
  Future<String> listenForName() async {
    await Future<void>.delayed(delay);
    return 'श्याम दाइ';
  }

  @override
  Future<List<BillLineProposal>> readBill() async {
    await Future<void>.delayed(delay + const Duration(milliseconds: 300));
    return [
      BillLineProposal(
        label: 'वाइवाइ (प्याकेट)',
        productId: 'waiwai',
        qtyMilli: 60 * milli,
        costPaisa: rs(18),
        confident: true,
      ),
      BillLineProposal(
        label: 'चिनी 1 केजी',
        productId: 'sugar',
        qtyMilli: 25 * milli,
        costPaisa: rs(105),
        confident: true,
      ),
      BillLineProposal(
        label: 'तेल 1 लिटर',
        productId: 'oil',
        qtyMilli: 12 * milli,
        costPaisa: rs(250),
        confident: true,
      ),
      BillLineProposal(
        label: 'साबुन',
        productId: 'soap',
        qtyMilli: 24 * milli,
        costPaisa: rs(45),
        confident: false,
        note: 'कुन साबुन? फोटो प्रस्ट भएन',
      ),
      BillLineProposal(
        label: 'बिस्कुट',
        productId: 'biscuit',
        qtyMilli: 40 * milli,
        costPaisa: rs(22),
        confident: true,
      ),
      BillLineProposal(
        label: 'दूध',
        productId: 'milk',
        qtyMilli: 8 * milli,
        costPaisa: rs(48),
        confident: false,
        note: '3 हो कि 8? जाँच्नुस्',
      ),
    ];
  }
}

class DemoBarcodeScanner implements BarcodeScanner {
  DemoBarcodeScanner({this.delay = const Duration(milliseconds: 400)});

  final Duration delay;
  static const _codes = ['demo-biscuit', 'demo-soap', 'demo-milk', 'demo-waiwai'];
  int _i = 0;

  @override
  Future<String?> scan() async {
    await Future<void>.delayed(delay);
    return _codes[_i++ % _codes.length];
  }
}
