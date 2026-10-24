import 'package:flutter/material.dart';

import '../ai/assistant_service.dart';
import '../app_scope.dart';
import '../core/money.dart';
import '../core/qty.dart';
import '../data/models.dart';
import '../data/proposed_action.dart';
import '../data/shop_backend.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/product_tile.dart';
import '../widgets/delivery_info.dart';
import '../widgets/number_pad.dart';
import 'add_stock_sheet.dart';
import 'label_screen.dart';
import 'new_product_screen.dart';
import 'photo_capture_screen.dart';

enum _Stage { pick, review, saved }

/// A bill line under review; starts ticked only if the AI was confident.
class _Row {
  _Row(this.proposal) : qtyMilli = proposal.qtyMilli, on = proposal.confident;
  final BillLineProposal proposal;
  int qtyMilli;
  bool on;

  /// Sale price from now on; starts at the product's current price (S-6).
  int? salePricePaisa;
}

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  _Stage _stage = _Stage.pick;
  String? _busy;
  List<_Row> _rows = [];
  int _savedCount = 0;
  DeliveryInfo _billInfo = const DeliveryInfo();

  Future<void> _shootBill() async {
    setState(() => _busy = 'बिल');
    final lines = await context.assistant.readBill();
    if (!mounted) return;
    setState(() {
      _busy = null;
      final store = context.readStore;
      _rows = [for (final l in lines) _Row(l)..salePricePaisa = store.product(l.productId).pricePaisa];
      _stage = _Stage.review;
    });
  }

  Future<void> _voiceAdd() async {
    final store = context.readStore;
    setState(() => _busy = 'voice');
    final heard = await context.assistant.listen(VoiceContext.stock);
    if (!mounted) return;
    setState(() => _busy = null);
    final intent = heard.intent;
    if (intent is! ActionIntent || intent.action is! AddStock || store.validate(intent.action) != null) {
      showToast(context, 'बुझिनँ, फेरि भन्नुस्');
      return;
    }
    final action = intent.action as AddStock;
    final ok = await showBhunteSheet<bool>(
      context,
      (c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('“${heard.transcript}”', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          for (final l in action.lines)
            CardBox(
              borderColor: BColors.green,
              borderWidth: 2,
              child: Text(
                '${store.product(l.productId).nameNe} + ${formatQty(l.qtyMilli)} ${store.product(l.productId).unit.ne}'
                ' · ${formatRs(l.costPaisa)} दरले',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ),
          const SizedBox(height: 12),
          ConfirmButtons(onNo: () => Navigator.pop(c, false), onYes: () => Navigator.pop(c, true)),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    store.apply(action);
    showToast(context, 'स्टकमा थपियो');
  }

  void _save() {
    final selected = _rows.where((r) => r.on && r.qtyMilli > 0).toList();
    if (selected.isEmpty) return;
    context.readStore.addStock(
      [
        for (final r in selected)
          StockLine(
            productId: r.proposal.productId,
            qtyMilli: r.qtyMilli,
            costPaisa: r.proposal.costPaisa,
            salePricePaisa: r.salePricePaisa,
          ),
      ],
      source: StockSource.billPhoto,
      supplierName: _billInfo.supplierName,
      supplierPhone: _billInfo.supplierPhone,
      billNo: _billInfo.billNo,
    );
    setState(() {
      _savedCount = selected.length;
      _stage = _Stage.saved;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const ScreenHeader(title: 'स्टक थप्नुस्', subtitle: 'फोटो खिच्नुस्, भुन्टेले लेख्छ'),
                Expanded(
                  child: switch (_stage) {
                    _Stage.pick => _pick(),
                    _Stage.review => _review(),
                    _Stage.saved => _saved(),
                  },
                ),
              ],
            ),
            if (_busy == 'बिल')
              const BusyOverlay(
                icon: Icons.document_scanner_outlined,
                title: 'भुन्टेले बिल पढ्दैछ…',
                subtitle: '२–३ सेकेन्ड',
                accent: BColors.green,
              ),
            if (_busy == 'voice')
              const BusyOverlay(
                icon: Icons.mic_none_rounded,
                title: 'सुन्दैछु…',
                subtitle: 'जस्तै: “२० वटा साबुन आयो”',
              ),
          ],
        ),
      ),
    );
  }

  Widget _pick() {
    final store = context.store;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      children: [
        _PickButton(
          height: 112,
          filled: true,
          icon: Icons.receipt_outlined,
          title: 'बिलको फोटो',
          subtitle: 'होलसेलको बिल खिच्नुस् · सबै सामान एकैचोटि',
          onTap: _shootBill,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _PickButton(
                height: 84,
                icon: Icons.mic_none_rounded,
                iconColor: BColors.orange,
                title: 'बोलेर',
                subtitle: '“२० वटा साबुन आयो”',
                onTap: _voiceAdd,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PickButton(
                height: 84,
                icon: Icons.photo_camera_outlined,
                iconColor: BColors.green,
                title: 'सामानको फोटो',
                subtitle: 'नयाँ सामान, फोटोबाट',
                onTap: _fromPhotos,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('हातैले थप्नुस्', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const Text('सामान थिच्नुस्, कति आयो लेख्नुस्', style: TextStyle(fontSize: 15, color: BColors.inkSoft)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: BigButton(
                label: 'स्क्यान',
                icon: Icons.qr_code_scanner_rounded,
                outlineColor: BColors.green,
                foreground: BColors.green,
                height: 60,
                fontSize: 19,
                onPressed: _scanForStock,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: BigButton(
                label: 'नयाँ सामान',
                icon: Icons.add_rounded,
                height: 60,
                fontSize: 19,
                onPressed: _newProduct,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ProductGrid(
          products: store.products,
          tileFor: (p) => ProductTile(
            product: p,
            caption: stockLabel(p),
            warn: p.isLow,
            action: 'स्टक थप्नुस्',
            onTap: () => _addManually(p),
          ),
        ),
        if (store.archivedProducts.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('show-hidden'),
              icon: const Icon(Icons.visibility_off_outlined, color: BColors.inkSoft),
              label: Text(
                'लुकाइएका सामान (${store.archivedProducts.length})',
                style: const TextStyle(fontSize: 16, color: BColors.inkSoft),
              ),
              onPressed: _showHidden,
            ),
          ),
        const SizedBox(height: 14),
        const CardBox(
          radius: 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: BColors.blue),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'भुन्टेले पढेको कुरा तपाईंले हेरेर “ठीक छ” नथिचेसम्म स्टकमा जाँदैन।',
                  style: TextStyle(fontSize: 16, color: BColors.inkSoft, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addManually(Product p) async {
    final arrival = await showBhunteSheet<StockArrival>(context, (c) => AddStockSheet(product: p));
    if (arrival == null || !mounted) return;
    final store = context.readStore;
    final oldPrice = store.product(p.id).pricePaisa;
    final line = arrival.line;
    store.addStock(
      [line],
      source: StockSource.manual,
      supplierName: arrival.info.supplierName,
      supplierPhone: arrival.info.supplierPhone,
      billNo: arrival.info.billNo,
    );
    final now = store.product(p.id);
    final priceChanged = now.pricePaisa != oldPrice;
    showToast(
      context,
      '${p.nameNe} + ${formatQty(line.qtyMilli)} ${p.unit.ne} स्टकमा थपियो'
      '${priceChanged ? ' · अब ${formatRs(now.pricePaisa)}' : ''}',
    );
    if (priceChanged && now.hasOwnCode) await offerReprint(context, now, oldPrice);
  }

  Future<void> _scanForStock() async {
    final store = context.readStore;
    final code = await context.scanner.scan(context);
    if (code == null || !mounted) return;
    final p = store.productByBarcode(code);
    if (p != null && p.archived) {
      if (await offerUnhide(context, p) && mounted) await _addManually(store.product(p.id));
    } else if (p != null) {
      await _addManually(p);
    } else {
      showToast(context, 'नयाँ बारकोड · सामानको विवरण भर्नुस्');
      await NewProductScreen.open(context, barcode: code);
    }
  }

  Future<void> _newProduct() => NewProductScreen.open(context);

  /// New product from photos (docs/product-photos.md); a photographed code
  /// that is already in the shop goes to adding stock instead (F-4).
  Future<void> _fromPhotos() async {
    final outcome = await PhotoCaptureScreen.open(context);
    if (!mounted) return;
    switch (outcome) {
      case PhotoFoundExisting(:final product):
        final p = context.readStore.product(product.id);
        if (p.archived) {
          if (await offerUnhide(context, p) && mounted) await _addManually(context.readStore.product(p.id));
        } else {
          await _addManually(p);
        }
      case PhotoDraft():
        await NewProductScreen.open(context, photos: outcome);
      case null:
        break;
    }
  }

  Future<void> _showHidden() async {
    final p = await showProductPicker(
      context,
      title: 'लुकाइएका सामान',
      products: context.readStore.archivedProducts,
      caption: (_) => 'थिचेर फेरि देखाउनुस्',
    );
    if (p != null && mounted) await NewProductScreen.edit(context, p);
  }

  Future<void> _editRowPrice(_Row row) async {
    final current = row.salePricePaisa ?? 0;
    final text = await showNumberPad(
      context,
      title: '${row.proposal.label} · बेच्ने मूल्य',
      initial: current == 0 ? '' : formatAmount(current).replaceAll(',', ''),
      allowDecimal: true,
      maxDecimals: 2,
      prefix: 'रु ',
    );
    if (text == null || !mounted) return;
    final paisa = parseMoneyPaisa(text);
    if (paisa > 0) setState(() => row.salePricePaisa = paisa);
  }

  Widget _review() {
    final store = context.readStore;
    final selected = _rows.where((r) => r.on).toList();
    final unsure = _rows.where((r) => !r.proposal.confident && !r.on).length;
    final total = selected.fold(0, (s, r) => s + lineTotal(r.proposal.costPaisa, r.qtyMilli));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: BColors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: BColors.muted, width: 2),
                ),
                child: const Icon(Icons.receipt_long_outlined, color: BColors.muted, size: 36),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_rows.length} सामान भेटियो',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const Text('[होलसेल पसलको नाम] · आजको बिल', style: TextStyle(fontSize: 15, color: BColors.inkSoft)),
                    Text(
                      unsure > 0 ? '$unsure वटा जाँच्नुपर्छ' : 'सबै ठीक देखियो',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: unsure > 0 ? BColors.warnInk : BColors.greenDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            itemCount: _rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (c, i) => _BillRow(
              row: _rows[i],
              product: store.product(_rows[i].proposal.productId),
              onToggle: () => setState(() => _rows[i].on = !_rows[i].on),
              onDec: () => setState(() => _rows[i].qtyMilli = (_rows[i].qtyMilli - milli).clamp(0, 1 << 30)),
              onInc: () => setState(() => _rows[i].qtyMilli += milli),
              onPrice: () => _editRowPrice(_rows[i]),
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: BColors.white,
            border: Border(top: BorderSide(color: BColors.line)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('बिलको जम्मा', style: TextStyle(fontSize: 17, color: BColors.inkSoft)),
                  ),
                  Text(formatRs(total), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ],
              ),
              DeliveryInfoButton(info: _billInfo, onChanged: (v) => setState(() => _billInfo = v)),
              BigButton(
                label: 'स्टकमा थप्नुस् (${selected.length})',
                trailingIcon: Icons.check_rounded,
                height: 66,
                color: selected.isEmpty ? BColors.disabled : BColors.green,
                onPressed: selected.isEmpty ? null : _save,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _saved() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 112,
              height: 112,
              decoration: const BoxDecoration(color: BColors.green, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, size: 72, color: BColors.white),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$_savedCount सामान स्टकमा थपियो',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const Text(
            'बिलको फोटो पनि साँचेर राखियो',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, color: BColors.inkSoft),
          ),
          const SizedBox(height: 28),
          BigButton(label: 'अर्को बिल', height: 66, onPressed: () => setState(() => _stage = _Stage.pick)),
          const SizedBox(height: 12),
          BigButton(
            label: 'गृहमा फर्कनुस्',
            outlineColor: BColors.line,
            foreground: BColors.ink,
            height: 60,
            fontSize: 19,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  const _PickButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor = BColors.white,
    this.filled = false,
    this.height = 120,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool filled;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? BColors.white : BColors.ink;
    final sub = filled ? const Color(0xEBFFFFFF) : BColors.inkSoft;
    final texts = [
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: filled ? 26 : 19, fontWeight: FontWeight.w800, color: fg, height: 1.15),
      ),
      Text(
        subtitle,
        maxLines: filled ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: filled ? 16 : 13, color: sub, height: 1.25),
      ),
    ];
    return Semantics(
      button: true,
      label: '$title · $subtitle',
      excludeSemantics: true,
      child: CardBox(
        color: filled ? BColors.green : BColors.white,
        borderColor: filled ? BColors.green : BColors.line,
        radius: filled ? 24 : 20,
        padding: EdgeInsets.symmetric(horizontal: filled ? 22 : 14, vertical: filled ? 0 : 10),
        onTap: onTap,
        child: SizedBox(
          height: filled ? height : height - 20,
          child: filled
              ? Row(
                  children: [
                    Icon(icon, size: 48, color: BColors.white),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: texts,
                      ),
                    ),
                  ],
                )
              // Small cards sit two to a row: icon on top, text below.
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, size: 26, color: iconColor),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: texts),
                  ],
                ),
        ),
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.row,
    required this.product,
    required this.onToggle,
    required this.onDec,
    required this.onInc,
    required this.onPrice,
  });

  final _Row row;
  final Product product;
  final VoidCallback onToggle;
  final VoidCallback onDec;
  final VoidCallback onInc;
  final VoidCallback onPrice;

  @override
  Widget build(BuildContext context) {
    final flagged = !row.proposal.confident && !row.on;
    final cost = row.proposal.costPaisa;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: flagged ? BColors.warnCard : BColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: flagged ? BColors.warnBorder : BColors.line, width: 2),
      ),
      child: Row(
        children: [
          Semantics(
            checked: row.on,
            label: '${product.nameNe} समावेश गर्नुस्',
            excludeSemantics: true,
            child: Material(
              color: row.on ? BColors.green : BColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: BColors.green, width: 2),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onToggle,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.check_rounded, color: BColors.white, size: 26),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.proposal.label,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.15),
                ),
                Text(
                  '${formatRs(cost)} × ${formatQty(row.qtyMilli)} = ${formatRs(lineTotal(cost, row.qtyMilli))}',
                  style: const TextStyle(fontSize: 14, color: BColors.inkSoft),
                ),
                if (!row.proposal.confident && row.proposal.note != null)
                  Text(
                    row.proposal.note!,
                    style: const TextStyle(fontSize: 14, color: BColors.warnInk, fontWeight: FontWeight.w700),
                  ),
                _SalePriceChip(
                  key: ValueKey('bill-price-${product.id}'),
                  price: row.salePricePaisa ?? product.pricePaisa,
                  changed: (row.salePricePaisa ?? product.pricePaisa) != product.pricePaisa,
                  onTap: onPrice,
                ),
              ],
            ),
          ),
          RoundIconButton(
            icon: Icons.remove_rounded,
            label: 'घटाउनुस्',
            size: 44,
            border: BColors.line,
            onPressed: onDec,
          ),
          SizedBox(
            width: 40,
            child: Text(
              formatQty(row.qtyMilli),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          RoundIconButton(
            icon: Icons.add_rounded,
            label: 'बढाउनुस्',
            size: 44,
            background: BColors.greenTint,
            onPressed: onInc,
          ),
        ],
      ),
    );
  }
}

/// "बेच्ने: रु 25 ✎" on a bill line; green when it changes the price.
class _SalePriceChip extends StatelessWidget {
  const _SalePriceChip({super.key, required this.price, required this.changed, required this.onTap});

  final int price;
  final bool changed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'बेच्ने मूल्य ${formatRs(price)}, बदल्न थिच्नुस्',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'बेच्ने: ${formatRs(price)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: changed ? BColors.greenDark : BColors.ink,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.edit_outlined, size: 18, color: changed ? BColors.greenDark : BColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}
