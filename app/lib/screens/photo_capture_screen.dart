import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/product_code.dart';
import '../data/models.dart';
import '../photos/photo_reader.dart';
import '../photos/photo_source.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';

/// What the capture screen hands back.
sealed class PhotoOutcome {
  const PhotoOutcome();
}

/// Suggestions for the new-product form. Nothing here is saved until the
/// shopkeeper taps save on the form (PR1).
final class PhotoDraft extends PhotoOutcome {
  const PhotoDraft({
    this.reading,
    this.problem,
    this.thumbnail,
    this.barcode,
    this.barcodeByAi = false,
    this.barcodeUnread = false,
  });

  final PhotoReading? reading;

  /// Why the AI didn't fill the form; the form says so (PR9, PR10, F-17).
  final PhotoReadProblem? problem;

  /// From the front photo (D3).
  final ProductImage? thumbnail;

  /// A checked code: read on the phone, else the AI's digits (PR3).
  final String? barcode;
  final bool barcodeByAi;

  /// A barcode photo was taken but no code came out of it (F-3).
  final bool barcodeUnread;
}

/// The photographed barcode belongs to a product already in the shop, and the
/// shopkeeper chose to add stock to it (F-4).
final class PhotoFoundExisting extends PhotoOutcome {
  const PhotoFoundExisting(this.product);
  final Product product;
}

/// "फोटोबाट सामान थप्नुस्": three photo slots (front, barcode, label), each
/// from the camera or the gallery / files, then पढ्नुस् (docs/product-photos.md §2).
class PhotoCaptureScreen extends StatefulWidget {
  const PhotoCaptureScreen({super.key, this.offerExisting = true});

  /// Ask "पहिल्यै छ — स्टक थप्ने?" when the barcode is already in the shop.
  /// Off when opened from the form, where saving reports a taken code anyway.
  final bool offerExisting;

