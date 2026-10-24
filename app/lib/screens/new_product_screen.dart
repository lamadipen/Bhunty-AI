import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/barcode.dart';
import '../core/money.dart';
import '../core/qty.dart';
import '../data/models.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../labels/product_label.dart';
import '../widgets/number_pad.dart';
import 'label_screen.dart';

/// Adds a product to the catalog. The name is typed once — the only text
/// keyboard in the app — until voice/photo naming arrives (Phase 2).
/// Numbers use the keypad. Returns the new [Product], or null.
class NewProductScreen extends StatefulWidget {
  const NewProductScreen({super.key, this.barcode});

  /// Pre-filled when the user scanned a code that isn't in the catalog yet.
  final String? barcode;

  static Future<Product?> open(BuildContext context, {String? barcode}) =>
      Navigator.of(context).push<Product>(MaterialPageRoute(builder: (_) => NewProductScreen(barcode: barcode)));

  @override
  State<NewProductScreen> createState() => _NewProductScreenState();
}

const _packNames = ['कार्टुन', 'बोरा', 'बट्टा', 'दर्जन', 'बन्डल'];

class _NewProductScreenState extends State<NewProductScreen> {
  final _nameNe = TextEditingController();
  final _nameEn = TextEditingController();
  Unit _unit = Unit.piece;
  String _price = '';
  String _cost = '';
  String _opening = '';
  String _lowAt = '';
  String? _packName;
  String _packSize = '';
  late String? _barcode = widget.barcode;
  LabelKind _labelKind = LabelKind.barcode;

  /// The code was generated here (no barcode on the packet).
  bool get _ownCode => _barcode != null && isInStoreCode(_barcode!);
  String? _error;

  @override
  void dispose() {
    _nameNe.dispose();
    _nameEn.dispose();
    super.dispose();
  }

  Future<void> _pad({
    required String title,
    required String current,
    required ValueChanged<String> set,
    bool money = false,
    bool decimal = false,
  }) async {
    _closeKeyboard();
    final text = await showNumberPad(
      context,
      title: title,
      initial: current,
      allowDecimal: money || decimal,
      maxDecimals: money ? 2 : 3,
      prefix: money ? 'रु ' : '',
      suffix: money ? '' : ' ${_unit.ne}',
    );
    if (text != null) setState(() => set(text));
  }

  /// The name keyboard goes away as soon as the user moves on to tap fields.
  void _closeKeyboard() => FocusScope.of(context).unfocus();

  Future<void> _scan() async {
    _closeKeyboard();
    final code = await context.scanner.scan();
    if (code != null && mounted) setState(() => _barcode = code);
  }

  void _generate() {
    _closeKeyboard();
    setState(() => _barcode = context.readStore.newInStoreCode());
  }

