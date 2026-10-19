import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/cash.dart';
import '../core/money.dart';
import '../data/models.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';

/// "कसरी तिर्नुभयो?" — cash, QR or udharo.
class PayMethodSheet extends StatelessWidget {
  const PayMethodSheet({super.key, required this.totalPaisa});

  final int totalPaisa;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('कसरी तिर्नुभयो?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            Text(formatRs(totalPaisa), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 12),
        BigButton(
          label: 'नगद · Cash',
          icon: Icons.payments_outlined,
          height: 72,
          fontSize: 22,
          alignStart: true,
          onPressed: () => Navigator.pop(context, PaymentMethod.cash),
        ),
        const SizedBox(height: 12),
        BigButton(
          label: 'QR · Fonepay / eSewa',
          icon: Icons.qr_code_2_rounded,
          color: BColors.blue,
          height: 72,
          fontSize: 22,
          alignStart: true,
          onPressed: () => Navigator.pop(context, PaymentMethod.qr),
        ),
        const SizedBox(height: 12),
        BigButton(
          label: 'उधारो · Credit',
          icon: Icons.receipt_long_outlined,
          color: BColors.orange,
          height: 72,
          fontSize: 22,
          alignStart: true,
          onPressed: () => Navigator.pop(context, PaymentMethod.udharo),
        ),
        const SizedBox(height: 4),
        BigButton(
          label: 'फर्कनुस्',
          color: BColors.white,
          foreground: BColors.inkSoft,
          height: 52,
          fontSize: 18,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

/// "ग्राहकले कति दिनुभयो?" — pick the note handed over; change is computed.
class CashSheet extends StatefulWidget {
  const CashSheet({super.key, required this.totalPaisa});

  final int totalPaisa;

  @override
  State<CashSheet> createState() => _CashSheetState();
}

class _CashSheetState extends State<CashSheet> {
  late int _tendered = widget.totalPaisa;

  @override
  Widget build(BuildContext context) {
    final options = suggestTenders(widget.totalPaisa);
    final change = changeDue(tenderedPaisa: _tendered, totalPaisa: widget.totalPaisa);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('ग्राहकले कति दिनुभयो?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            Text(formatRs(widget.totalPaisa), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.6,
          children: [
            for (final amt in options)
              BigButton(
                label: amt == widget.totalPaisa ? 'मिलेको' : formatRs(amt),
                outlineColor: _tendered == amt ? BColors.green : BColors.line,
                foreground: BColors.ink,
                fontSize: 22,
                radius: 18,
                onPressed: () => setState(() => _tendered = amt),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(color: BColors.greenTint, borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'फिर्ता दिनुस्',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: BColors.greenDark),
                ),
              ),
              Text(
                formatRs(change),
                key: const ValueKey('change'),
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: BColors.greenDark),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        BigButton(
          label: 'सकियो',
          trailingIcon: Icons.check_rounded,
          height: 68,
          fontSize: 22,
          onPressed: () => Navigator.pop(context, _tendered),
        ),
      ],
    );
  }
}

/// Static QR for now: the shopkeeper confirms after seeing the money arrive.
class QrSheet extends StatelessWidget {
  const QrSheet({super.key, required this.totalPaisa});

  final int totalPaisa;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('ग्राहकलाई यो QR देखाउनुस्', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: BColors.blue, width: 3),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.qr_code_2_rounded, size: 120, color: BColors.blue),
              Text(
                '[पसलको QR] · ${formatRs(totalPaisa)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: BColors.blue),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'फोनमा पैसा आएको हेरेर मात्र थिच्नुस्',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: BColors.warnInk, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: BigButton(
            label: 'पैसा आयो',
            trailingIcon: Icons.check_rounded,
            color: BColors.blue,
            onPressed: () => Navigator.pop(context, true),
          ),
        ),
      ],
    );
  }
}

/// "कसको नाममा लेख्ने?" — returns a customer id. New customers are added by voice, then confirmed.
class UdharoPickSheet extends StatefulWidget {
  const UdharoPickSheet({super.key, required this.totalPaisa});

  final int totalPaisa;

