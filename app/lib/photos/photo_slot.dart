import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../widgets/common.dart';
import 'photo_source.dart';

/// One photo slot: placeholder or the picked photo, with camera and
/// gallery/file buttons and ✕. Keys use [id]: `slot-`, `camera-`, `gallery-`, `remove-`.
class PhotoSlot extends StatelessWidget {
  const PhotoSlot({
    super.key,
    required this.id,
    required this.icon,
    required this.title,
    required this.hint,
    required this.photo,
    required this.onPick,
    required this.onRemove,
  });

  final String id;
  final IconData icon;
  final String title;
  final String hint;
  final PickedPhoto? photo;
  final ValueChanged<PhotoFrom> onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    return CardBox(
      key: ValueKey('slot-$id'),
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
                    child: Icon(icon, color: BColors.muted, size: 36),
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
                        key: ValueKey('remove-$id'),
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
                        key: ValueKey('camera-$id'),
                        icon: photo == null ? Icons.photo_camera_outlined : Icons.refresh_rounded,
                        label: photo == null ? 'क्यामेरा' : 'फेरि खिच्नुस्',
                        onTap: () => onPick(PhotoFrom.camera),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SmallButton(
                        key: ValueKey('gallery-$id'),
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
