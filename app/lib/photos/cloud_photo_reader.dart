import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'photo_reader.dart';

/// Calls `readProductPhotos` (functions/src/index.ts), which asks Claude
/// Haiku to read the photos. The API key never reaches the phone.
class CloudPhotoReader implements PhotoReader {
  CloudPhotoReader(FirebaseFunctions functions)
    : _call = functions.httpsCallable(
        'readProductPhotos',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
      );

  /// Same region as the function (closest to Nepal).
  static const region = 'asia-south1';

  final HttpsCallable _call;

  @override
  Future<PhotoReadResult> read(Map<PhotoRole, Uint8List> photos, {String? barcodeOnPhone}) async {
    try {
      final result = await _call.call<Object?>({
        'images': [
          for (final e in photos.entries) {'role': e.key.wire, 'jpegBase64': base64Encode(e.value)},
        ],
        'barcodeOnPhone': ?barcodeOnPhone,
      });
      final data = result.data;
      if (data is! Map) return const PhotoReadFailed(PhotoReadProblem.unavailable);
      return PhotoRead(PhotoReading.fromMap(data.cast<String, Object?>()));
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Bhunte: readProductPhotos ${e.code}: ${e.message}');
      return PhotoReadFailed(problemFor(e.code, e.message));
    } on TimeoutException {
      return const PhotoReadFailed(PhotoReadProblem.offline);
    } catch (e) {
      debugPrint('Bhunte: readProductPhotos: $e');
      return const PhotoReadFailed(PhotoReadProblem.unavailable);
    }
  }

  /// The function's own errors carry their reason as the message; a network
  /// failure arrives as `unavailable` / `deadline-exceeded` with another message.
  /// Shared with the bill reader (same error contract).
  static PhotoReadProblem problemFor(String code, String? message) => switch ((code, message)) {
    ('resource-exhausted', _) => PhotoReadProblem.limitReached,
    ('failed-precondition', 'unreadable') => PhotoReadProblem.unreadable,
    ('unavailable', 'ai-unavailable') => PhotoReadProblem.unavailable,
    ('unavailable' || 'deadline-exceeded', _) => PhotoReadProblem.offline,
    _ => PhotoReadProblem.unavailable,
  };
}
