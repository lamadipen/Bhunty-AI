import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

import '../core/barcode.dart';
import '../data/models.dart';
import '../widgets/product_tile.dart';

/// One sticker: name, price and the shop's own code, sized 70 × 37 mm
/// (the common 24-per-A4 label sheet). Drawn by Flutter so Devanagari shapes
/// correctly, then put into the PDF as an image.
class ProductLabel extends StatelessWidget {
  const ProductLabel({
    super.key,
    required this.nameNe,
    required this.priceText,
    required this.code,
    required this.kind,
    this.showPrice = true,
  });

  ProductLabel.of(Product p, {super.key, LabelKind? kind, this.showPrice = true})
    : nameNe = p.nameNe,
      priceText = priceLabel(p),
      code = p.barcode!,
      kind = kind ?? p.labelKind ?? LabelKind.barcode;

  final String nameNe;
  final String priceText;
  final String code;
  final LabelKind kind;

  /// Off for shops that change prices often: printed prices go stale, scans don't.
  final bool showPrice;

  /// Logical size; 70:37 like the sticker.
  static const width = 280.0;
  static const height = 148.0;

  static const _ink = Color(0xFF000000);

  @override
  Widget build(BuildContext context) {
    final name = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        nameNe,
        maxLines: 1,
        style: const TextStyle(
          fontFamily: 'Mukta',
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: _ink,
          height: 1.1,
        ),
      ),
    );
    final price = Text(
      priceText,
      style: const TextStyle(fontFamily: 'Mukta', fontSize: 18, fontWeight: FontWeight.w700, color: _ink, height: 1.1),
    );
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFFFFFFF),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: switch (kind) {
        LabelKind.barcode => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: name),
                if (showPrice) ...[const SizedBox(width: 8), price],
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: BarcodeWidget(
                barcode: Barcode.ean13(drawEndChar: true),
                data: code,
                color: _ink,
                style: const TextStyle(fontSize: 13, color: _ink, letterSpacing: 1),
              ),
            ),
          ],
        ),
        LabelKind.qr => Row(
          children: [
            BarcodeWidget(barcode: Barcode.qrCode(), data: code, width: 124, height: 124, color: _ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  name,
                  if (showPrice) ...[const SizedBox(height: 4), price],
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(formatEan13(code), style: const TextStyle(fontSize: 12, color: _ink)),
                  ),
                ],
              ),
            ),
          ],
        ),
      },
    );
  }
}
