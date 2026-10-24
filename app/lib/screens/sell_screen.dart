import 'package:flutter/material.dart';

import '../ai/assistant_service.dart';
import '../app_scope.dart';
import '../core/keypad_input.dart';
import '../core/money.dart';
import '../core/qty.dart';
import '../data/models.dart';
import '../data/proposed_action.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/keypad.dart';
import '../widgets/product_tile.dart';
import 'payment_sheets.dart';

/// Checkout: tap grid → scan → voice (tap first, AI second).
class SellScreen extends StatefulWidget {
  const SellScreen({super.key});

  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  /// productId → quantity in milli-units, in the order items were added.
  Map<String, int> _cart = {};
  bool _listening = false;
  Sale? _done;

  void _add(String productId, int qtyMilli) {
    setState(() {
      final next = (_cart[productId] ?? 0) + qtyMilli;
      _cart = {..._cart};
      if (next <= 0) {
        _cart.remove(productId);
      } else {
        _cart[productId] = next;
      }
    });
  }

  void _setQty(String productId, int qtyMilli) {
    setState(() {
      _cart = {..._cart};
      if (qtyMilli <= 0) {
        _cart.remove(productId);
      } else {
        _cart[productId] = qtyMilli;
      }
    });
  }

  Future<void> _scan() async {
    final store = context.readStore;
    final code = await context.scanner.scan();
    if (!mounted || code == null) return;
    final p = store.productByBarcode(code);
    if (p == null) {
      showToast(context, 'यो बारकोड भेटिएन');
      return;
    }
    _add(p.id, milli);
    showToast(context, 'स्क्यान भयो: ${p.nameNe} +1');
  }

  Future<void> _listen() async {
    if (_listening) return;
    final store = context.readStore;
    setState(() => _listening = true);
    final heard = await context.assistant.listen(VoiceContext.sell);
    if (!mounted) return;
    setState(() => _listening = false);
    final intent = heard.intent;
    if (intent is! ActionIntent || intent.action is! AddToCart || store.validate(intent.action) != null) {
      showToast(context, 'बुझिनँ, फेरि भन्नुस्');
      return;
    }
    final action = intent.action as AddToCart;
    final ok = await showBhunteSheet<bool>(
      context,
      (c) => VoiceConfirmSheet(
        heard: heard.transcript,
        product: store.product(action.productId),
        qtyMilli: action.qtyMilli,
      ),
    );
    if (!mounted || ok != true) return;
    _add(action.productId, action.qtyMilli);
    showToast(context, '${store.product(action.productId).nameNe} × ${formatQty(action.qtyMilli)} थपियो');
  }

  Future<void> _pickAny() async {
    final p = await showProductPicker(context, title: 'कुन सामान?');
    if (p != null) _add(p.id, milli);
  }

  Future<void> _openPad(Product p) async {
    final q = await showBhunteSheet<int>(context, (c) => QtyPadSheet(product: p, current: _cart[p.id] ?? 0));
    if (q != null) _setQty(p.id, q);
  }

  Future<void> _checkout() async {
    final store = context.readStore;
    final total = store.cartTotal(_cart);
    if (total == 0) return;
    final method = await showBhunteSheet<PaymentMethod>(context, (c) => PayMethodSheet(totalPaisa: total));
    if (!mounted || method == null) return;
    switch (method) {
      case PaymentMethod.cash:
        final tendered = await showBhunteSheet<int>(context, (c) => CashSheet(totalPaisa: total));
        if (tendered != null) _finish(method, tenderedPaisa: tendered);
      case PaymentMethod.qr:
        final paid = await showBhunteSheet<bool>(context, (c) => QrSheet(totalPaisa: total));
        if (paid == true) _finish(method);
      case PaymentMethod.udharo:
        final customerId = await showBhunteSheet<String>(context, (c) => UdharoPickSheet(totalPaisa: total));
        if (customerId != null) _finish(method, customerId: customerId);
    }
  }

