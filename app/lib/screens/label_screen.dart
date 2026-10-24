import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:printing/printing.dart';

import '../app_scope.dart';
import '../core/barcode.dart';
import '../core/money.dart';
import '../data/models.dart';
import '../labels/label_pdf.dart';
import '../labels/product_label.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/number_pad.dart';

/// After a price change on an own-code product: printed labels show the old
/// price, so offer fresh ones (scanning always gives the new price).
Future<void> offerReprint(BuildContext context, Product p, int oldPricePaisa) async {
  final yes = await showBhunteSheet<bool>(
    context,
    (c) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('नयाँ लेबल छाप्ने?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(
          'पुराना लेबलमा ${formatRs(oldPricePaisa)} लेखिएको छ। स्क्यान गर्दा ${formatRs(p.pricePaisa)} नै आउँछ।',
          style: const TextStyle(fontSize: 16, color: BColors.inkSoft, height: 1.35),
        ),
        const SizedBox(height: 16),
        BigButton(label: 'नयाँ लेबल छाप्नुस्', onPressed: () => Navigator.pop(c, true)),
        const SizedBox(height: 8),
        BigButton(
          label: 'पछि',
          outlineColor: BColors.line,
          foreground: BColors.ink,
          height: 56,
          fontSize: 18,
          onPressed: () => Navigator.pop(c, false),
        ),
      ],
    ),
  );
  if (yes == true && context.mounted) await Navigator.of(context).push(LabelScreen.route<void>(p.id));
}

/// Print the shop's own barcode/QR stickers for one product.
class LabelScreen extends StatefulWidget {
  const LabelScreen({super.key, required this.productId});

  final String productId;

  static Route<T> route<T>(String productId) => MaterialPageRoute<T>(builder: (_) => LabelScreen(productId: productId));

  @override
  State<LabelScreen> createState() => _LabelScreenState();
}

class _LabelScreenState extends State<LabelScreen> {
  final _labelKey = GlobalKey();
  int _copies = labelsPerSheet;
  bool _busy = false;
  bool _showPrice = true;
  LabelPaper _paper = LabelPaper.a4Sheet;

