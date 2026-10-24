import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/money.dart';
import '../core/qty.dart';
import '../data/bill.dart';
import '../data/models.dart';
import '../data/shop_backend.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/delivery_info.dart';
import '../widgets/number_pad.dart';
import '../widgets/product_tile.dart';
import 'add_stock_sheet.dart';
import 'new_product_screen.dart';

/// One delivery, checked line by line and saved once (docs/stock-from-bill.md).
/// Filled from a bill photo, or empty for a manual bill. Returns the saved
/// [Delivery], or null.
class BillScreen extends StatefulWidget {
  const BillScreen({super.key, required this.draft, this.aiHeader = false});

  final BillDraft draft;

  /// The supplier/bill details were read by Bhunte (shown with a tag).
  final bool aiHeader;

  static Future<Delivery?> open(BuildContext context, BillDraft draft, {bool aiHeader = false}) =>
      Navigator.of(context).push<Delivery>(
        MaterialPageRoute(
          builder: (_) => BillScreen(draft: draft, aiHeader: aiHeader),
        ),
      );

  @override
  State<BillScreen> createState() => _BillScreenState();
}

class _BillScreenState extends State<BillScreen> {
  BillDraft get _bill => widget.draft;
  Delivery? _saved;

  StockLine _lineFor(BillRow r, Product p) {
    final packs = r.inPacks && p.hasPack;
    // When the printed amount doesn't match, start from qty × rate (BL-2); the sheet shows both to confirm.
    final total = r.amountMismatch ? lineTotal(r.ratePaisa!, r.qtyMilli) : r.totalPaisa;
    return StockLine(
      productId: p.id,
      qtyMilli: r.unitsMilli,
      costPaisa: r.unitsMilli <= 0 ? 0 : unitCostFromPack(total, r.unitsMilli),
      totalCostPaisa: total,
      salePricePaisa: r.salePricePaisa ?? p.pricePaisa,
      packsMilli: packs ? r.qtyMilli + r.freeMilli : null,
    );
  }

  /// The sheet's answer becomes the row's numbers; what it checked is no longer in doubt.
  void _applyLine(BillRow r, StockLine l, Product p) {
    final packs = l.packsMilli;
    r
      ..inPacks = packs != null
      ..qtyMilli = packs ?? l.qtyMilli
      ..freeMilli = 0
      ..packSizeMilli = packs != null ? p.packSizeMilli : null
      ..amountPaisa = l.totalCostPaisa
      ..ratePaisa = packs != null ? unitCostFromPack(l.totalCostPaisa, packs) : l.costPaisa
      ..salePricePaisa = l.salePricePaisa == p.pricePaisa ? null : l.salePricePaisa
      ..ticked = true;
    r.issues.removeAll(const [RowIssue.unsureNumbers, RowIssue.unitConflict]);
    if (r.issues.isEmpty) r.note = null;
  }

  Future<void> _editRow(BillRow r) async {
    final id = r.productId;
    if (id == null) return;
    final p = context.readStore.product(id);
    final arrival = await showBhunteSheet<StockArrival>(
      context,
      (c) => AddStockSheet(product: p, initial: _lineFor(r, p), forBill: true),
    );
    if (arrival == null || !mounted) return;
    setState(() => _applyLine(r, arrival.line, context.readStore.product(id)));
  }

  /// Manual lines: a product already on the bill opens its row instead (BR10).
  Future<void> _addProduct(Product p) async {
    final existing = _bill.rows.where((r) => r.productId == p.id && !r.fromBill).firstOrNull;
    if (existing != null) return _editRow(existing);
    final arrival = await showBhunteSheet<StockArrival>(context, (c) => AddStockSheet(product: p, forBill: true));
    if (arrival == null || !mounted) return;
    final row = BillRow(productId: p.id);
    setState(() {
      _applyLine(row, arrival.line, context.readStore.product(p.id));
      _bill.rows.add(row);
    });
  }

