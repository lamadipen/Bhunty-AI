import 'dart:typed_data';

import '../core/money.dart';
import '../core/qty.dart';
import 'photo_reader.dart';

/// Scripted stand-in for the Cloud Function, so the photo flow can be tried
/// in the demo (F-17). Always "reads" the F-1 packet; tests pass [result].
class DemoPhotoReader implements PhotoReader {
  DemoPhotoReader({this.delay = const Duration(milliseconds: 900), this.result});

  final Duration delay;
  final PhotoReadResult? result;

  /// How many reads were asked for (each would count toward the day's limit).
  int calls = 0;

  @override
  Future<PhotoReadResult> read(Map<PhotoRole, Uint8List> photos, {String? barcodeOnPhone}) async {
    calls++;
    await Future<void>.delayed(delay);
    return result ??
        PhotoRead(
          PhotoReading(
            nameNe: 'वाइवाइ चिकेन',
            nameEn: 'Wai Wai Chicken',
            brand: 'Wai Wai',
            sizeText: '70 g',
            unit: Unit.packet,
            mrpPaisa: rs(25),
            // The AI reads the digits only when it was shown the barcode photo.
            barcode: photos.containsKey(PhotoRole.barcode) ? '8901234567890' : null,
          ),
        );
  }
}
