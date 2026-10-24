import 'package:flutter/material.dart';

import '../core/keypad_input.dart';
import '../core/product_code.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/keypad.dart';

/// Type the number printed under a barcode that won't scan (crumpled, shiny,
/// curved) or when there's no camera. Checked with the GTIN check digit, so a
/// mistyped digit is caught. Returns the code or null.
class ManualCodeSheet extends StatefulWidget {
  const ManualCodeSheet({super.key});

  static Future<String?> open(BuildContext context) => showBhunteSheet<String>(context, (_) => const ManualCodeSheet());

  @override
  State<ManualCodeSheet> createState() => _ManualCodeSheetState();
}

class _ManualCodeSheetState extends State<ManualCodeSheet> {
  String _digits = '';
  String? _error;

  void _onKey(String k) {
    if (k == Keys.ok) {
      final check = checkProductCode(_digits, typed: true);
      if (check.error != null) {
        setState(() => _error = check.error);
        return;
      }
      Navigator.pop(context, check.code);
      return;
    }
    setState(() {
      _error = null;
      _digits = applyKey(_digits, k, maxDigits: 14, leadingZeros: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('बारकोडमुनिको नम्बर लेख्नुस्', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const Text(
          'बारकोडको तल लेखिएका सबै अङ्क, बायाँबाट दायाँ',
          style: TextStyle(fontSize: 15, color: BColors.inkSoft),
        ),
        const SizedBox(height: 10),
        Container(
          height: 64,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: BColors.ground, borderRadius: BorderRadius.circular(16)),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _digits.isEmpty ? '8 9 0 …' : _digits,
              key: const ValueKey('manual-code'),
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: _digits.isEmpty ? BColors.disabled : BColors.ink,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Semantics(
            liveRegion: true,
            child: Text(
              _error ?? '${_digits.length} अङ्क',
              style: TextStyle(
                fontSize: 15,
                fontWeight: _error == null ? FontWeight.w400 : FontWeight.w700,
                color: _error == null ? BColors.inkSoft : BColors.warnInk,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Keypad(keyHeight: 58, onKey: _onKey),
      ],
    );
  }
}
