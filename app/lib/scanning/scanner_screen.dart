import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../ai/assistant_service.dart';
import '../core/product_code.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import 'manual_code_sheet.dart';

/// Real scanning with the phone camera (ML Kit on Android/iOS, ZXing on web).
class CameraBarcodeScanner implements BarcodeScanner {
  const CameraBarcodeScanner();

  @override
  Future<String?> scan(BuildContext context) => Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ScannerScreen()));
}

/// Draws the camera and reports raw values; replaced in tests.
typedef ScannerPreviewBuilder =
    Widget Function(BuildContext context, ValueChanged<String> onRaw, Widget Function(String problem) onError);

/// Full-screen scanner. Every way it can fail has a way out: typing the
/// number, retrying the camera, or closing.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, this.preview});

  final ScannerPreviewBuilder? preview;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  MobileScannerController? _controller;
  String? _notice;
  String? _lastRejected;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (widget.preview == null) {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        // Retail and distributor codes, plus QR for the shop's own labels.
        formats: const [
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
          BarcodeFormat.code128,
          BarcodeFormat.code39,
          BarcodeFormat.itf14,
          BarcodeFormat.qrCode,
        ],
      );
    }
  }

  @override
  void dispose() {
    // MobileScanner itself frees the camera while the app is in the background.
    _controller?.dispose();
    super.dispose();
  }

  void _onRaw(String raw) {
    if (_done || raw == _lastRejected) return;
    final check = checkProductCode(raw);
    if (check.error != null) {
      setState(() {
        _lastRejected = raw;
        _notice = check.error;
      });
      return;
    }
    _done = true;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(check.code);
  }

  Future<void> _typeInstead() async {
    await _controller?.stop();
    if (!mounted) return;
    final code = await ManualCodeSheet.open(context);
    if (!mounted) return;
    if (code != null) {
      _done = true;
      Navigator.of(context).pop(code);
    } else {
      await _controller?.start();
    }
  }

  Widget _cameraProblem(String problem) => ColoredBox(
    color: BColors.ink,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: BColors.white, size: 56),
            const SizedBox(height: 12),
            Text(
              problem,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, color: BColors.white, height: 1.4),
            ),
            if (_controller != null) ...[
              const SizedBox(height: 16),
              BigButton(
                label: 'फेरि प्रयास गर्नुस्',
                icon: Icons.refresh_rounded,
                outlineColor: BColors.white,
                outlineFill: BColors.ink,
                foreground: BColors.white,
                height: 56,
                fontSize: 18,
                onPressed: () => _controller!.start(),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _defaultPreview() => MobileScanner(
    controller: _controller,
    // Only while the camera is live, so it never covers an error message.
    overlayBuilder: (context, constraints) => const IgnorePointer(child: _AimFrame()),
    onDetect: (capture) {
      for (final b in capture.barcodes) {
        final raw = b.rawValue;
        if (raw != null && raw.isNotEmpty) {
          _onRaw(raw);
          return;
        }
      }
    },
    errorBuilder: (context, error) => _cameraProblem(switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'क्यामेरा चलाउने अनुमति छैन। फोनको सेटिङमा Bhunte लाई क्यामेरा अनुमति दिनुस्, वा तल नम्बर लेख्नुस्।',
      MobileScannerErrorCode.unsupported => 'यो उपकरणमा क्यामेरा चलेन। तल नम्बर लेख्नुस्।',
      _ => 'क्यामेरा खुलेन। फेरि प्रयास गर्नुस् वा तल नम्बर लेख्नुस्।',
    }),
  );

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview?.call(context, _onRaw, _cameraProblem) ?? _defaultPreview();
    return Scaffold(
      backgroundColor: BColors.ink,
      body: Stack(
        children: [
          Positioned.fill(child: preview),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  RoundIconButton(
                    icon: Icons.close_rounded,
                    label: 'बन्द गर्नुस्',
                    background: const Color(0xCCFFFFFF),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  if (_controller != null)
                    RoundIconButton(
                      icon: Icons.flashlight_on_outlined,
                      label: 'बत्ती',
                      background: const Color(0xCCFFFFFF),
                      onPressed: () => _controller!.toggleTorch(),
                    ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: const BoxDecoration(
                color: BColors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _notice ?? 'बारकोड वा QR फ्रेमभित्र राख्नुस्',
                        key: const ValueKey('scan-notice'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _notice == null ? BColors.ink : BColors.warnInk,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    BigButton(
                      label: 'नम्बर हातैले लेख्नुस्',
                      icon: Icons.dialpad_rounded,
                      outlineColor: BColors.line,
                      foreground: BColors.ink,
                      height: 56,
                      fontSize: 18,
                      onPressed: _typeInstead,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AimFrame extends StatelessWidget {
  const _AimFrame();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.78,
        child: AspectRatio(
          aspectRatio: 1.4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: BColors.greenOnDark, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }
}
