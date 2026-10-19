import 'package:flutter/material.dart';

import '../core/keypad_input.dart';
import '../theme/theme.dart';
import 'common.dart';
import 'keypad.dart';

/// Opens a keypad sheet for one number and returns the typed text, or null
/// if closed. Use for forms; quick entry screens put a [Keypad] inline.
Future<String?> showNumberPad(
  BuildContext context, {
  required String title,
  String initial = '',
  bool allowDecimal = false,
  int maxDecimals = 3,
  int maxDigits = 6,
  String prefix = '',
  String suffix = '',
}) {
  return showBhunteSheet<String>(
    context,
    (c) => _NumberPadSheet(
      title: title,
      initial: initial,
      allowDecimal: allowDecimal,
      maxDecimals: maxDecimals,
      maxDigits: maxDigits,
      prefix: prefix,
      suffix: suffix,
    ),
  );
}

class _NumberPadSheet extends StatefulWidget {
  const _NumberPadSheet({
    required this.title,
    required this.initial,
    required this.allowDecimal,
    required this.maxDecimals,
    required this.maxDigits,
    required this.prefix,
    required this.suffix,
  });

  final String title;
  final String initial;
  final bool allowDecimal;
  final int maxDecimals;
  final int maxDigits;
  final String prefix;
  final String suffix;

  @override
  State<_NumberPadSheet> createState() => _NumberPadSheetState();
}

class _NumberPadSheetState extends State<_NumberPadSheet> {
  late String _entry = widget.initial;
  bool _fresh = true;

  void _onKey(String k) {
    if (k == Keys.ok) {
      Navigator.pop(context, _entry);
      return;
    }
    setState(() {
      // The first digit replaces the old value instead of adding to it.
      final base = _fresh && k != Keys.backspace ? '' : _entry;
      _fresh = false;
      _entry = applyKey(
        base,
        k,
        allowDecimal: widget.allowDecimal,
        maxDecimals: widget.maxDecimals,
        maxDigits: widget.maxDigits,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Container(
          height: 68,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(color: BColors.ground, borderRadius: BorderRadius.circular(16)),
          child: Text(
            '${widget.prefix}${_entry.isEmpty ? '0' : _entry}${widget.suffix}',
            key: const ValueKey('pad-entry'),
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 12),
        Keypad(
          keyHeight: 62,
          bottomRow: widget.allowDecimal ? const [Keys.dot, '0', Keys.backspace] : const [Keys.backspace, '0', Keys.ok],
          onKey: _onKey,
        ),
        if (widget.allowDecimal) ...[
          const SizedBox(height: 10),
          BigButton(label: 'ठीक छ', trailingIcon: Icons.check_rounded, onPressed: () => _onKey(Keys.ok)),
        ],
      ],
    );
  }
}

/// A form field that shows a number and opens the keypad when tapped.
class PadField extends StatelessWidget {
  const PadField({super.key, required this.label, required this.value, required this.onTap, this.active = false});

  final String label;
  final String value;
  final VoidCallback onTap;

  /// Green border, e.g. for the field the inline keypad is typing into.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: CardBox(
        radius: 16,
        borderColor: active ? BColors.green : BColors.line,
        borderWidth: active ? 2 : 1,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 14, color: BColors.inkSoft)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2)),
            ),
          ],
        ),
      ),
    );
  }
}
