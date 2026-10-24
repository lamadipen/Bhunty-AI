import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../data/models.dart';

/// Longest side of a photo sent to the AI (PR7).
const aiPhotoSide = 1024;

/// Longest side of a product thumbnail (PR7).
const thumbnailSide = 256;

/// Re-encodes any photo as a JPEG no larger than [maxSide], upright (EXIF
/// rotation applied). Runs off the UI thread where the platform allows.
Future<Uint8List> shrinkToJpeg(Uint8List bytes, {int maxSide = aiPhotoSide, int quality = 80}) =>
    compute(_shrink, (bytes, maxSide, quality));

/// The product thumbnail: 256 px, quality stepped down until it is about
/// 30 KB, never above [ProductImage.maxBytes].
Future<ProductImage> makeThumbnail(Uint8List bytes) => compute(_thumbnail, bytes);

Uint8List _shrink((Uint8List, int, int) a) {
  final (bytes, maxSide, quality) = a;
  return img.encodeJpg(_resized(bytes, maxSide), quality: quality);
}

ProductImage _thumbnail(Uint8List bytes) {
  final small = _resized(bytes, thumbnailSide);
  var jpeg = img.encodeJpg(small, quality: 70);
  for (final q in const [60, 50, 40]) {
    if (jpeg.length <= 30000) break;
    jpeg = img.encodeJpg(small, quality: q);
  }
  if (jpeg.length > ProductImage.maxBytes) throw const FormatException('Thumbnail too large');
  return ProductImage(jpeg: jpeg, width: small.width, height: small.height);
}

img.Image _resized(Uint8List bytes, int maxSide) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Not an image');
  final upright = img.bakeOrientation(decoded);
  if (upright.width <= maxSide && upright.height <= maxSide) return upright;
  return upright.width >= upright.height
      ? img.copyResize(upright, width: maxSide, interpolation: img.Interpolation.average)
      : img.copyResize(upright, height: maxSide, interpolation: img.Interpolation.average);
}
