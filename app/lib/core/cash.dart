import 'money.dart';

/// Notes a customer is likely to hand over, smallest first.
const List<int> _tenderNotes = [50, 100, 500, 1000];

/// Exact amount first, then the next round amounts a customer would pay with.
/// रु 75 → [75, 100, 500, 1000]; रु 4,250 → [4,250, 4,300, 4,500, 5,000].
List<int> suggestTenders(int totalPaisa, {int extra = 3}) {
  final out = <int>[totalPaisa];
  for (final note in _tenderNotes) {
    final step = rs(note);
    final roundUp = ((totalPaisa + step - 1) ~/ step) * step;
    if (roundUp > totalPaisa && !out.contains(roundUp)) out.add(roundUp);
    if (out.length > extra) break;
  }
  return out;
}

int changeDue({required int tenderedPaisa, required int totalPaisa}) =>
    tenderedPaisa > totalPaisa ? tenderedPaisa - totalPaisa : 0;
