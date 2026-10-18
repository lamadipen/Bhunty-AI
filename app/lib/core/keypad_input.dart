/// Keys the on-screen keypad sends.
abstract final class Keys {
  static const backspace = '⌫';
  static const ok = '✓';
  static const dot = '.';
  static const doubleZero = '00';
}

/// Applies one keypad key to the current entry text.
/// No leading zeros, at most one decimal point (only when [allowDecimal]),
/// at most [maxDecimals] digits after it, at most [maxDigits] before it.
/// Set [leadingZeros] for codes and phone numbers, where "0" is a real digit.
String applyKey(
  String current,
  String key, {
  bool allowDecimal = false,
  int maxDigits = 6,
  int maxDecimals = 3,
  bool leadingZeros = false,
}) {
  if (key == Keys.backspace) {
    return current.isEmpty ? current : current.substring(0, current.length - 1);
  }
  if (key == Keys.dot) {
    if (!allowDecimal || current.contains('.')) return current;
    return current.isEmpty ? '0.' : '$current.';
  }
  if (key == Keys.doubleZero) {
    if (current.isEmpty) return current;
    return applyKey(
      applyKey(current, '0', allowDecimal: allowDecimal, maxDigits: maxDigits, maxDecimals: maxDecimals),
      '0',
      allowDecimal: allowDecimal,
      maxDigits: maxDigits,
      maxDecimals: maxDecimals,
    );
  }
  if (key.length != 1 || key.codeUnitAt(0) < 48 || key.codeUnitAt(0) > 57) return current;

  final dot = current.indexOf('.');
  if (dot >= 0) {
    if (current.length - dot - 1 >= maxDecimals) return current;
    return current + key;
  }
  if (current == '0' && !leadingZeros) return key;
  if (current.length >= maxDigits) return current;
  return current + key;
}
