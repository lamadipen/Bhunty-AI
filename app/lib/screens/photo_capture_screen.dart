import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/product_code.dart';
import '../data/models.dart';
import '../photos/photo_reader.dart';
import '../photos/photo_slot.dart';
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
                        PhotoSlot(
                          id: role.wire,
                          icon: switch (role) {
                            PhotoRole.front => Icons.inventory_2_outlined,
                            PhotoRole.barcode => Icons.qr_code_2_rounded,
                            PhotoRole.label => Icons.text_snippet_outlined,
                          },
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
