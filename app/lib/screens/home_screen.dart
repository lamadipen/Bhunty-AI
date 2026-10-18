import 'package:flutter/material.dart';

import '../ai/answers.dart';
import '../app.dart';
import '../app_scope.dart';
import '../core/money.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final today = store.today;
    final low = store.lowStock;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(
                            'assets/brand/bhunte-logo.png',
                            width: 52,
                            height: 52,
                            semanticLabel: 'Bhunte AI',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'भुन्टे',
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: BColors.green,
                                  height: 1,
                                ),
                              ),
                              Text(store.shopName, style: const TextStyle(fontSize: 14, color: BColors.inkSoft)),
                            ],
                          ),
                        ),
                        RoundIconButton(
                          icon: Icons.person_outline_rounded,
                          label: 'पसल · Shop',
                          background: BColors.white,
                          border: BColors.line,
                          onPressed: () => _showShopSheet(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    CardBox(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                      onTap: () => Navigator.pushNamed(context, Routes.reports),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "आजको बिक्री · Today's sales",
                            style: TextStyle(fontSize: 16, color: BColors.inkSoft),
                          ),
                          Text(
                            formatRs(today.totalPaisa),
                            style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800, height: 1.15),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Pill('नगद ${formatRs(today.cashPaisa)}', bg: BColors.greenTint, fg: BColors.greenDark),
                              Pill('QR ${formatRs(today.qrPaisa)}', bg: BColors.blueTint, fg: BColors.blue),
                              if (today.udharoPaisa > 0)
                                Pill('उधारो ${formatRs(today.udharoPaisa)}', bg: BColors.warnBg, fg: BColors.warnInk),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _HomeTile(
                            icon: Icons.shopping_cart_outlined,
                            title: 'बेच्नुस्',
                            subtitle: 'Sell',
                            filled: true,
                            onTap: () => Navigator.pushNamed(context, Routes.sell),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _HomeTile(
                            icon: Icons.inventory_2_outlined,
                            iconColor: BColors.green,
                            title: 'स्टक थप्नुस्',
                            subtitle: 'Add stock',
                            onTap: () => Navigator.pushNamed(context, Routes.stock),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _HomeTile(
                            icon: Icons.receipt_long_outlined,
                            iconColor: BColors.orange,
                            title: 'उधारो',
                            subtitle: 'Credit book',
                            badge: store.totalUdharoPaisa > 0 ? formatRs(store.totalUdharoPaisa) : null,
                            onTap: () => Navigator.pushNamed(context, Routes.udharo),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _HomeTile(
                            icon: Icons.bar_chart_rounded,
                            iconColor: BColors.blue,
                            title: 'हिसाब',
                            subtitle: 'Reports',
                            onTap: () => Navigator.pushNamed(context, Routes.reports),
                          ),
                        ),
                      ],
                    ),
                    if (low.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      CardBox(
                        color: BColors.warnBg,
                        borderColor: BColors.warnBg,
                        radius: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        onTap: () => Navigator.pushNamed(context, Routes.stock),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: BColors.warnInk, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${low.length} सामान सकिँदैछ',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: BColors.warnInk,
                                    ),
                                  ),
                                  Text(
                                    '${joinNe([for (final p in low) p.nameNe])} · थिच्नुस्',
                                    style: const TextStyle(fontSize: 14, color: BColors.warnInk),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    const SizedBox(height: 16),
                    BigButton(
                      label: 'भुन्टेलाई भन्नुस्',
                      icon: Icons.mic_none_rounded,
                      color: BColors.orange,
                      height: 76,
                      radius: 38,
                      fontSize: 22,
                      onPressed: () => Navigator.pushNamed(context, Routes.assistant),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showShopSheet(BuildContext context) {
    final store = context.readStore;
    showBhunteSheet<void>(
      context,
      (c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset('assets/brand/bhunte-logo.png', width: 44, height: 44),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(store.shopName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Bhunte AI · demo data. लगइन, पसलको सेटिङ र Firebase sync अर्को चरणमा आउँछ।',
            style: TextStyle(fontSize: 16, color: BColors.inkSoft),
          ),
          const SizedBox(height: 16),
          BigButton(label: 'ठीक छ', onPressed: () => Navigator.pop(c)),
        ],
      ),
    );
  }
}

class _HomeTile extends StatelessWidget {
  const _HomeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor = BColors.white,
    this.filled = false,
    this.badge,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool filled;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? BColors.white : BColors.ink;
    return Semantics(
      button: true,
      label: '$title · $subtitle',
      excludeSemantics: true,
      child: CardBox(
        color: filled ? BColors.green : BColors.white,
        borderColor: filled ? BColors.green : BColors.line,
        radius: 24,
        padding: const EdgeInsets.all(18),
        onTap: onTap,
        child: SizedBox(
          height: 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 44, color: filled ? BColors.white : iconColor),
                  const SizedBox(width: 6),
                  if (badge != null)
                    Expanded(
                      child: Align(
                        alignment: Alignment.topRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Pill(badge!, bg: BColors.warnBg, fg: BColors.warnInk, fontSize: 14),
                        ),
                      ),
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: fg, height: 1.1),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 15, color: filled ? const Color(0xE6FFFFFF) : BColors.inkSoft),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
