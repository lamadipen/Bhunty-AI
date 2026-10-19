import 'package:flutter/material.dart';

import '../app.dart';
import '../app_scope.dart';
import '../core/keypad_input.dart';
import '../core/money.dart';
import '../data/models.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/keypad.dart';

class UdharoScreen extends StatelessWidget {
  const UdharoScreen({super.key});

  Future<void> _open(BuildContext context, Customer c) async {
    final store = context.readStore;
    final result = await showBhunteSheet<_UdharoResult>(context, (_) => _CustomerSheet(customer: c));
    if (result == null || !context.mounted) return;
    switch (result.kind) {
      case _Kind.payment:
        store.recordPayment(c.id, result.amountPaisa);
        showToast(context, '${c.name} · ${formatRs(result.amountPaisa)} आयो');
      case _Kind.credit:
        store.recordCredit(c.id, result.amountPaisa);
        showToast(context, '${c.name} · ${formatRs(result.amountPaisa)} उधारो लेखियो');
      case _Kind.remind:
        showToast(context, 'Viber जोडेपछि ${c.name}लाई सम्झना पठाउन मिल्छ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'उधारो खाता', subtitle: 'कसले कति तिर्न बाँकी'),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(color: BColors.orange, borderRadius: BorderRadius.circular(22)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('जम्मा उठ्न बाँकी', style: TextStyle(fontSize: 16, color: Color(0xEBFFFFFF))),
                        Text(
                          formatRs(store.totalUdharoPaisa),
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: BColors.white,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${store.customersOwing} जना',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: BColors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                children: [
                  for (final c in store.customers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CustomerRow(customer: c, onTap: () => _open(context, c)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: BigButton(
                label: '“राम दाइलाई ३५० उधारो” भन्नुस्',
                icon: Icons.mic_none_rounded,
                outlineColor: BColors.orange,
                foreground: BColors.orange,
                radius: 32,
                fontSize: 19,
                onPressed: () => Navigator.pushNamed(context, Routes.assistant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer, required this.onTap});

  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final owes = customer.balancePaisa > 0;
    final ink = owes ? BColors.warnInk : BColors.greenDark;
    return Semantics(
      button: true,
      child: CardBox(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: onTap,
        child: Row(
          children: [
            LetterTile(
              letter: customer.initial,
              bg: owes ? BColors.warnBg : BColors.greenTint,
              ink: ink,
              size: 48,
              circle: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(customer.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.15)),
                  Text(customer.lastNote, style: const TextStyle(fontSize: 14, color: BColors.inkSoft)),
                ],
              ),
            ),
            if (!owes) Icon(Icons.check_rounded, color: ink, size: 22),
            Text(
              owes ? formatRs(customer.balancePaisa) : 'चुक्ता',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Kind { payment, credit, remind }

class _UdharoResult {
  const _UdharoResult(this.kind, [this.amountPaisa = 0]);
  final _Kind kind;
  final int amountPaisa;
}

/// Amount keypad with "पैसा आयो −" and "उधारो थप +".
class _CustomerSheet extends StatefulWidget {
  const _CustomerSheet({required this.customer});

  final Customer customer;

  @override
  State<_CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends State<_CustomerSheet> {
  String _entry = '';
  String? _error;

  int get _amount => _entry.isEmpty ? 0 : rs(int.parse(_entry));

  void _submit(_Kind kind) {
    if (_amount <= 0) {
      setState(() => _error = 'रकम लेख्नुस्');
      return;
    }
    if (kind == _Kind.payment && _amount > widget.customer.balancePaisa) {
      setState(() => _error = 'बाँकी ${formatRs(widget.customer.balancePaisa)} भन्दा बढी भयो');
      return;
    }
    Navigator.pop(context, _UdharoResult(kind, _amount));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            LetterTile(letter: c.initial, bg: BColors.warnBg, ink: BColors.warnInk, size: 48, circle: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.15)),
                  Text(
                    c.balancePaisa > 0 ? 'बाँकी ${formatRs(c.balancePaisa)}' : 'चुक्ता',
                    style: const TextStyle(fontSize: 15, color: BColors.warnInk, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            RoundIconButton(
              icon: Icons.close_rounded,
              label: 'बन्द गर्नुस्',
              size: 44,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 64,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(color: BColors.ground, borderRadius: BorderRadius.circular(16)),
          child: Text(
            formatRs(_amount),
            key: const ValueKey('udharo-amount'),
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _error!,
              style: const TextStyle(fontSize: 15, color: BColors.warnInk, fontWeight: FontWeight.w700),
            ),
          ),
        const SizedBox(height: 10),
        Keypad(
          keyHeight: 54,
          bottomRow: const [Keys.backspace, '0', Keys.doubleZero],
          onKey: (k) => setState(() {
            _entry = applyKey(_entry, k, maxDigits: 6);
            _error = null;
          }),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: BigButton(label: 'पैसा आयो −', fontSize: 19, radius: 18, onPressed: () => _submit(_Kind.payment)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: BigButton(
                label: 'उधारो थप +',
                color: BColors.orange,
                fontSize: 19,
                radius: 18,
                onPressed: () => _submit(_Kind.credit),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        BigButton(
          label: 'Viber मा सम्झाउनुस्',
          outlineColor: BColors.line,
          foreground: BColors.ink,
          height: 52,
          fontSize: 17,
          radius: 16,
          onPressed: () => Navigator.pop(context, const _UdharoResult(_Kind.remind)),
        ),
      ],
    );
  }
}
