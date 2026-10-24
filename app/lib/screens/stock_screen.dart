import 'package:flutter/material.dart';

import '../ai/assistant_service.dart';
import '../app_scope.dart';
import '../core/money.dart';
import '../core/qty.dart';
import '../data/bill.dart';
import '../data/models.dart';
import '../data/proposed_action.dart';
import '../data/shop_backend.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/product_tile.dart';
import 'add_stock_sheet.dart';
import 'bill_capture_screen.dart';
import 'bill_screen.dart';
import 'label_screen.dart';
import 'new_product_screen.dart';
import 'photo_capture_screen.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  String? _busy;

  /// Bill photo → the bill screen to check and save (docs/stock-from-bill.md).
  Future<void> _shootBill() async {
    final draft = await BillCaptureScreen.open(context);
    if (draft != null && mounted) await BillScreen.open(context, draft, aiHeader: draft.fromPhoto);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const ScreenHeader(title: 'स्टक थप्नुस्', subtitle: 'फोटो खिच्नुस्, भुन्टेले लेख्छ'),
                Expanded(child: _pick()),
              ],
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
        BigButton(
          key: const ValueKey('manual-bill'),
          label: 'हातैले बिल · धेरै सामान एकैचोटि',
          icon: Icons.receipt_long_outlined,
          outlineColor: BColors.green,
          foreground: BColors.green,
          height: 60,
          fontSize: 18,
          onPressed: () => BillScreen.open(context, BillDraft()),
        ),
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
