/// Money is always integer paisa (रु 1 = 100 paisa). Never use `double`.
library;

/// Rupees to paisa, for whole-rupee literals.
int rs(int rupees) => rupees * 100;

/// Indian digit grouping: 1234567 → "12,34,567".
String groupIndian(int n) {
  final digits = n.abs().toString();
  if (digits.length <= 3) return n < 0 ? '-$digits' : digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  final grouped = '${parts.join(',')},$last3';
  return n < 0 ? '-$grouped' : grouped;
}

/// "4,250", or "22.50" when there are paisa.
String formatAmount(int paisa) {
  final sign = paisa < 0 ? '-' : '';
  final abs = paisa.abs();
  final whole = groupIndian(abs ~/ 100);
  final cents = abs % 100;
  return cents == 0 ? '$sign$whole' : '$sign$whole.${cents.toString().padLeft(2, '0')}';
}

/// "रु 4,250"
String formatRs(int paisa) => 'रु ${formatAmount(paisa)}';

/// Keypad text in rupees ("25", "22.5", "22.50") → paisa. Empty → 0.
int parseMoneyPaisa(String text) {
  if (text.isEmpty || text == '.') return 0;
  final parts = text.split('.');
  final whole = int.parse(parts[0].isEmpty ? '0' : parts[0]);
  final frac = '${parts.length > 1 ? parts[1] : ''}00'.substring(0, 2);
  return whole * 100 + int.parse(frac);
}

/// Line total for a unit price and a quantity in milli-units, rounded half-up to the paisa.
int lineTotal(int pricePaisa, int qtyMilli) => (pricePaisa * qtyMilli + 500) ~/ 1000;
