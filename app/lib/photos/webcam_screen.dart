import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../widgets/common.dart';

/// What the webcam screen hands back.
sealed class WebcamResult {
  const WebcamResult();
}

final class WebcamPhoto extends WebcamResult {
  const WebcamPhoto(this.bytes);
  final Uint8List bytes;
}

/// The camera couldn't be used and the user chose a file instead.
final class WebcamUseFiles extends WebcamResult {
  const WebcamUseFiles();
}

/// Live camera for desktop browsers, which ignore the camera hint on a file
/// input and would open the file picker. Every failure has a way out: retry,
/// or choose a file.
class WebcamScreen extends StatefulWidget {
  const WebcamScreen({super.key, this.findCameras = availableCameras});

  /// Replaced in tests (the camera plugin isn't available there).
  final Future<List<CameraDescription>> Function() findCameras;

  static Future<WebcamResult?> open(BuildContext context) => Navigator.of(
    context,
  ).push<WebcamResult>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const WebcamScreen()));

  @override
  State<WebcamScreen> createState() => _WebcamScreenState();
}

class _WebcamScreenState extends State<WebcamScreen> {
  List<CameraDescription> _cameras = const [];
  int _which = 0;
  CameraController? _controller;
  String? _problem;
  bool _busy = false;

  /// The shot waiting for "ठीक छ" (a webcam photo is easy to blur).
  Uint8List? _shot;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _problem = null;
      _busy = true;
    });
    try {
      if (_cameras.isEmpty) _cameras = await widget.findCameras();
      if (_cameras.isEmpty) throw CameraException('cameraNotFound', null);
      // Prefer a camera facing away from the user (a USB or phone-like back camera) when there is one.
      if (_controller == null) {
        final back = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
        _which = back < 0 ? 0 : back;
      }
      await _controller?.dispose();
      final controller = CameraController(_cameras[_which], ResolutionPreset.high, enableAudio: false);
      _controller = controller;
      await controller.initialize();
    } on CameraException catch (e) {
      debugPrint('Bhunte: webcam ${e.code}: ${e.description}');
      _controller = null;
      _problem = switch (e.code) {
        'cameraNotFound' => 'यो कम्प्युटरमा क्यामेरा भेटिएन। फाइलबाट फोटो छान्नुस्।',
        'CameraAccessDenied' || 'cameraPermission' =>
          'क्यामेरा चलाउने अनुमति छैन। ब्राउजरको ठेगाना पट्टीको क्यामेरा आइकन थिचेर अनुमति दिनुस्, वा फाइल छान्नुस्।',
        _ => 'क्यामेरा खुलेन। फेरि प्रयास गर्नुस् वा फाइल छान्नुस्।',
      };
    } catch (e) {
      debugPrint('Bhunte: webcam: $e');
      _controller = null;
      _problem = 'क्यामेरा खुलेन। फेरि प्रयास गर्नुस् वा फाइल छान्नुस्।';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _take() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _shot = bytes);
    } catch (e) {
      debugPrint('Bhunte: webcam shot: $e');
      if (mounted) showToast(context, 'फोटो खिच्न सकिएन, फेरि थिच्नुस्');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _busy) return;
    _which = (_which + 1) % _cameras.length;
    await _start();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final shot = _shot;
    final Widget view;
    if (shot != null) {
      view = Image.memory(shot, key: const ValueKey('webcam-shot'), fit: BoxFit.contain);
    } else if (_problem != null) {
      view = _problemView(_problem!);
    } else if (controller != null && controller.value.isInitialized) {
      view = Center(
        child: AspectRatio(aspectRatio: controller.value.aspectRatio, child: CameraPreview(controller)),
      );
    } else {
      view = const Center(child: CircularProgressIndicator(color: BColors.white));
    }
    return Scaffold(
      backgroundColor: BColors.ink,
      body: Stack(
        children: [
          Positioned.fill(child: view),
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
                  if (_cameras.length > 1 && shot == null && _problem == null)
                    RoundIconButton(
                      key: const ValueKey('webcam-switch'),
                      icon: Icons.cameraswitch_outlined,
                      label: 'अर्को क्यामेरा',
                      background: const Color(0xCCFFFFFF),
                      onPressed: _switchCamera,
                    ),
                ],
              ),
            ),
          ),
          if (_problem == null)
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
                  child: shot == null
                      ? BigButton(
                          key: const ValueKey('webcam-take'),
                          label: 'फोटो खिच्नुस्',
                          icon: Icons.photo_camera_rounded,
                          height: 66,
                          color: controller?.value.isInitialized == true && !_busy ? BColors.green : BColors.disabled,
                          onPressed: controller?.value.isInitialized == true && !_busy ? _take : null,
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: BigButton(
                                key: const ValueKey('webcam-retake'),
                                label: 'फेरि खिच्नुस्',
                                outlineColor: BColors.line,
                                foreground: BColors.ink,
                                height: 66,
                                fontSize: 18,
                                onPressed: () => setState(() => _shot = null),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: BigButton(
                                key: const ValueKey('webcam-use'),
                                label: 'ठीक छ',
                                trailingIcon: Icons.check_rounded,
                                height: 66,
                                onPressed: () => Navigator.of(context).pop(WebcamPhoto(shot)),
                              ),
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

  // Scrolls so the buttons stay reachable on a short window.
  Widget _problemView(String problem) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 80, 28, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined, color: BColors.white, size: 56),
          const SizedBox(height: 12),
          Text(
            problem,
            key: const ValueKey('webcam-problem'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, color: BColors.white, height: 1.4),
          ),
          const SizedBox(height: 16),
          BigButton(
            key: const ValueKey('webcam-files'),
            label: 'फाइल छान्नुस्',
            icon: Icons.photo_library_outlined,
            height: 56,
            fontSize: 18,
            onPressed: () => Navigator.of(context).pop(const WebcamUseFiles()),
          ),
          const SizedBox(height: 10),
          BigButton(
            key: const ValueKey('webcam-retry'),
            label: 'फेरि प्रयास गर्नुस्',
            icon: Icons.refresh_rounded,
            outlineColor: BColors.white,
            outlineFill: BColors.ink,
            foreground: BColors.white,
            height: 56,
            fontSize: 18,
            onPressed: _start,
          ),
        ],
      ),
    ),
  );
}
