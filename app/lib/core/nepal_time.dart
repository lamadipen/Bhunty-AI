/// Nepal is UTC+5:45 with no daylight saving. Day boundaries ("today's sales")
/// use Nepal time whatever the device's timezone is set to.
library;

const Duration nepalOffset = Duration(hours: 5, minutes: 45);

/// A UTC DateTime whose fields read as Nepal wall-clock time.
DateTime toNepalWallClock(DateTime t) => t.toUtc().add(nepalOffset);

/// "2026-10-18" in Nepal time; the key for daily summaries.
String nepalDayKey(DateTime t) {
  final n = toNepalWallClock(t);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${n.year}-${two(n.month)}-${two(n.day)}';
}

bool isSameNepalDay(DateTime a, DateTime b) => nepalDayKey(a) == nepalDayKey(b);