  void _finish(PaymentMethod method, {int? tenderedPaisa, String? customerId}) {
    if (!mounted) return;
    final sale = context.readStore.recordSale(
      cart: _cart,
      method: method,
      tenderedPaisa: tenderedPaisa,
      customerId: customerId,
    );
    setState(() {
      _done = sale;
      _cart = {};
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final total = store.cartTotal(_cart);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const ScreenHeader(title: 'बेच्नुस्', subtitle: 'थिच्नुस्, स्क्यान गर्नुस् वा बोल्नुस्'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Column(
                    children: [
                      ProductGrid(
                        products: store.favourites,
                        maxTiles: 8,
                        onMore: _pickAny,
                        tileFor: (p) =>
                            ProductTile(product: p, badgeMilli: _cart[p.id] ?? 0, onTap: () => _add(p.id, milli)),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: BigButton(
                              label: 'स्क्यान',
                              icon: Icons.qr_code_scanner_rounded,
                              outlineColor: BColors.green,
                              foreground: BColors.green,
                              fontSize: 20,
                              onPressed: _scan,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: BigButton(
                              label: 'बोल्नुस्',
                              icon: Icons.mic_none_rounded,
                              color: BColors.orange,
                              fontSize: 20,
                              onPressed: _listen,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    decoration: const BoxDecoration(
                      color: BColors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      border: Border(
                        top: BorderSide(color: BColors.line),
                        left: BorderSide(color: BColors.line),
                        right: BorderSide(color: BColors.line),
                      ),
                    ),
                    child: _cart.isEmpty
                        ? const _EmptyCart()
                        : ListView(
                            children: [
                              for (final e in _cart.entries)
                                _CartRow(
                                  product: store.product(e.key),
                                  qtyMilli: e.value,
                                  onDec: () => _add(e.key, -milli),
                                  onInc: () => _add(e.key, milli),
                                  onPad: () => _openPad(store.product(e.key)),
                                ),
                            ],
                          ),
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: BColors.white,
                    border: Border(top: BorderSide(color: BColors.line)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'जम्मा · ${_cart.length} सामान',
                              style: const TextStyle(fontSize: 15, color: BColors.inkSoft),
                            ),
                            Text(
                              formatRs(total),
                              key: const ValueKey('cart-total'),
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1.1),
                            ),
                          ],
                        ),
                      ),
                      BigButton(
                        label: 'पैसा लिनुस्',
                        color: total > 0 ? BColors.green : BColors.disabled,
                        onPressed: total > 0 ? _checkout : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_listening)
              const BusyOverlay(icon: Icons.mic_none_rounded, title: 'सुन्दैछु…', subtitle: 'जस्तै: “पाँच वटा अण्डा”'),
            if (_done != null)
              SaleDoneView(
                sale: _done!,
                onNext: () => setState(() => _done = null),
                onHome: () => Navigator.of(context).maybePop(),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 40, color: BColors.muted),
          SizedBox(height: 4),
          Text(
            'टोकरी खाली छ',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: BColors.inkSoft),
          ),
          Text('माथिको सामान थिच्नुस्', style: TextStyle(fontSize: 15, color: BColors.inkSoft)),
        ],
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({
    required this.product,
    required this.qtyMilli,
    required this.onDec,
    required this.onInc,
    required this.onPad,
  });

  final Product product;
  final int qtyMilli;
  final VoidCallback onDec;
  final VoidCallback onInc;
  final VoidCallback onPad;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: BColors.lineSoft)),
      ),
      child: Row(
        children: [
          LetterTile(letter: p.letter, bg: Color(p.tileBg), ink: Color(p.tileInk), size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.nameNe, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.15)),
                Text(
                  '${formatRs(p.pricePaisa)} · ${formatRs(lineTotal(p.pricePaisa, qtyMilli))}',
                  style: const TextStyle(fontSize: 14, color: BColors.inkSoft),
                ),
              ],
            ),
          ),
          RoundIconButton(
            icon: Icons.remove_rounded,
            label: 'एउटा घटाउनुस्',
            size: 44,
            border: BColors.line,
            onPressed: onDec,
          ),
          const SizedBox(width: 6),
          Semantics(
            button: true,
            label: 'मात्रा ${formatQty(qtyMilli)}, थिचेर लेख्नुस्',
            excludeSemantics: true,
            child: Material(
              color: BColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: BColors.green, width: 2),
              ),
              child: InkWell(
                key: ValueKey('qty-${p.id}'),
                onTap: onPad,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 48),
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  child: Text(
                    formatQty(qtyMilli),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: BColors.green),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Material(
            color: BColors.green,
            shape: const CircleBorder(),
            child: Tooltip(
              message: 'एउटा थप्नुस्',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onInc,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.add_rounded, color: BColors.white, size: 24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "कति वटा?" — keypad for a cart line. Loose goods get a decimal key.
class QtyPadSheet extends StatefulWidget {
  const QtyPadSheet({super.key, required this.product, required this.current});

  final Product product;
  final int current;

  @override
  State<QtyPadSheet> createState() => _QtyPadSheetState();
}

class _QtyPadSheetState extends State<QtyPadSheet> {
  String _entry = '';

  void _onKey(String k) {
    if (k == Keys.ok) {
      Navigator.pop(context, _entry.isEmpty ? widget.current : parseQtyMilli(_entry));
      return;
    }
    setState(() => _entry = applyKey(_entry, k, allowDecimal: widget.product.unit.isLoose, maxDigits: 3));
  }

  @override
  Widget build(BuildContext context) {
    final loose = widget.product.unit.isLoose;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                '${widget.product.nameNe} · कति ${widget.product.unit.ne}?',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              _entry.isEmpty ? formatQty(widget.current) : _entry,
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: BColors.green),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Keypad(
          keyHeight: 68,
          bottomRow: loose ? const [Keys.dot, '0', Keys.backspace] : const [Keys.backspace, '0', Keys.ok],
          onKey: _onKey,
        ),
        if (loose) ...[
          const SizedBox(height: 10),
          BigButton(label: 'ठीक छ', trailingIcon: Icons.check_rounded, onPressed: () => _onKey(Keys.ok)),
        ],
      ],
    );
  }
}

/// "तपाईंले भन्नुभयो …" — confirm card for a voice add (principle 2).
class VoiceConfirmSheet extends StatelessWidget {
  const VoiceConfirmSheet({super.key, required this.heard, required this.product, required this.qtyMilli});

  final String heard;
  final Product product;
  final int qtyMilli;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 16, color: BColors.inkSoft),
            children: [
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.mic_none_rounded, color: BColors.orange, size: 22),
                ),
              ),
              const TextSpan(text: 'तपाईंले भन्नुभयो: '),
              TextSpan(
                text: '“$heard”',
                style: const TextStyle(fontWeight: FontWeight.w800, color: BColors.ink),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CardBox(
          borderColor: BColors.green,
          borderWidth: 2,
          radius: 20,
          child: Row(
            children: [
              LetterTile(letter: product.letter, bg: Color(product.tileBg), ink: Color(product.tileInk), size: 56),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${product.nameNe} × ${formatQty(qtyMilli)}${product.unit.isLoose ? ' ${product.unit.ne}' : ''}',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.15),
                  ),
                  Text(
                    '= ${formatRs(lineTotal(product.pricePaisa, qtyMilli))}',
                    style: const TextStyle(fontSize: 18, color: BColors.inkSoft),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ConfirmButtons(onNo: () => Navigator.pop(context, false), onYes: () => Navigator.pop(context, true)),
      ],
    );
  }
}