  @override
  State<UdharoPickSheet> createState() => _UdharoPickSheetState();
}

class _UdharoPickSheetState extends State<UdharoPickSheet> {
  bool _listening = false;
  String? _newName;

  Future<void> _listenForName() async {
    setState(() => _listening = true);
    final name = await context.assistant.listenForName();
    if (!mounted) return;
    setState(() {
      _listening = false;
      _newName = name;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    if (_newName != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('नयाँ ग्राहक बनाऊँ?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          CardBox(
            borderColor: BColors.orange,
            borderWidth: 2,
            child: Row(
              children: [
                LetterTile(
                  letter: String.fromCharCodes(_newName!.runes.take(2)),
                  bg: BColors.warnBg,
                  ink: BColors.warnInk,
                  size: 48,
                  circle: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_newName!, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                      Text(
                        'नयाँ · उधारो ${formatRs(widget.totalPaisa)}',
                        style: const TextStyle(fontSize: 16, color: BColors.warnInk, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ConfirmButtons(
            onNo: () => setState(() => _newName = null),
            onYes: () {
              final c = context.readStore.addCustomer(_newName!);
              Navigator.pop(context, c.id);
            },
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'कसको नाममा लेख्ने? · ${formatRs(widget.totalPaisa)}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in store.customers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: CardBox(
                    radius: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    onTap: () => Navigator.pop(context, c.id),
                    child: Row(
                      children: [
                        LetterTile(letter: c.initial, bg: BColors.warnBg, ink: BColors.warnInk, size: 44, circle: true),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        ),
                        if (c.balancePaisa > 0)
                          Text(
                            'बाँकी ${formatRs(c.balancePaisa)}',
                            style: const TextStyle(fontSize: 15, color: BColors.warnInk, fontWeight: FontWeight.w700),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        BigButton(
          label: _listening ? 'सुन्दैछु…' : '+ नयाँ ग्राहक (नाम बोल्नुस्)',
          icon: Icons.mic_none_rounded,
          outlineColor: BColors.orange,
          foreground: BColors.orange,
          height: 60,
          fontSize: 18,
          onPressed: _listening ? null : _listenForName,
        ),
      ],
    );
  }
}

/// Full-screen "बिक्री सकियो" end state (principle 6).
class SaleDoneView extends StatelessWidget {
  const SaleDoneView({super.key, required this.sale, required this.onNext, required this.onHome});

  final Sale sale;
  final VoidCallback onNext;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final store = context.readStore;
    final method = switch (sale.method) {
      PaymentMethod.cash => (sale.changePaisa ?? 0) > 0 ? 'नगद · फिर्ता ${formatRs(sale.changePaisa!)}' : 'नगद',
      PaymentMethod.qr => 'QR बाट आयो',
      PaymentMethod.udharo => 'उधारो · ${store.customer(sale.customerId!).name}को खातामा',
    };
    return Positioned.fill(
      child: Container(
        color: BColors.green,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(color: BColors.white, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 80, color: BColors.green),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'बिक्री सकियो',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: BColors.white),
            ),
            Text(
              formatRs(sale.totalPaisa),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: BColors.white, height: 1.1),
            ),
            Text(
              method,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, color: Color(0xEBFFFFFF)),
            ),
            const SizedBox(height: 32),
            BigButton(
              label: 'अर्को ग्राहक',
              color: BColors.white,
              foreground: BColors.green,
              height: 72,
              fontSize: 23,
              radius: 22,
              onPressed: onNext,
            ),
            const SizedBox(height: 12),
            BigButton(
              label: 'रसिद Viber मा पठाउनुस्',
              outlineColor: BColors.white,
              outlineFill: BColors.green,
              foreground: BColors.white,
              height: 60,
              fontSize: 19,
              onPressed: () => showToast(context, 'Viber जोडेपछि रसिद पठाउन मिल्छ'),
            ),
            TextButton(
              onPressed: onHome,
              child: const Text(
                'गृहमा फर्कनुस्',
                style: TextStyle(
                  fontSize: 18,
                  color: BColors.white,
                  decoration: TextDecoration.underline,
                  decorationColor: BColors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
