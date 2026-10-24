import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../photos/cloud_photo_reader.dart';
import '../photos/photo_reader.dart';
import 'bill_reader.dart';

/// Calls `readBill` (functions/src/index.ts): Claude Haiku reads the pages.
class CloudBillReader implements BillReader {
  CloudBillReader(FirebaseFunctions functions)
    : _call = functions.httpsCallable('readBill', options: HttpsCallableOptions(timeout: const Duration(seconds: 100)));

  final HttpsCallable _call;

  @override
  Future<BillReadResult> read(List<Uint8List> pages, List<Map<String, Object?>> catalog) async {
    try {
      final result = await _call.call<Object?>({
        'pages': [for (final p in pages) base64Encode(p)],
        'catalog': catalog,
      });
      final data = result.data;
      if (data is! Map) return const BillReadFailed(BillReadProblem.unavailable);
      final reading = BillReading.fromMap(data.cast<String, Object?>());
      return reading.lines.isEmpty ? const BillReadFailed(BillReadProblem.unreadable) : BillRead(reading);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Bhunte: readBill ${e.code}: ${e.message}');
      // Same error contract as readProductPhotos.
      return BillReadFailed(switch (CloudPhotoReader.problemFor(e.code, e.message)) {
        PhotoReadProblem.offline => BillReadProblem.offline,
        PhotoReadProblem.limitReached => BillReadProblem.limitReached,
        PhotoReadProblem.unreadable => BillReadProblem.unreadable,
        PhotoReadProblem.unavailable => BillReadProblem.unavailable,
      });
    } on TimeoutException {
      return const BillReadFailed(BillReadProblem.offline);
    } catch (e) {
      debugPrint('Bhunte: readBill: $e');
      return const BillReadFailed(BillReadProblem.unavailable);
    }
  }
}
