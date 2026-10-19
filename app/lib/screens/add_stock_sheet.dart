import 'package:flutter/material.dart';

import '../core/keypad_input.dart';
import '../core/money.dart';
import '../core/qty.dart';
import '../data/models.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/keypad.dart';
import '../widgets/number_pad.dart';

/// "कति आयो?" — stock arriving for one product, in selling units or packs.
/// Returns the [StockLine] to add (always in selling units), or null.
class AddStockSheet extends StatefulWidget {
  const AddStockSheet({super.key, required this.product});

  final Product product;

  @override
  State<AddStockSheet> createState() => _AddStockSheetState();
}

class _AddStockSheetState extends State<AddStockSheet> {
  Product get p => widget.product;

  // Bills are usually in packs, so start there when the product has one.
  late bool _inPacks = p.hasPack;
  String _qty = '';
  late String _cost = _costTextFor(_inPacks);

  /// Default cost text: the product's last cost, per unit or per pack.
  String _costTextFor(bool packs) {
    final paisa = packs ? lineTotal(p.costPaisa, p.packSizeMilli!) : p.costPaisa;
    return paisa == 0 ? '' : formatAmount(paisa).replaceAll(',', '');
  }

  String get _unitName => _inPacks ? p.packName! : p.unit.ne;
  int get _enteredMilli => parseQtyMilli(_qty);
  int get _unitsMilli => _inPacks ? packsToUnitsMilli(_enteredMilli, p.packSizeMilli!) : _enteredMilli;
  int get _costEntered => parseMoneyPaisa(_cost);
  int get _unitCost => _inPacks ? unitCostFromPack(_costEntered, p.packSizeMilli!) : _costEntered;
  int get _total => lineTotal(_costEntered, _enteredMilli);

  void _onKey(String k) => setState(() {
    _qty = applyKey(_qty, k, allowDecimal: !_inPacks && p.unit.isLoose, maxDigits: 5);
  });

  void _setPacks(bool packs) {
    if (packs == _inPacks) return;
    setState(() {
      _inPacks = packs;
      _qty = '';
      _cost = _costTextFor(packs);
    });
  }

  Future<void> _editCost() async {
    final text = await showNumberPad(
      context,
      title: 'किनेको दर · प्रति $_unitName',
      initial: _cost,
      allowDecimal: true,
      maxDecimals: 2,
      prefix: 'रु ',
    );
    if (text != null) setState(() => _cost = text);
  }

  void _save() {
    if (_unitsMilli <= 0) return;
    Navigator.pop(
      context,
      StockLine(productId: p.id, qtyMilli: _unitsMilli, costPaisa: _unitCost, totalCostPaisa: _total),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loose = !_inPacks && p.unit.isLoose;
    final hasQty = _unitsMilli > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            LetterTile(letter: p.letter, bg: Color(p.tileBg), ink: Color(p.tileInk), size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.nameNe, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.15)),
                  Text(
                    'अहिले बाँकी: ${formatQty(p.stockMilli)} ${p.unit.ne}',
                    style: TextStyle(
                      fontSize: 15,
                      color: p.isLow ? BColors.warnInk : BColors.inkSoft,
                      fontWeight: p.isLow ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            RoundIconButton(
              icon: Icons.close_rounded,
              label: 'बन्द गर्नुस्',
              size: 44,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        if (p.hasPack) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: BigButton(
                  label: '${p.unit.ne}मा',
                  height: 52,
                  fontSize: 18,
                  outlineColor: _inPacks ? BColors.line : BColors.green,
                  foreground: _inPacks ? BColors.inkSoft : BColors.green,
                  onPressed: () => _setPacks(false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BigButton(
                  label: '${p.packName}मा (×${formatQty(p.packSizeMilli!)})',
                  height: 52,
                  fontSize: 18,
                  outlineColor: _inPacks ? BColors.green : BColors.line,
                  foreground: _inPacks ? BColors.green : BColors.inkSoft,
                  onPressed: () => _setPacks(true),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: PadField(
                label: 'कति $_unitName आयो?',
                value: _qty.isEmpty ? '0' : _qty,
                active: true,
                onTap: () {},
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PadField(
                key: const ValueKey('stock-cost'),
                label: 'दर · प्रति $_unitName',
                value: _cost.isEmpty ? 'रु —' : formatRs(_costEntered),
                onTap: _editCost,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Keypad(
          keyHeight: 54,
          bottomRow: loose ? const [Keys.dot, '0', Keys.backspace] : const [Keys.backspace, '0', ''],
          onKey: _onKey,
        ),
        const SizedBox(height: 10),
        Text(
          hasQty ? '+ ${formatQty(_unitsMilli)} ${p.unit.ne} · जम्मा ${formatRs(_total)}' : 'माथि कति आयो लेख्नुस्',
          key: const ValueKey('stock-summary'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        if (hasQty)
          Text(
            'नयाँ बाँकी: ${formatQty(p.stockMilli + _unitsMilli)} ${p.unit.ne}'
            '${_inPacks && _costEntered > 0 ? ' · ${formatRs(_unitCost)}/${p.unit.ne}' : ''}',
            style: const TextStyle(fontSize: 15, color: BColors.inkSoft),
          ),
        const SizedBox(height: 10),
        BigButton(
          label: 'स्टकमा थप्नुस्',
          trailingIcon: Icons.check_rounded,
          color: hasQty ? BColors.green : BColors.disabled,
          onPressed: hasQty ? _save : null,
        ),
      ],
    );
  }
}
