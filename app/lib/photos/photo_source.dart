import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/product_code.dart';
import '../data/models.dart';
import 'image_shrink.dart';
import 'webcam_screen.dart';

enum PhotoFrom { camera, gallery }

/// A photo picked for a slot, already shrunk to ≤ 1024 px JPEG (PR7).
class PickedPhoto {
  const PickedPhoto({required this.jpeg, this.path});

  final Uint8List jpeg;

  /// A file on the phone, for the on-phone barcode reader; null on the web.
  final String? path;
}

/// Where photos come from. Replaced in tests.
abstract interface class PhotoSource {
  /// A photo from the camera or the gallery / files; null if the user cancelled
  /// or the file wasn't an image. The camera may open a screen, hence [context].
  Future<PickedPhoto?> pick(BuildContext context, PhotoFrom from);

  /// A checked product code read on the phone from [photo] (free, offline);
  /// null on the web or when none is found (PR3).
  Future<String?> readBarcode(PickedPhoto photo);

  /// The 256 px thumbnail kept with the product (D3); null if it can't be made.
  Future<ProductImage?> thumbnail(PickedPhoto photo);
}

class DevicePhotoSource implements PhotoSource {
  const DevicePhotoSource();

  /// Desktop browsers ignore the camera hint on a file input and open the file
  /// picker, so they get a live webcam screen. Phone browsers and the apps use
  /// the system camera.
  static bool get usesWebcam =>
      kIsWeb && defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS;

  @override
  Future<PickedPhoto?> pick(BuildContext context, PhotoFrom from) async {
    if (from == PhotoFrom.camera && usesWebcam) {
      switch (await WebcamScreen.open(context)) {
        case WebcamPhoto(:final bytes):
          try {
            return PickedPhoto(jpeg: await shrinkToJpeg(bytes));
          } catch (e) {
            debugPrint('Bhunte: webcam photo unreadable: $e');
            return null;
          }
        case WebcamUseFiles():
          from = PhotoFrom.gallery;
        case null:
          return null;
      }
    }
    try {
      // The picker shrinks on Android/iOS/web; shrinkToJpeg makes sure of it everywhere.
      final file = await ImagePicker().pickImage(
        source: from == PhotoFrom.camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: aiPhotoSide.toDouble(),
        maxHeight: aiPhotoSide.toDouble(),
        imageQuality: 85,
      );
      if (file == null) return null;
      final jpeg = await shrinkToJpeg(await file.readAsBytes());
      return PickedPhoto(jpeg: jpeg, path: kIsWeb ? null : file.path);
    } catch (e) {
      debugPrint('Bhunte: photo pick failed: $e');
      return null;
    }
  }

  @override
  Future<ProductImage?> thumbnail(PickedPhoto photo) async {
    try {
      return await makeThumbnail(photo.jpeg);
    } catch (e) {
      debugPrint('Bhunte: thumbnail failed: $e');
      return null;
    }
  }

  @override
  Future<String?> readBarcode(PickedPhoto photo) async {
    final path = photo.path;
    if (path == null) return null;
    final controller = MobileScannerController(autoStart: false);
    try {
      final capture = await controller.analyzeImage(
        path,
        formats: const [
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
          BarcodeFormat.code128,
          BarcodeFormat.code39,
          BarcodeFormat.itf14,
          BarcodeFormat.qrCode,
        ],
      );
      for (final b in capture?.barcodes ?? const <Barcode>[]) {
        final code = checkProductCode(b.rawValue ?? '').code;
        if (code != null) return code;
      }
      return null;
    } catch (e) {
      debugPrint('Bhunte: barcode from photo failed: $e');
      return null;
    } finally {
      await controller.dispose();
    }
  }
}
