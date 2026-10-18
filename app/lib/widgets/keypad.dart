import 'package:flutter/material.dart';

import '../core/keypad_input.dart';
import '../theme/theme.dart';

/// Large 3×4 number keypad (principle 4: no text keyboard).
/// Rows 1–9, then [bottomRow] (e.g. ⌫ 0 ✓, or . 0 ⌫ for kg/litre).
class Keypad extends StatelessWidget {
  const Keypad({
    super.key,
    required this.onKey,
    this.bottomRow = const [Keys.backspace, '0', Keys.ok],
    this.keyHeight = 64,
  });

  final ValueChanged<String> onKey;
  final List<String> bottomRow;
  final double keyHeight;

  static const _labels = {Keys.backspace: 'मेटाउनुस्', Keys.ok: 'ठीक छ', Keys.dot: 'दशमलव'};

  @override
  Widget build(BuildContext context) {
    final keys = [for (var i = 1; i <= 9; i++) '$i', ...bottomRow];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: keys.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisExtent: keyHeight,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, i) {
        final k = keys[i];
        final isOk = k == Keys.ok;
        final isBack = k == Keys.backspace;
        final bg = isOk ? BColors.green : (isBack ? BColors.warnBg : BColors.ground);
        final fg = isOk ? BColors.white : (isBack ? BColors.warnInk : BColors.ink);
        return Semantics(
          button: true,
          label: _labels[k] ?? k,
          excludeSemantics: true,
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: BColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('key-$k'),
              onTap: () => onKey(k),
              child: Center(
                child: isBack
                    ? Icon(Icons.backspace_outlined, color: fg, size: 26)
                    : isOk
                    ? Icon(Icons.check_rounded, color: fg, size: 34)
                    : Text(
                        k,
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: fg),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
