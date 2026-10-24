import 'dart:typed_data';

import '../core/qty.dart';

/// The three photo slots on the capture screen (docs/product-photos.md, D1).
enum PhotoRole {
  front('front'),
  barcode('barcode'),
  label('label');

  const PhotoRole(this.wire);

  /// As the Cloud Function expects it.
  final String wire;
}

/// What the AI read from the photos. Every field is a suggestion for the form;
/// it never holds a selling price, cost or stock (PR2).
class PhotoReading {
  const PhotoReading({
    this.nameNe,
    this.nameEn,
    this.brand,
    this.sizeText,
    this.unit,
    this.mrpPaisa,
    this.barcode,
    this.lowConfidence = const {},
    this.notes,
  });

  final String? nameNe;
  final String? nameEn;
  final String? brand;

  /// Net size as printed, e.g. "70 g", "1 L".
  final String? sizeText;
  final Unit? unit;

  /// Printed MRP: shown as a hint only, never saved.
  final int? mrpPaisa;
  final String? barcode;

  /// Fields the AI was unsure of: `nameNe`, `nameEn`, `sizeText`, `unit`, `mrpPaisa`, `barcode`.
  final Set<String> lowConfidence;
  final String? notes;

  /// Reads the Cloud Function's reply, dropping anything malformed.
  factory PhotoReading.fromMap(Map<String, Object?> m) {
    String? text(String key) {
      final v = m[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final mrp = m['mrpPaisa'];
    final confidence = m['confidence'];
    return PhotoReading(
      nameNe: text('nameNe'),
      nameEn: text('nameEn'),
      brand: text('brand'),
      sizeText: text('sizeText'),
      unit: Unit.values.asNameMap()[m['unit']],
      mrpPaisa: mrp is int && mrp > 0 ? mrp : null,
      barcode: text('barcode'),
      lowConfidence: confidence is Map
          ? {
              for (final e in confidence.entries)
                if (e.value == 'low') '${e.key}',
            }
          : {},
      notes: text('notes'),
    );
  }
}

/// Why the AI couldn't fill the form. The form still opens (except for
/// [unreadable], where the user can retake a photo) with the thumbnail and the
/// barcode read on the phone.
enum PhotoReadProblem {
  /// No internet (PR10).
  offline('इन्टरनेट आएपछि फोटोबाट भर्न सकिन्छ'),

  /// 100 reads today already (PR9).
  limitReached('आजको फोटो पढ्ने सीमा सकियो — हातैले भर्नुस्'),

  /// Not a product, or nothing could be read (F-7).
  unreadable('फोटोबाट पढ्न सकिएन — अर्को फोटो खिच्नुस् वा हातैले भर्नुस्'),

  /// Not signed in, function not deployed, or the AI is down (F-17).
  unavailable('फोटोबाट भर्ने सुविधा अहिले उपलब्ध छैन');

  const PhotoReadProblem(this.message);

  final String message;
}

sealed class PhotoReadResult {
  const PhotoReadResult();
}

final class PhotoRead extends PhotoReadResult {
  const PhotoRead(this.reading);
  final PhotoReading reading;
}

final class PhotoReadFailed extends PhotoReadResult {
  const PhotoReadFailed(this.problem);
  final PhotoReadProblem problem;
}

/// Client side of the `readProductPhotos` Cloud Function. Never throws.
abstract interface class PhotoReader {
  /// [photos] are JPEGs already shrunk to ≤ 1024 px (PR7).
  Future<PhotoReadResult> read(Map<PhotoRole, Uint8List> photos, {String? barcodeOnPhone});
}

/// For builds with no AI backend: the photo button still gives a thumbnail
/// and the phone's barcode read (F-17).
class NoPhotoReader implements PhotoReader {
  const NoPhotoReader();

  @override
  Future<PhotoReadResult> read(Map<PhotoRole, Uint8List> photos, {String? barcodeOnPhone}) async =>
      const PhotoReadFailed(PhotoReadProblem.unavailable);
}

final _compactSize = RegExp(r'^(\d+(?:[.,]\d+)?)\s*([A-Za-z]+)$');

/// PR4: different sizes are different products, so a read size goes into the
/// name ("वाइवाइ चिकेन" + "70 g" → "वाइवाइ चिकेन 70g") — except for loose goods,
/// whose unit (केजी/लिटर) already says it (F-10).
String nameWithSize(String name, String? sizeText, Unit unit) {
  final size = sizeText?.trim();
  if (size == null || size.isEmpty || unit.isLoose) return name;
  final short = size.replaceFirstMapped(_compactSize, (m) => '${m[1]}${m[2]}');
  final lower = name.toLowerCase();
  if (lower.contains(short.toLowerCase()) || lower.contains(size.toLowerCase())) return name;
  return '$name $short';
}