  /// The on-screen label at print resolution (~300 dpi on a 70 mm sticker).
  Future<Uint8List> _labelPng() async {
    final boundary = _labelKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  Future<void> _output({required bool share}) async {
    if (_copies <= 0) return;
    setState(() => _busy = true);
    try {
      final p = context.readStore.product(widget.productId);
      final png = await _labelPng();
      final pdf = await buildLabelSheetPdf(labelPng: png, copies: _copies, paper: _paper, title: p.nameNe);
      final file = 'bhunte-label-${p.barcode}.pdf';
      if (share) {
        await Printing.sharePdf(bytes: pdf, filename: file);
      } else {
        await Printing.layoutPdf(name: file, onLayout: (_) async => pdf);
      }
    } catch (e) {
      debugPrint('Bhunte: label output failed: $e');
      if (mounted) showToast(context, 'लेबल बनाउन सकिएन, फेरि प्रयास गर्नुस्');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editCopies() async {
    final text = await showNumberPad(context, title: 'कति वटा लेबल?', initial: '$_copies', maxDigits: 3);
    if (text != null && text.isNotEmpty) setState(() => _copies = int.parse(text));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final p = store.product(widget.productId);
    final kind = p.labelKind ?? LabelKind.barcode;
    final pages = pagesFor(_copies, _paper);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'लेबल प्रिन्ट',
              subtitle: '${p.nameNe} · आफ्नै ${kind == LabelKind.qr ? 'QR' : 'बारकोड'}',
            ),
            Expanded(
              child: ListView(
                key: const ValueKey('label-list'),
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: BColors.line),
                        boxShadow: const [BoxShadow(color: Color(0x1A17201B), blurRadius: 12, offset: Offset(0, 4))],
                      ),
                      child: RepaintBoundary(
                        key: _labelKey,
                        child: ProductLabel.of(p, showPrice: _showPrice),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('कस्तो लेबल?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _KindButton(
                          label: 'बारकोड',
                          hint: 'क्यामेरा र स्क्यानर दुवैले पढ्छ',
                          icon: Icons.view_week_outlined,
                          selected: kind == LabelKind.barcode,
                          onTap: () => store.setLabelKind(p.id, LabelKind.barcode),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _KindButton(
                          label: 'QR',
                          hint: 'सानो वा गोलो सामानमा',
                          icon: Icons.qr_code_2_rounded,
                          selected: kind == LabelKind.qr,
                          onTap: () => store.setLabelKind(p.id, LabelKind.qr),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CardBox(
                    radius: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    child: SwitchListTile(
                      key: const ValueKey('show-price'),
                      contentPadding: EdgeInsets.zero,
                      value: _showPrice,
                      activeThumbColor: BColors.green,
                      onChanged: (v) => setState(() => _showPrice = v),
                      title: const Text(
                        'मूल्य पनि छाप्ने',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'मूल्य धेरै बदलिन्छ भने नछाप्नुस् — स्क्यान गर्दा सधैं नयाँ मूल्य आउँछ',
                        style: TextStyle(fontSize: 13, color: BColors.inkSoft),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('कस्तो कागज?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _KindButton(
                          label: 'A4 पाना',
                          hint: '२४ स्टिकर (७०×३७ मिमी) वा साधारण कागज',
                          icon: Icons.grid_on_rounded,
                          selected: _paper == LabelPaper.a4Sheet,
                          onTap: () => setState(() => _paper = LabelPaper.a4Sheet),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _KindButton(
                          key: const ValueKey('paper-thermal'),
                          label: 'थर्मल',
                          hint: 'लेबल प्रिन्टर ५०×३० मिमी',
                          icon: Icons.receipt_long_outlined,
                          selected: _paper == LabelPaper.thermal50x30,
                          onTap: () => setState(() => _paper = LabelPaper.thermal50x30),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  PadField(
                    key: const ValueKey('label-copies'),
                    label: 'कति वटा लेबल?',
                    value: _paper == LabelPaper.a4Sheet ? '$_copies वटा · $pages पाना A4' : '$_copies वटा लेबल',
                    onTap: _editCopies,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'प्रिन्टर छैन? "PDF पठाउनुस्" थिचेर Viber मा प्रिन्ट पसलमा पठाउनुस्।',
                    style: TextStyle(fontSize: 15, color: BColors.inkSoft, height: 1.35),
                  ),
                ],
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: BColors.white,
                border: Border(top: BorderSide(color: BColors.line)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BigButton(
                    label: _busy ? 'पर्खनुस्…' : 'प्रिन्ट गर्नुस्',
                    icon: Icons.print_outlined,
                    color: _busy ? BColors.disabled : BColors.green,
                    onPressed: _busy ? null : () => _output(share: false),
                  ),
                  const SizedBox(height: 8),
                  BigButton(
                    label: 'PDF पठाउनुस् / साँच्नुस्',
                    icon: Icons.ios_share_rounded,
                    outlineColor: BColors.line,
                    foreground: BColors.ink,
                    height: 56,
                    fontSize: 18,
                    onPressed: _busy ? null : () => _output(share: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindButton extends StatelessWidget {
  const _KindButton({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label · $hint',
      excludeSemantics: true,
      child: CardBox(
        radius: 16,
        color: selected ? BColors.greenTint : BColors.white,
        borderColor: selected ? BColors.green : BColors.line,
        borderWidth: 2,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: selected ? BColors.greenDark : BColors.inkSoft, size: 30),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: selected ? BColors.greenDark : BColors.ink,
                    ),
                  ),
                  Text(
                    hint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: BColors.inkSoft, height: 1.2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
