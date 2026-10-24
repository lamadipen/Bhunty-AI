/// Which scanned or typed values may be saved as a product's code.
///
/// Product codes are IDs: retail GTINs (EAN-8, UPC-A, EAN-13, GTIN-14) or a
/// short alphanumeric code (Code 128/39 used by some distributors). Anything
/// else — a payment QR, a web link, a Wi-Fi QR — is refused, so it can't end
/// up as a product's "barcode".
library;

/// The code to store, or a Nepali reason it can't be used.
typedef CodeCheck = ({String? code, String? error});

/// GTIN check digit (EAN-8/12/13/14) for [body] (all digits but the last).
int gtinCheckDigit(String body) {
  var sum = 0;
  for (var i = 0; i < body.length; i++) {
    final d = body.codeUnitAt(body.length - 1 - i) - 48;
    sum += d * (i.isEven ? 3 : 1);
  }
  return (10 - sum % 10) % 10;
}

bool _gtinValid(String digits) =>
    gtinCheckDigit(digits.substring(0, digits.length - 1)) == digits.codeUnitAt(digits.length - 1) - 48;

final _digits = RegExp(r'^\d+$');
final _alnum = RegExp(r'^[A-Z0-9\-.]{4,30}$');

/// Cleans up and checks a code.
///
/// [typed]: entered by hand, so GTIN-length numbers must pass the check digit
/// (catches a mistyped digit). Scanned codes were already checked by the decoder.
CodeCheck checkProductCode(String raw, {bool typed = false}) {
  final value = raw.trim();
  if (value.isEmpty) return (code: null, error: 'कोड खाली छ');
  if (value.contains('://') || value.contains(' ') || value.length > 30) {
    return (code: null, error: 'यो सामानको कोड होइन (लिंक वा भुक्तानी QR जस्तो छ)');
  }
  if (_digits.hasMatch(value)) {
    final gtinLength = const {8, 12, 13, 14}.contains(value.length);
    if (gtinLength && !_gtinValid(value)) {
      return (code: null, error: typed ? 'अङ्क मिलेन, एक पटक फेरि हेर्नुस्' : 'कोड पढ्न सकिएन, फेरि स्क्यान गर्नुस्');
    }
    if (!gtinLength && (value.length < 6 || value.length > 20)) {
      return (code: null, error: 'यति अङ्कको सामानको कोड हुँदैन');
    }
    // UPC-A is EAN-13 with a leading 0; store one form so both scans match.
    if (value.length == 12) return (code: '0$value', error: null);
    // GTIN-14 with indicator 0 is the same item as the EAN-13 inside it.
    if (value.length == 14 && value.startsWith('0')) return (code: value.substring(1), error: null);
    return (code: value, error: null);
  }
  final upper = value.toUpperCase();
  if (_alnum.hasMatch(upper)) return (code: upper, error: null);
  return (code: null, error: 'यो सामानको कोड होइन');
}
