import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Common A4 sticker sheet: 3 columns × 8 rows of 70 × 37 mm, no page margin.
const labelsPerSheet = 24;
const _cols = 3, _rows = 8;
const _labelW = 70 * PdfPageFormat.mm, _labelH = 37 * PdfPageFormat.mm;

int sheetsFor(int copies) => copies <= 0 ? 0 : (copies + labelsPerSheet - 1) ~/ labelsPerSheet;

/// A PDF of [copies] identical labels, from a PNG of one label.
Future<Uint8List> buildLabelSheetPdf({required Uint8List labelPng, required int copies, String title = 'labels'}) {
  final doc = pw.Document(title: title, creator: 'Bhunte AI');
  final image = pw.MemoryImage(labelPng);
  var left = copies;
  for (var sheet = 0; sheet < sheetsFor(copies); sheet++) {
    final onSheet = left < labelsPerSheet ? left : labelsPerSheet;
    left -= onSheet;
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 0, marginRight: 0, marginTop: 0, marginBottom: 0),
        build: (_) => pw.Column(
          children: [
            for (var r = 0; r < _rows; r++)
              pw.Row(
                children: [
                  for (var c = 0; c < _cols; c++)
                    pw.SizedBox(
                      width: _labelW,
                      height: _labelH,
                      child: r * _cols + c < onSheet
                          // A little inset so a slightly misaligned printer doesn't cut the code.
                          ? pw.Padding(
                              padding: const pw.EdgeInsets.all(2 * PdfPageFormat.mm),
                              child: pw.Image(image, fit: pw.BoxFit.contain),
                            )
                          : pw.SizedBox(),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}
