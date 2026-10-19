import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/money.dart';
import '../core/qty.dart';
import '../data/models.dart';
import '../theme/theme.dart';
import 'common.dart';

String priceLabel(Product p) => p.unit.isLoose ? '${formatRs(p.pricePaisa)}/${p.unit.ne}' : formatRs(p.pricePaisa);

String stockLabel(Product p) => 'बाँकी ${formatQty(p.stockMilli)} ${p.unit.ne}';

/// Picture-grid tile: letters on a tint, name, and a caption (price by default).
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    required this.onTap,
    this.badgeMilli = 0,
    this.caption,
    this.warn = false,
    this.action = 'एउटा थप्नुस्',
  });

  final Product product;
  final VoidCallback onTap;

  /// Quantity shown in the green corner badge; hidden when 0.
  final int badgeMilli;
  final String? caption;

  /// Highlights the tile (e.g. low stock).
  final bool warn;

  /// What a tap does, for screen readers.
  final String action;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final text = caption ?? priceLabel(p);
    return Semantics(
      button: true,
      label: '${p.nameNe} ${p.nameEn}, $text, $action',
      excludeSemantics: true,
      child: Stack(
        children: [
          Positioned.fill(
            child: CardBox(
              key: ValueKey('tile-${p.id}'),
              radius: 18,
              color: warn ? BColors.warnCard : BColors.white,
              borderColor: warn ? BColors.warnBorder : BColors.line,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              onTap: onTap,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  LetterTile(letter: p.letter, bg: Color(p.tileBg), ink: Color(p.tileInk)),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      p.nameNe,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.2),
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1,
                        color: warn ? BColors.warnInk : BColors.inkSoft,
                        fontWeight: warn ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (badgeMilli > 0)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                constraints: const BoxConstraints(minWidth: 24),
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: BColors.green, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  formatQty(badgeMilli),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: BColors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fixed 4-column grid. With [maxTiles], the last slot becomes "सबै" (all) when there are more.
class ProductGrid extends StatelessWidget {
  const ProductGrid({super.key, required this.products, required this.tileFor, this.maxTiles, this.onMore});

  final List<Product> products;
  final Widget Function(Product) tileFor;
  final int? maxTiles;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final limit = maxTiles;
    final overflow = limit != null && products.length > limit;
    final shown = overflow ? products.take(limit - 1).toList() : products;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: shown.length + (overflow ? 1 : 0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisExtent: 104,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (c, i) => i < shown.length ? tileFor(shown[i]) : _MoreTile(count: products.length, onTap: onMore),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.count, required this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'सबै $count सामान हेर्नुस्',
      excludeSemantics: true,
      child: CardBox(
        key: const ValueKey('tile-more'),
        radius: 18,
        color: BColors.greenTint,
        borderColor: BColors.greenTint,
        padding: const EdgeInsets.all(6),
        onTap: onTap,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.grid_view_rounded, color: BColors.green, size: 32),
              const Text(
                'सबै',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: BColors.greenDark),
              ),
              Text('$count सामान', style: const TextStyle(fontSize: 13, color: BColors.greenDark)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every product in a scrollable grid; returns the one tapped.
Future<Product?> showProductPicker(BuildContext context, {required String title, String Function(Product)? caption}) {
  return showBhunteSheet<Product>(context, (c) {
    final products = c.store.products;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            RoundIconButton(
              icon: Icons.close_rounded,
              label: 'बन्द गर्नुस्',
              size: 44,
              onPressed: () => Navigator.pop(c),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.6),
          child: GridView.builder(
            shrinkWrap: true,
            itemCount: products.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisExtent: 104,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (_, i) => ProductTile(
              product: products[i],
              caption: caption?.call(products[i]),
              action: 'छान्नुस्',
              onTap: () => Navigator.pop(c, products[i]),
            ),
          ),
        ),
      ],
    );
  });
}
