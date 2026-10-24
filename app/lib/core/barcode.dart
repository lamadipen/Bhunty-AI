/// In-store codes for products that have no barcode of their own.
///
/// EAN-13 numbers starting with "2" are reserved by GS1 for use inside one
/// shop ("restricted circulation"), so they never clash with a real product's
/// barcode. The same number can be printed as a barcode (works with phone
/// cameras and cheap laser scanners) or as a QR code (smaller, any angle).
library;

import 'dart:math';

/// How a product's own label is printed.
enum LabelKind { barcode, qr }

/// EAN-13 check digit for the first 12 digits.
int ean13CheckDigit(String first12) {
  assert(first12.length == 12 && int.tryParse(first12) != null);
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += (first12.codeUnitAt(i) - 48) * (i.isEven ? 1 : 3);
  }
  return (10 - sum % 10) % 10;
}

bool isValidEan13(String code) =>
    RegExp(r'^\d{13}$').hasMatch(code) && ean13CheckDigit(code.substring(0, 12)) == code.codeUnitAt(12) - 48;

/// True for codes this app made (EAN-13 in the GS1 in-store range 20–29).
bool isInStoreCode(String code) => isValidEan13(code) && code.startsWith('2');

/// A new in-store EAN-13 ("2" + 11 random digits + check digit) not in [taken].
String generateInStoreEan13({required Set<String> taken, Random? random}) {
  final rng = random ?? Random.secure();
  while (true) {
    final body = StringBuffer('2');
    for (var i = 0; i < 11; i++) {
      body.write(rng.nextInt(10));
    }
    final first12 = body.toString();
    final code = '$first12${ean13CheckDigit(first12)}';
    if (!taken.contains(code)) return code;
  }
}

/// "2012345678905" → "2 012345 678905", the way it's printed under EAN-13 bars.
String formatEan13(String code) => code.length == 13 ? '${code[0]} ${code.substring(1, 7)} ${code.substring(7)}' : code;
