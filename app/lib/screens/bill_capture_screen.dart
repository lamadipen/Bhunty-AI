import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../bills/bill_mapping.dart';
import '../bills/bill_reader.dart';
import '../data/bill.dart';
import '../photos/image_shrink.dart';
import '../photos/photo_slot.dart';
import '../photos/photo_source.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';

/// "बिलको फोटो खिच्नुस्": 1–3 pages, then पढ्नुस् (docs/stock-from-bill.md §2.1).
/// Returns the bill to check — read from the photos, or empty for building it
/// by hand when reading failed — or null.
class BillCaptureScreen extends StatefulWidget {
  const BillCaptureScreen({super.key});

  static Future<BillDraft?> open(BuildContext context) =>
      Navigator.of(context).push<BillDraft>(MaterialPageRoute(builder: (_) => const BillCaptureScreen()));

  @override
  State<BillCaptureScreen> createState() => _BillCaptureScreenState();
}

const _pageNames = ['पेज १', 'पेज २', 'पेज ३'];

class _BillCaptureScreenState extends State<BillCaptureScreen> {
  final List<PickedPhoto> _pages = [];
  bool _busy = false;
  BillReadProblem? _problem;

  Future<void> _pick(int index, PhotoFrom from) async {
    final photo = await context.photoSource.pick(context, from, maxSide: billPageSide);
    if (photo == null || !mounted) return;
    setState(() {
      if (index < _pages.length) {
        _pages[index] = photo;
      } else {
        _pages.add(photo);
      }
      _problem = null;
    });
  }

  Future<void> _read() async {
    if (_pages.isEmpty || _busy) return;
    final store = context.readStore, reader = context.billReader;
    setState(() => _busy = true);
    // Hidden products too, so a match to one can offer to show it again (BR8).
    final catalog = [
      for (final p in [...store.products, ...store.archivedProducts]) catalogEntry(p),
    ];
    final result = await reader.read([for (final p in _pages) p.jpeg], catalog);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case BillRead(:final reading):
        Navigator.pop(context, draftFromReading(reading, store));
      case BillReadFailed(:final problem):
        setState(() => _problem = problem);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The next page slot appears once the previous one has a photo.
    final slots = (_pages.length + 1).clamp(1, _pageNames.length);
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const ScreenHeader(title: 'बिलको फोटो खिच्नुस्', subtitle: 'लामो बिल भए ३ पेजसम्म'),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (var i = 0; i < slots; i++) ...[
                        PhotoSlot(
                          id: 'page$i',
                          icon: Icons.receipt_long_outlined,
                          title: _pageNames[i],
                          hint: i == 0 ? 'सबै लाइन र जम्मा देखिने गरी' : 'बाँकी लाइनहरू',
                          photo: i < _pages.length ? _pages[i] : null,
                          onPick: (from) => _pick(i, from),
                          onRemove: () => setState(() => _pages.removeAt(i)),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const Text(
                        'भुन्टेले बिल पढ्छ। तपाईंले हेरेर "स्टकमा थप्नुस्" नथिचेसम्म केही पनि सुरक्षित हुँदैन।',
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
                            key: const ValueKey('bill-problem'),
                            style: const TextStyle(fontSize: 16, color: BColors.warnInk, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 8),
                        BigButton(
                          key: const ValueKey('bill-by-hand'),
                          label: 'हातैले बिल बनाउनुस्',
                          outlineColor: BColors.green,
                          foreground: BColors.green,
                          height: 56,
                          fontSize: 18,
                          onPressed: () => Navigator.pop(context, BillDraft()),
                        ),
                        const SizedBox(height: 8),
                      ],
                      BigButton(
                        key: const ValueKey('read-bill'),
                        label: 'पढ्नुस्',
                        icon: Icons.auto_awesome_rounded,
                        height: 66,
                        color: _pages.isEmpty ? BColors.disabled : BColors.green,
                        onPressed: _pages.isEmpty ? null : _read,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_busy)
              const BusyOverlay(
                icon: Icons.document_scanner_outlined,
                title: 'भुन्टेले बिल पढ्दैछ…',
                subtitle: 'केही सेकेन्ड',
                accent: BColors.green,
              ),
          ],
        ),
      ),
    );
  }
}