  Future<void> _pickProduct() async {
    final p = await showProductPicker(context, title: 'कुन सामान आयो?', caption: stockLabel);
    if (p != null && mounted) await _addProduct(p);
  }

  Future<void> _scan() async {
    final store = context.readStore;
    final code = await context.scanner.scan(context);
    if (code == null || !mounted) return;
    var p = store.productByBarcode(code);
    if (p != null && p.archived) {
      if (!await offerUnhide(context, p) || !mounted) return;
      p = store.product(p.id);
    }
    if (p == null) {
      showToast(context, 'नयाँ बारकोड · सामानको विवरण भर्नुस्');
      p = await NewProductScreen.open(context, barcode: code, fromBill: const BillPrefill());
      if (p == null || !mounted) return;
    }
    await _addProduct(p);
  }

  Future<void> _makeProduct(BillRow r) async {
    final made = await NewProductScreen.open(
      context,
      fromBill: BillPrefill(
        nameNe: r.suggestedNameNe ?? r.text,
        nameEn: r.text,
        unit: r.unitHint,
        costPaisa: r.unitCostPaisa > 0 ? r.unitCostPaisa : null,
      ),
    );
    if (made == null || !mounted) return;
    setState(() => _link(r, made));
  }

  Future<void> _chooseProduct(BillRow r) async {
    final p = await showProductPicker(context, title: 'बिलको "${r.text ?? ''}" कुन सामान हो?');
    if (p != null && mounted) setState(() => _link(r, p));
  }

  /// The row now points at [p]; a pack size is taken from it when it has one.
  void _link(BillRow r, Product p) {
    r.productId = p.id;
    r.skipped = false;
    r.issues.removeAll(const [RowIssue.unsureMatch, RowIssue.hiddenProduct, RowIssue.unitConflict]);
    if (r.inPacks && p.hasPack) {
      r.packSizeMilli = p.packSizeMilli;
      r.issues.remove(RowIssue.packUnknown);
    } else if (r.inPacks && r.packSizeMilli == null) {
      r.issues.add(RowIssue.packUnknown);
    }
    r.ticked = r.canSave;
  }

  Future<void> _askPackSize(BillRow r) async {
    final p = context.readStore.product(r.productId!);
    final text = await showNumberPad(
      context,
      title: 'एक ${r.packWord ?? 'प्याक'}मा कति ${p.unit.ne}?',
      allowDecimal: p.unit.isLoose,
      suffix: ' ${p.unit.ne}',
    );
    final size = text == null ? 0 : parseQtyMilli(text);
    if (size <= 0 || !mounted) return;
    setState(() {
      r.packSizeMilli = size;
      r.issues.remove(RowIssue.packUnknown);
      r.ticked = r.canSave;
    });
  }

  Future<void> _unhide(BillRow r) async {
    final p = context.readStore.product(r.productId!);
    if (!await offerUnhide(context, p) || !mounted) return;
    setState(() {
      r.issues.remove(RowIssue.hiddenProduct);
      r.ticked = r.canSave;
    });
  }

  Future<void> _editTotal() async {
    final current = _bill.header.totalPaisa;
    final text = await showNumberPad(
      context,
      title: 'बिलमा लेखेको जम्मा',
      initial: current == null ? '' : formatAmount(current).replaceAll(',', ''),
      allowDecimal: true,
      maxDecimals: 2,
      maxDigits: 8,
      prefix: 'रु ',
    );
    if (text == null || !mounted) return;
    final paisa = parseMoneyPaisa(text);
    setState(() => _bill.header = _bill.header.copyWith(totalPaisa: paisa, clearTotal: paisa <= 0));
  }

  void _save() {
    if (_bill.ticked.isEmpty) return;
    final Delivery d;
    try {
      d = context.readStore.receiveBill(_bill);
    } on ArgumentError catch (e) {
      showToast(context, '${e.message}');
      return;
    }
    setState(() => _saved = d);
  }

