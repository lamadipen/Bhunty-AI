import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// White top bar with a round back button, a big Nepali title and a small subtitle.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.subtitle, this.subtitleColor, this.badge});

  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: BColors.white,
        border: Border(bottom: BorderSide(color: BColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          RoundIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            label: 'पछाडि · Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          if (badge != null) ...[badge!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.1)),
                if (subtitle != null)
                  Text(subtitle!, style: TextStyle(fontSize: 14, color: subtitleColor ?? BColors.inkSoft, height: 1.2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 48,
    this.background = BColors.ground,
    this.border,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final Color background;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: background,
        shape: CircleBorder(side: border == null ? BorderSide.none : BorderSide(color: border!)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size * 0.5, color: BColors.ink),
          ),
        ),
      ),
    );
  }
}

/// Large primary action (64–76 px, principle 6).
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = BColors.green,
    this.foreground = BColors.white,
    this.height = 64,
    this.icon,
    this.outlineColor,
    this.fontSize = 21,
    this.radius = 20,
    this.alignStart = false,
    this.outlineFill = BColors.white,
    this.trailingIcon,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color foreground;
  final double height;
  final IconData? icon;

  /// When set the button is white with this border colour.
  final Color? outlineColor;
  final double fontSize;
  final double radius;
  final bool alignStart;

  /// Fill colour used together with [outlineColor].
  final Color outlineFill;

  /// Drawn after the label, e.g. ✓ — Mukta has no ✓/✕ glyphs, so use icons.
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: outlineColor == null ? BorderSide.none : BorderSide(color: outlineColor!, width: 2),
    );
    final content = Row(
      mainAxisSize: alignStart ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, color: foreground, size: 28), const SizedBox(width: 12)],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, color: foreground, height: 1.15),
          ),
        ),
        if (trailingIcon != null) ...[
          const SizedBox(width: 8),
          Icon(trailingIcon, color: foreground, size: fontSize + 4),
        ],
      ],
    );
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: Material(
        color: outlineColor != null ? outlineFill : color,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: alignStart ? content : Center(child: content),
            ),
          ),
        ),
      ),
    );
  }
}

/// "होइन ✕ / ठीक छ ✓" pair (drawn with icons) used on every confirm card.
class ConfirmButtons extends StatelessWidget {
  const ConfirmButtons({super.key, required this.onNo, required this.onYes, this.height = 64});

  final VoidCallback onNo;
  final VoidCallback onYes;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: BigButton(
            label: 'होइन',
            trailingIcon: Icons.close_rounded,
            outlineColor: BColors.line,
            foreground: BColors.ink,
            height: height,
            fontSize: 20,
            onPressed: onNo,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: BigButton(
            label: 'ठीक छ',
            trailingIcon: Icons.check_rounded,
            height: height,
            fontSize: 20,
            onPressed: onYes,
          ),
        ),
      ],
    );
  }
}

/// White rounded card with the standard hairline border.
class CardBox extends StatelessWidget {
  const CardBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.color = BColors.white,
    this.borderColor = BColors.line,
    this.borderWidth = 1,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  final Color borderColor;
  final double borderWidth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: borderColor, width: borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Picture placeholder: short Devanagari letters on a tinted tile.
class LetterTile extends StatelessWidget {
  const LetterTile({
    super.key,
    required this.letter,
    required this.bg,
    required this.ink,
    this.size = 44,
    this.circle = false,
  });

  final String letter;
  final Color bg;
  final Color ink;
  final double size;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(circle ? size / 2 : size * 0.3)),
      child: Text(
        letter,
        style: TextStyle(fontSize: size * 0.43, fontWeight: FontWeight.w800, color: ink, height: 1),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.bg, required this.fg, this.fontSize = 15});

  final String text;
  final Color bg;
  final Color fg;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        text,
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// Dark overlay while the mic listens or a photo is read.
class BusyOverlay extends StatelessWidget {
  const BusyOverlay({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.accent = BColors.orange,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Semantics(
        liveRegion: true,
        label: title,
        child: Container(
          color: const Color(0xB817201B),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: accent.withValues(alpha: 0.3), spreadRadius: 18),
                    BoxShadow(color: accent.withValues(alpha: 0.15), spreadRadius: 36),
                  ],
                ),
                child: Icon(icon, size: 64, color: BColors.white),
              ),
              const SizedBox(height: 48),
              Text(
                title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: BColors.white),
              ),
              Text(subtitle, style: const TextStyle(fontSize: 17, color: Color(0xE6FFFFFF))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens a rounded bottom sheet in the app's style.
Future<T?> showBhunteSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (c) => SafeArea(
      top: false,
      child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 22), child: builder(c)),
    ),
  );
}

/// Short dark message near the top that fades by itself.
void showToast(BuildContext context, String message) {
  _toast?.remove();
  _toastTimer?.cancel();
  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (c) => Positioned(
      left: 16,
      right: 16,
      top: MediaQuery.of(c).padding.top + 76,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 528),
          child: Material(
            color: BColors.ink,
            borderRadius: BorderRadius.circular(16),
            child: Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.check_rounded, color: BColors.greenOnDark, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: BColors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  _toast = entry;
  _toastTimer = Timer(const Duration(milliseconds: 1800), () {
    if (_toast == entry) {
      entry.remove();
      _toast = null;
    }
  });
}

OverlayEntry? _toast;
Timer? _toastTimer;
