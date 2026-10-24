/// Quantities are integer milli-units: 1 piece = 1000, आधा केजी = 500.
/// One code path for pieces and loose goods; never `double`.
library;

const int milli = 1000;

enum Unit {
  piece('वटा'),
  packet('प्याकेट'),
  kg('केजी'),
  litre('लिटर');

  const Unit(this.ne);

  /// Nepali label shown after a quantity.
  final String ne;

  /// Loose goods can be sold in fractions, so their keypad shows a decimal key.
  bool get isLoose => this == kg || this == litre;
}

/// Packs to selling units: 2 cartons (2000) of 30 packets (30000) → 60000.
int packsToUnitsMilli(int packsMilli, int packSizeMilli) => (packsMilli * packSizeMilli + 500) ~/ milli;

/// Cost of one selling unit from a pack price, rounded to the paisa:
/// रु 900 a carton of 30 → रु 30 a packet.
int unitCostFromPack(int packCostPaisa, int packSizeMilli) =>
    (packCostPaisa * milli + packSizeMilli ~/ 2) ~/ packSizeMilli;

/// 2000 → "2", 2500 → "2.5", 250 → "0.25".
String formatQty(int qtyMilli) {
  final sign = qtyMilli < 0 ? '-' : '';
  final abs = qtyMilli.abs();
  final whole = abs ~/ milli;
  final frac = abs % milli;
  if (frac == 0) return '$sign$whole';
  var f = frac.toString().padLeft(3, '0');
  while (f.endsWith('0')) {
    f = f.substring(0, f.length - 1);
  }
  return '$sign$whole.$f';
}

/// Keypad text ("2", "2.5", "0.25") → milli-units. Empty or "." → 0.
int parseQtyMilli(String text) {
  if (text.isEmpty || text == '.') return 0;
  final parts = text.split('.');
  final whole = int.parse(parts[0].isEmpty ? '0' : parts[0]);
  var frac = parts.length > 1 ? parts[1] : '';
  frac = '${frac}000'.substring(0, 3);
  return whole * milli + int.parse(frac);
}
