/// Nepal mobile numbers: 10 digits starting 96, 97 or 98.
bool isNepalMobile(String digits) => RegExp(r'^9[678]\d{8}$').hasMatch(digits);

/// "9812345678" → "+9779812345678"
String toE164Nepal(String digits) => '+977$digits';

/// "9812345678" → "98123 45678" for display while typing.
String formatNepalMobile(String digits) =>
    digits.length <= 5 ? digits : '${digits.substring(0, 5)} ${digits.substring(5)}';