  static Future<PhotoOutcome?> open(BuildContext context, {bool offerExisting = true}) => Navigator.of(
    context,
  ).push<PhotoOutcome>(MaterialPageRoute(builder: (_) => PhotoCaptureScreen(offerExisting: offerExisting)));

  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

const _slots = [
  (PhotoRole.front, '१ सामानको फोटो', 'ग्रिडमा देखिने फोटो'),
  (PhotoRole.barcode, '२ बारकोड', 'बारकोड भए खिच्नुस् (नभए पनि हुन्छ)'),
  (PhotoRole.label, '३ विवरण भएको फोटो', 'नाम, तौल/मात्रा, MRP देखिने भाग'),
];

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen> {
  final Map<PhotoRole, PickedPhoto> _photos = {};
  bool _busy = false;

  /// Shown after a failed read (F-7), with a way to carry on by hand.
  PhotoReadProblem? _problem;

  Future<void> _pick(PhotoRole role, PhotoFrom from) async {
    final photo = await context.photoSource.pick(context, from);
    if (photo == null || !mounted) return;
    setState(() {
      _photos[role] = photo;
      _problem = null;
    });
  }

  Future<void> _read() async {
    if (_photos.isEmpty || _busy) return;
    final source = context.photoSource, reader = context.photoReader;
    setState(() => _busy = true);
    try {
      final barcodePhoto = _photos[PhotoRole.barcode];
      final phoneCode = barcodePhoto == null ? null : await source.readBarcode(barcodePhoto);
      if (phoneCode != null && await _offeredExisting(phoneCode)) return;

      // D5: the AI reads front + label, and the barcode photo only if the phone couldn't.
      final forAi = {
        for (final e in _photos.entries)
          if (e.key != PhotoRole.barcode || phoneCode == null) e.key: e.value.jpeg,
      };
      final result = forAi.isEmpty ? null : await reader.read(forAi, barcodeOnPhone: phoneCode);
      if (!mounted) return;
      if (result case PhotoReadFailed(problem: PhotoReadProblem.unreadable)) {
        setState(() => _problem = PhotoReadProblem.unreadable);
        return;
      }
      final reading = result is PhotoRead ? result.reading : null;
      final aiCode = reading?.barcode == null ? null : checkProductCode(reading!.barcode!).code;
      if (phoneCode == null && aiCode != null && await _offeredExisting(aiCode)) return;
      final front = _photos[PhotoRole.front];
      _finish(
        PhotoDraft(
          reading: reading,
          problem: result is PhotoReadFailed ? result.problem : null,
          thumbnail: front == null ? null : await _thumbnail(front),
          barcode: phoneCode ?? aiCode,
          barcodeByAi: phoneCode == null && aiCode != null,
          barcodeUnread: barcodePhoto != null && phoneCode == null && aiCode == null,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Carries on with only the thumbnail and the phone's barcode read (F-7).
  Future<void> _fillByHand() async {
    final barcodePhoto = _photos[PhotoRole.barcode], front = _photos[PhotoRole.front];
    setState(() => _busy = true);
    final code = barcodePhoto == null ? null : await context.photoSource.readBarcode(barcodePhoto);
    final thumbnail = front == null ? null : await _thumbnail(front);
    if (!mounted) return;
    setState(() => _busy = false);
    _finish(PhotoDraft(thumbnail: thumbnail, barcode: code, barcodeUnread: barcodePhoto != null && code == null));
  }

  void _finish(PhotoDraft draft) => Navigator.pop(context, draft);

  Future<ProductImage?> _thumbnail(PickedPhoto photo) => context.photoSource.thumbnail(photo);

  /// True when the code is already in the shop and the screen has closed (F-4).
  Future<bool> _offeredExisting(String code) async {
    final existing = widget.offerExisting ? context.readStore.productByBarcode(code) : null;
    if (existing == null || !mounted) return false;
    final addStock = await showBhunteSheet<bool>(
      context,
      (c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('पहिल्यै छ: ${existing.nameNe}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
            'यो बारकोड पसलको सामानमा पहिल्यै छ। स्टक थप्ने?',
            style: TextStyle(fontSize: 16, color: BColors.inkSoft, height: 1.35),
          ),
          const SizedBox(height: 16),
          BigButton(
            key: const ValueKey('existing-add-stock'),
            label: 'स्टक थप्नुस्',
            onPressed: () => Navigator.pop(c, true),
          ),
          const SizedBox(height: 8),
          BigButton(
            label: 'होइन, फोटोमा फर्कनुस्',
            outlineColor: BColors.line,
            foreground: BColors.ink,
            height: 56,
            fontSize: 18,
            onPressed: () => Navigator.pop(c, false),
          ),
        ],
      ),
    );
    if (addStock == true && mounted) {
      Navigator.pop(context, PhotoFoundExisting(existing));
      return true;
    }
    // "No" (or closed): back to the photos, which stay as they were.
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const ScreenHeader(title: 'फोटोबाट सामान थप्नुस्', subtitle: 'फोटो खिच्नुस्, भुन्टेले फारम भर्छ'),
                Expanded(
                  child: ListView(
                    key: const ValueKey('photo-slots'),
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final (role, title, hint) in _slots) ...[
                        _Slot(
                          role: role,
                          title: title,
                          hint: hint,
                          photo: _photos[role],
                          onPick: (from) => _pick(role, from),
                          onRemove: () => setState(() => _photos.remove(role)),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const Text(
                        'भुन्टेले नाम, तौल र बारकोड भर्छ। मूल्य र स्टक तपाईं आफैं लेख्नुहुन्छ।',
                        style: TextStyle(fontSize: 15, color: BColors.inkSoft, height: 1.35),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: BColors.white,
                    border: Border(top: BorderSide(color: BColors.line)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_problem != null) ...[
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _problem!.message,
                            key: const ValueKey('photo-problem'),
                            style: const TextStyle(fontSize: 16, color: BColors.warnInk, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 8),
                        BigButton(
                          key: const ValueKey('fill-by-hand'),
                          label: 'हातैले भर्नुस्',
                          outlineColor: BColors.green,
                          foreground: BColors.green,
                          height: 56,
                          fontSize: 18,
                          onPressed: _fillByHand,
                        ),
                        const SizedBox(height: 8),
                      ],
                      BigButton(
                        key: const ValueKey('read-photos'),
                        label: 'पढ्नुस्',
                        icon: Icons.auto_awesome_rounded,
                        height: 66,
                        color: _photos.isEmpty ? BColors.disabled : BColors.green,
                        onPressed: _photos.isEmpty ? null : _read,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_busy)
              const BusyOverlay(
                icon: Icons.auto_awesome_rounded,
                title: 'भुन्टेले फोटो पढ्दैछ…',
                subtitle: 'केही सेकेन्ड',
                accent: BColors.green,
              ),
          ],
        ),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.role,
    required this.title,
    required this.hint,
    required this.photo,
    required this.onPick,
    required this.onRemove,
  });

  final PhotoRole role;
  final String title;
  final String hint;
  final PickedPhoto? photo;
  final ValueChanged<PhotoFrom> onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    return CardBox(
      key: ValueKey('slot-${role.wire}'),
      radius: 18,
      borderColor: photo == null ? BColors.line : BColors.green,
      borderWidth: photo == null ? 1 : 2,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            height: 88,
            child: photo == null
                ? DecoratedBox(
                    decoration: BoxDecoration(color: BColors.ground, borderRadius: BorderRadius.circular(14)),
                    child: Icon(_icon, color: BColors.muted, size: 36),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(photo.jpeg, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 264),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                    if (photo != null)
                      RoundIconButton(
                        key: ValueKey('remove-${role.wire}'),
                        icon: Icons.close_rounded,
                        label: 'फोटो हटाउनुस्',
                        size: 44,
                        onPressed: onRemove,
                      ),
                  ],
                ),
                Text(hint, style: const TextStyle(fontSize: 14, color: BColors.inkSoft)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _SmallButton(
                        key: ValueKey('camera-${role.wire}'),
                        icon: photo == null ? Icons.photo_camera_outlined : Icons.refresh_rounded,
                        label: photo == null ? 'क्यामेरा' : 'फेरि खिच्नुस्',
                        onTap: () => onPick(PhotoFrom.camera),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SmallButton(
                        key: ValueKey('gallery-${role.wire}'),
                        icon: Icons.photo_library_outlined,
                        label: 'ग्यालरी/फाइल',
                        onTap: () => onPick(PhotoFrom.gallery),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData get _icon => switch (role) {
    PhotoRole.front => Icons.inventory_2_outlined,
    PhotoRole.barcode => Icons.qr_code_2_rounded,
    PhotoRole.label => Icons.text_snippet_outlined,
  };
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Material(
      color: BColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: BColors.line, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: BColors.green),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