  void _save() {
    _closeKeyboard();
    final store = context.readStore;
    final price = parseMoneyPaisa(_price);
    final cost = parseMoneyPaisa(_cost);
    final packSize = _packName == null ? null : parseQtyMilli(_packSize);
    final problem = store.validateNewProduct(
      nameNe: _nameNe.text,
      pricePaisa: price,
      costPaisa: cost,
      barcode: _barcode,
      packName: _packName,
      packSizeMilli: packSize,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final product = store.addProduct(
      nameNe: _nameNe.text,
      nameEn: _nameEn.text,
      pricePaisa: price,
      costPaisa: cost,
      unit: _unit,
      openingStockMilli: parseQtyMilli(_opening),
      lowStockAtMilli: _lowAt.isEmpty ? null : parseQtyMilli(_lowAt),
      barcode: _barcode,
      packName: _packName,
      packSizeMilli: packSize,
      labelKind: _labelKind,
    );
    showToast(context, '${product.nameNe} थपियो');
    if (product.hasOwnCode) {
      // Its own code is only useful once it's stuck on the product: go straight to printing.
      Navigator.pushReplacement(context, LabelScreen.route<Product>(product.id), result: product);
    } else {
      Navigator.pop(context, product);
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = parseMoneyPaisa(_price), cost = parseMoneyPaisa(_cost);
    final margin = price - cost;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'नयाँ सामान', subtitle: 'एक पटक भर्नुस्, सधैं काम लाग्छ'),
            Expanded(
              child: ListView(
                key: const ValueKey('new-product-list'),
                padding: const EdgeInsets.all(16),
                children: [
                  _label('सामानको नाम'),
                  _textField(_nameNe, hint: 'जस्तै: नुन', big: true, key: const ValueKey('name-ne')),
                  const SizedBox(height: 8),
                  _textField(_nameEn, hint: 'English name (नभए पनि हुन्छ)', key: const ValueKey('name-en')),
                  const SizedBox(height: 16),
                  _label('कसरी बेच्नुहुन्छ?'),
                  _choices<Unit>(
                    values: Unit.values,
                    selected: _unit,
                    label: (u) => u.ne,
                    onPick: (u) => setState(() => _unit = u),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: PadField(
                          key: const ValueKey('field-price'),
                          label: 'बेच्ने मूल्य · प्रति ${_unit.ne}',
                          value: _price.isEmpty ? 'रु —' : formatRs(price),
                          onTap: () => _pad(
                            title: 'बेच्ने मूल्य · प्रति ${_unit.ne}',
                            current: _price,
                            money: true,
                            set: (v) => _price = v,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PadField(
                          key: const ValueKey('field-cost'),
                          label: 'किनेको मूल्य · प्रति ${_unit.ne}',
                          value: _cost.isEmpty ? 'रु —' : formatRs(cost),
                          onTap: () => _pad(
                            title: 'किनेको मूल्य · प्रति ${_unit.ne}',
                            current: _cost,
                            money: true,
                            set: (v) => _cost = v,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (price > 0 && _cost.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        margin >= 0
                            ? 'नाफा: ${formatRs(margin)} प्रति ${_unit.ne}'
                            : 'किनेको भन्दा सस्तो बेच्दै हुनुहुन्छ',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: margin >= 0 ? BColors.greenDark : BColors.warnInk,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: PadField(
                          key: const ValueKey('field-opening'),
                          label: 'अहिले कति छ?',
                          value: '${_opening.isEmpty ? '0' : _opening} ${_unit.ne}',
                          onTap: () => _pad(
                            title: 'अहिले कति छ?',
                            current: _opening,
                            decimal: _unit.isLoose,
                            set: (v) => _opening = v,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PadField(
                          label: 'कति भए सूचना दिने?',
                          value: _lowAt.isEmpty ? '—' : '$_lowAt ${_unit.ne}',
                          onTap: () => _pad(
                            title: 'यति भन्दा कम भए सूचना दिने',
                            current: _lowAt,
                            decimal: _unit.isLoose,
                            set: (v) => _lowAt = v,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _label('होलसेलबाट कसरी आउँछ?'),
                  _choices<String?>(
                    values: [null, ..._packNames],
                    selected: _packName,
                    label: (n) => n ?? 'खुद्रै (${_unit.ne}मा)',
                    onPick: (n) => setState(() => _packName = n),
                  ),
                  if (_packName != null) ...[
                    const SizedBox(height: 8),
                    PadField(
                      key: const ValueKey('field-pack'),
                      label: 'एक $_packNameमा कति ${_unit.ne}?',
                      value: _packSize.isEmpty ? '—' : '$_packSize ${_unit.ne}',
                      onTap: () => _pad(
                        title: 'एक $_packNameमा कति ${_unit.ne}?',
                        current: _packSize,
                        decimal: _unit.isLoose,
                        set: (v) => _packSize = v,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _label('बारकोड'),
                  if (_barcode == null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: BigButton(
                            label: 'स्क्यान',
                            icon: Icons.qr_code_scanner_rounded,
                            outlineColor: BColors.line,
                            foreground: BColors.ink,
                            height: 56,
                            fontSize: 17,
                            onPressed: _scan,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: BigButton(
                            key: const ValueKey('make-own-code'),
                            label: 'आफ्नै कोड',
                            icon: Icons.qr_code_2_rounded,
                            outlineColor: BColors.green,
                            foreground: BColors.green,
                            height: 56,
                            fontSize: 17,
                            onPressed: _generate,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'प्याकेटमा बारकोड छैन? आफ्नै बारकोड वा QR बनाएर टाँस्नुस्। नभए पनि हुन्छ।',
                      style: TextStyle(fontSize: 14, color: BColors.inkSoft),
                    ),
                  ] else if (_ownCode)
                    CardBox(
                      radius: 16,
                      borderColor: BColors.green,
                      borderWidth: 2,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'पसलको आफ्नै कोड',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: BColors.greenDark),
                                ),
                              ),
                              RoundIconButton(
                                icon: Icons.close_rounded,
                                label: 'कोड हटाउनुस्',
                                size: 44,
                                onPressed: () => setState(() => _barcode = null),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(border: Border.all(color: BColors.line)),
                              child: FittedBox(
                                child: ProductLabel(
                                  nameNe: _nameNe.text.trim().isEmpty ? 'सामानको नाम' : _nameNe.text.trim(),
                                  priceText: _price.isEmpty
                                      ? 'रु —'
                                      : '${formatRs(price)}${_unit.isLoose ? '/${_unit.ne}' : ''}',
                                  code: _barcode!,
                                  kind: _labelKind,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _choices<LabelKind>(
                            values: LabelKind.values,
                            selected: _labelKind,
                            label: (k) => k == LabelKind.barcode ? 'बारकोड' : 'QR',
                            onPick: (k) => setState(() => _labelKind = k),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _labelKind == LabelKind.barcode
                                ? 'बारकोड: फोनको क्यामेरा र दोकानको स्क्यानर दुवैले पढ्छ।'
                                : 'QR: सानो वा गोलो सामानमा राम्रो; फोनको क्यामेराले जुनसुकै कोणबाट पढ्छ।',
                            style: const TextStyle(fontSize: 14, color: BColors.inkSoft),
                          ),
                        ],
                      ),
                    )
                  else
                    CardBox(
                      radius: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.qr_code_2_rounded, color: BColors.green),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_barcode!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          ),
                          RoundIconButton(
                            icon: Icons.close_rounded,
                            label: 'बारकोड हटाउनुस्',
                            size: 44,
                            onPressed: () => setState(() => _barcode = null),
                          ),
                        ],
                      ),
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
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: const TextStyle(fontSize: 16, color: BColors.warnInk, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  BigButton(label: 'सामान थप्नुस्', trailingIcon: Icons.check_rounded, height: 66, onPressed: _save),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
  );

  Widget _textField(TextEditingController c, {required String hint, bool big = false, Key? key}) => TextField(
    key: key,
    controller: c,
    textInputAction: TextInputAction.done,
    onChanged: (_) => setState(() => _error = null), // also refreshes the label preview
    style: TextStyle(fontSize: big ? 22 : 17, fontWeight: big ? FontWeight.w700 : FontWeight.w400),
    decoration: InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: BColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: BColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: BColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: BColors.green, width: 2),
      ),
    ),
  );

  Widget _choices<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onPick,
  }) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final v in values)
        Semantics(
          button: true,
          selected: v == selected,
          child: Material(
            color: v == selected ? BColors.greenTint : BColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: v == selected ? BColors.green : BColors.line, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                _closeKeyboard();
                onPick(v);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: SizedBox(
                  height: 52,
                  // widthFactor 1: as wide as the label, so chips sit side by side.
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      label(v),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: v == selected ? BColors.greenDark : BColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