  Future<bool> _confirmLeave() async {
    final yes = await showBhunteSheet<bool>(
      context,
      (c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('बिल नसकी जाने?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            _bill.fromPhoto
                ? 'पढेको बिल हराउँछ। केही पनि स्टकमा जाँदैन।'
                : 'थपेका ${_bill.rows.length} सामान हराउँछन्।',
            style: const TextStyle(fontSize: 16, color: BColors.inkSoft),
          ),
          const SizedBox(height: 16),
          BigButton(
            key: const ValueKey('leave-yes'),
            label: 'हो, छोड्नुस्',
            color: BColors.orange,
            onPressed: () => Navigator.pop(c, true),
          ),
          const SizedBox(height: 8),
          BigButton(
            label: 'रद्द',
            outlineColor: BColors.line,
            foreground: BColors.ink,
            height: 56,
            fontSize: 18,
            onPressed: () => Navigator.pop(c, false),
          ),
        ],
      ),
    );
    return yes == true;
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    return PopScope<Delivery>(
      canPop: saved != null || _bill.rows.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(body: SafeArea(child: saved == null ? _editing() : _done(saved))),
    );
  }

  Widget _done(Delivery d) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle_rounded, color: BColors.green, size: 96),
        const SizedBox(height: 12),
        const Text(
          'सकियो',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
        Text(
          '${d.batchCount} सामान स्टकमा थपियो · जम्मा ${formatRs(d.totalCostPaisa)}',
          key: const ValueKey('bill-saved'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, color: BColors.inkSoft),
        ),
        const SizedBox(height: 24),
        BigButton(label: 'ठीक छ', trailingIcon: Icons.check_rounded, onPressed: () => Navigator.of(context).pop(d)),
      ],
    ),
  );

  Widget _editing() {
    final store = context.store;
    final rows = _bill.rows;
    final toCheck = rows.where((r) => !r.ticked && !r.skipped).length;
    final diff = _bill.totalDifferencePaisa;
    final h = _bill.header;
    final ticked = _bill.ticked.length;
    return Column(
      children: [
        ScreenHeader(
          title: _bill.fromPhoto ? 'बिल जाँच्नुस्' : 'हातैले बिल',
          subtitle: _bill.fromPhoto
              ? '${rows.length} सामान भेटियो${toCheck > 0 ? ' · $toCheck जाँच्नुपर्छ' : ''}'
              : 'सामान थिच्नुस्, कति आयो लेख्नुस्',
        ),
        Expanded(
          child: ListView(
            key: const ValueKey('bill-list'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              if (_bill.notice != null) ...[
                CardBox(
                  radius: 16,
                  color: BColors.warnBg,
                  borderColor: BColors.warnBorder,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _bill.notice!,
                    style: const TextStyle(fontSize: 16, color: BColors.warnInk, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (diff != null) ...[
                CardBox(
                  key: const ValueKey('bill-total-warning'),
                  radius: 16,
                  color: BColors.warnBg,
                  borderColor: BColors.warnBorder,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'बिलको जम्मा मिलेन: लाइन ${formatRs(_bill.linesTotalPaisa + _bill.extrasPaisa)} · बिलमा ${formatRs(h.totalPaisa!)}',
                    style: const TextStyle(fontSize: 16, color: BColors.warnInk, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              for (var i = 0; i < rows.length; i++) ...[
                _RowTile(
                  key: ValueKey('row-$i'),
                  index: i,
                  row: rows[i],
                  product: rows[i].productId == null ? null : store.product(rows[i].productId!),
                  onTick: () => setState(() => rows[i].ticked = rows[i].canSave && !rows[i].ticked),
                  onEdit: () => _editRow(rows[i]),
                  onRemove: () => setState(() => rows.removeAt(i)),
                  onMake: () => _makeProduct(rows[i]),
                  onChoose: () => _chooseProduct(rows[i]),
                  onSkip: () => setState(() => rows[i].skipped = true),
                  onPackSize: () => _askPackSize(rows[i]),
                  onKeepPack: (v) => setState(() => rows[i].keepPack = v),
                  onUnhide: () => _unhide(rows[i]),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 4),
              Text(
                rows.isEmpty ? 'कुन सामान आयो?' : '+ सामान थप्नुस्',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: BigButton(
                      key: const ValueKey('bill-scan'),
                      label: 'स्क्यान',
                      icon: Icons.qr_code_scanner_rounded,
                      outlineColor: BColors.green,
                      foreground: BColors.green,
                      height: 56,
                      fontSize: 18,
                      onPressed: _scan,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: BigButton(
                      key: const ValueKey('bill-pick'),
                      label: 'सबै सामान',
                      icon: Icons.grid_view_rounded,
                      outlineColor: BColors.green,
                      foreground: BColors.green,
                      height: 56,
                      fontSize: 18,
                      onPressed: _pickProduct,
                    ),
                  ),
                ],
              ),
              if (!_bill.fromPhoto) ...[
                const SizedBox(height: 10),
                ProductGrid(
                  products: store.products,
                  maxTiles: 8,
                  onMore: _pickProduct,
                  tileFor: (p) => ProductTile(
                    product: p,
                    caption: stockLabel(p),
                    action: 'बिलमा थप्नुस्',
                    badgeMilli: rows.where((r) => r.productId == p.id).fold(0, (s, r) => s + r.unitsMilli),
                    onTap: () => _addProduct(p),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (widget.aiHeader && !(h.supplierName == null && h.billNo == null))
                const Align(alignment: Alignment.centerLeft, child: _AiTag()),
              DeliveryInfoButton(
                info: DeliveryInfo(supplierName: h.supplierName, supplierPhone: h.supplierPhone, billNo: h.billNo),
                onChanged: (v) => setState(
                  () => _bill.header = BillHeader(
                    supplierName: v.supplierName,
                    supplierPhone: v.supplierPhone,
                    billNo: v.billNo,
                    billDateText: h.billDateText,
                    totalPaisa: h.totalPaisa,
                    vatPaisa: h.vatPaisa,
                    discountPaisa: h.discountPaisa,
                  ),
                ),
              ),
              if (h.billDateText != null)
                Text('बिलको मिति: ${h.billDateText}', style: const TextStyle(fontSize: 15, color: BColors.inkSoft)),
              const SizedBox(height: 6),
              PadField(
                key: const ValueKey('bill-total'),
                label: 'बिलमा लेखेको जम्मा (नभए पनि हुन्छ)',
                value: h.totalPaisa == null ? 'रु —' : formatRs(h.totalPaisa!),
                onTap: _editTotal,
              ),
            ],
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: BColors.white,
            border: Border(top: BorderSide(color: BColors.line)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if ((h.vatPaisa ?? 0) != 0 || (h.discountPaisa ?? 0) != 0)
                Text(
                  [
                    if ((h.discountPaisa ?? 0) != 0) 'छुट −${formatRs(h.discountPaisa!)}',
                    if ((h.vatPaisa ?? 0) != 0) 'VAT +${formatRs(h.vatPaisa!)}',
                    'सामानको लागतमा बाँडिन्छ',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 14, color: BColors.inkSoft),
                ),
              Row(
                children: [
                  const Expanded(
                    child: Text('छानिएको जम्मा', style: TextStyle(fontSize: 17, color: BColors.inkSoft)),
                  ),
                  Text(
                    formatRs(_bill.tickedTotalPaisa),
                    key: const ValueKey('bill-ticked-total'),
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              BigButton(
                key: const ValueKey('bill-save'),
                label: 'स्टकमा थप्नुस् ($ticked)',
                trailingIcon: Icons.check_rounded,
                height: 66,
                color: ticked == 0 ? BColors.disabled : BColors.green,
                onPressed: ticked == 0 ? null : _save,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({
    super.key,
    required this.index,
    required this.row,
    required this.product,
    required this.onTick,
    required this.onEdit,
    required this.onRemove,
    required this.onMake,
    required this.onChoose,
    required this.onSkip,
    required this.onPackSize,
    required this.onKeepPack,
    required this.onUnhide,
  });

  final int index;
  final BillRow row;
  final Product? product;
  final VoidCallback onTick, onEdit, onRemove, onMake, onChoose, onSkip, onPackSize, onUnhide;
  final ValueChanged<bool> onKeepPack;

  List<String> _problems(Product? p) => [
    if (row.amountMismatch)
      'हिसाब मिलेन: ${formatQty(row.qtyMilli)} × ${formatRs(row.ratePaisa!)} = '
          '${formatRs(lineTotal(row.ratePaisa!, row.qtyMilli))}, बिलमा ${formatRs(row.amountPaisa!)}',
    for (final issue in row.issues)
      switch (issue) {
        RowIssue.unsureNumbers => 'अङ्क प्रस्ट भएन — जाँच्नुस्',
        RowIssue.unsureMatch => 'सामान मिलेको पक्का छैन',
        RowIssue.packUnknown => 'एक ${row.packWord ?? 'प्याक'}मा कति ${p?.unit.ne ?? ''}?',
        RowIssue.unitConflict => 'एकाइ मिलेन: बिलमा ${row.packWord ?? '?'}, सामान ${p?.unit.ne ?? ''}मा',
        RowIssue.hiddenProduct => 'लुकाइएको सामान',
      },
    ?row.note,
  ];

  @override
  Widget build(BuildContext context) {
    final p = product;
    final isNew = p == null;
    final problems = _problems(p);
    final warn = !isNew && !row.ticked && problems.isNotEmpty;
    final units = row.unitsMilli;
    final qtyText = row.inPacks
        ? '${formatQty(row.qtyMilli + row.freeMilli)} ${row.packWord ?? p?.packName ?? 'प्याक'}'
              '${units > 0 ? ' (+${formatQty(units)} ${p?.unit.ne ?? ''})' : ''}'
        : '+ ${formatQty(units)}${p == null ? '' : ' ${p.unit.ne}'}';
    final price = row.salePricePaisa;
    return CardBox(
      radius: 16,
      color: isNew
          ? BColors.blueTint
          : warn
          ? BColors.warnCard
          : BColors.white,
      borderColor: isNew
          ? BColors.blue
          : warn
          ? BColors.warnBorder
          : (row.ticked ? BColors.green : BColors.line),
      borderWidth: row.ticked || warn || isNew ? 2 : 1,
      padding: const EdgeInsets.fromLTRB(6, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isNew)
                Semantics(
                  checked: row.ticked,
                  label: row.ticked ? 'छानिएको' : 'छानिएको छैन',
                  child: IconButton(
                    key: ValueKey('tick-$index'),
                    iconSize: 32,
                    onPressed: row.canSave ? onTick : null,
                    icon: Icon(
                      row.ticked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                      color: row.ticked ? BColors.green : BColors.muted,
                    ),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.fiber_new_outlined, color: BColors.blue, size: 32),
                ),
              Expanded(
                child: InkWell(
                  onTap: isNew ? null : onEdit,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isNew) ...[ProductPicture(product: p, size: 44), const SizedBox(width: 10)],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isNew ? (row.text ?? '') : p.nameNe,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.2),
                              ),
                              if (row.text != null && !isNew)
                                Text(
                                  'बिलमा: ${row.text}',
                                  style: const TextStyle(fontSize: 13, color: BColors.inkSoft),
                                ),
                              Text(
                                '$qtyText · ${row.unitCostPaisa > 0 ? '${formatRs(row.unitCostPaisa)}/${p?.unit.ne ?? 'एउटा'} · ' : ''}'
                                '${formatRs(row.totalPaisa)}',
                                key: ValueKey('row-summary-$index'),
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              if (!isNew)
                                Text(
                                  price == null || price == p.pricePaisa
                                      ? 'बेच्ने: ${formatRs(p.pricePaisa)}'
                                      : 'बेच्ने: ${formatRs(p.pricePaisa)} → ${formatRs(price)}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: price == null || price == p.pricePaisa ? BColors.inkSoft : BColors.greenDark,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!row.fromBill)
                RoundIconButton(
                  key: ValueKey('remove-$index'),
                  icon: Icons.close_rounded,
                  label: 'हटाउनुस्',
                  size: 44,
                  onPressed: onRemove,
                ),
            ],
          ),
          for (final text in problems)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 2),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isNew ? BColors.blue : BColors.warnInk,
                ),
              ),
            ),
          if (row.issues.contains(RowIssue.packUnknown))
            _action(ValueKey('pack-size-$index'), 'कति छ लेख्नुस्', Icons.dialpad_rounded, onPackSize),
          if (row.inPacks && p != null && !p.hasPack && row.packSizeMilli != null)
            SwitchListTile(
              key: ValueKey('keep-pack-$index'),
              contentPadding: const EdgeInsets.only(left: 12),
              value: row.keepPack,
              onChanged: onKeepPack,
              title: Text(
                'यो सामानमा सधैं: १ ${row.packWord ?? 'प्याक'} = ${formatQty(row.packSizeMilli!)} ${p.unit.ne}',
                style: const TextStyle(fontSize: 15),
              ),
            ),
          if (row.issues.contains(RowIssue.hiddenProduct))
            _action(ValueKey('unhide-$index'), 'फेरि देखाउनुस्', Icons.visibility_outlined, onUnhide),
          if (row.issues.contains(RowIssue.unsureMatch) || row.issues.contains(RowIssue.unitConflict))
            _action(ValueKey('choose-$index'), 'अर्को सामान छान्नुस्', Icons.swap_horiz_rounded, onChoose),
          if (isNew && !row.skipped) ...[
            const SizedBox(height: 6),
            BigButton(
              key: ValueKey('make-$index'),
              label: 'नयाँ सामान बनाउनुस्',
              icon: Icons.add_rounded,
              color: BColors.blue,
              height: 52,
              fontSize: 17,
              onPressed: onMake,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: BigButton(
                    key: ValueKey('choose-$index'),
                    label: 'पसलको सामान',
                    outlineColor: BColors.blue,
                    foreground: BColors.blue,
                    height: 48,
                    fontSize: 16,
                    onPressed: onChoose,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BigButton(
                    key: ValueKey('skip-$index'),
                    label: 'छोड्नुस्',
                    outlineColor: BColors.line,
                    foreground: BColors.inkSoft,
                    height: 48,
                    fontSize: 16,
                    onPressed: onSkip,
                  ),
                ),
              ],
            ),
          ],
          if (isNew && row.skipped)
            const Padding(
              padding: EdgeInsets.only(left: 12, top: 4),
              child: Text('छोडियो — स्टकमा जाँदैन', style: TextStyle(fontSize: 14, color: BColors.inkSoft)),
            ),
        ],
      ),
    );
  }

  Widget _action(Key key, String label, IconData icon, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(left: 8, top: 6),
    child: Align(
      alignment: Alignment.centerLeft,
      child: BigButton(
        key: key,
        label: label,
        icon: icon,
        outlineColor: BColors.warnBorder,
        foreground: BColors.warnInk,
        height: 48,
        fontSize: 16,
        onPressed: onTap,
      ),
    ),
  );
}

class _AiTag extends StatelessWidget {
  const _AiTag();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: BColors.greenTint, borderRadius: BorderRadius.circular(999)),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.auto_awesome_rounded, size: 14, color: BColors.greenDark),
        SizedBox(width: 4),
        Text(
          'भुन्टेले भरेको',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BColors.greenDark),
        ),
      ],
    ),
  );
}
