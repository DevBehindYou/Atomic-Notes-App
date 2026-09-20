import 'package:atomic_notes/profile/profile_store.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:flutter/material.dart';

/// A small popup with every bundled avatar. Tapping one sets it and closes.
class AvatarPickerDialog extends StatelessWidget {
  const AvatarPickerDialog({super.key});

  static const double _tile = 64;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.std,
        side: BorderSide(color: AppColors.ink, width: AppStroke.hairline),
      ),
      insetPadding: const EdgeInsets.all(AppSpace.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: AnimatedBuilder(
            animation: ProfileStore.instance,
            builder: (context, _) {
              final String current = ProfileStore.instance.avatarAsset;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const MonoLabel('PROFILE PHOTO'),
                  const SizedBox(height: AppSpace.sm),
                  const HairRule(color: AppColors.ink),
                  const SizedBox(height: AppSpace.md),
                  const EditorialHeading('Choose an avatar',
                      style: AppType.headlineSm),
                  const SizedBox(height: AppSpace.md),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpace.sm + 2,
                    runSpacing: AppSpace.sm + 2,
                    children: [
                      for (int i = 0; i < Avatars.all.length; i++)
                        _AvatarTile(
                          key: ValueKey(Avatars.all[i]),
                          asset: Avatars.all[i],
                          number: i + 1,
                          selected: Avatars.all[i] == current,
                          size: _tile,
                          onTap: () async {
                            await ProfileStore.instance
                                .setAvatar(Avatars.all[i]);
                            if (context.mounted) Navigator.pop(context);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.lg),
                  if (ProfileStore.instance.hasCustomAvatar) ...[
                    GhostButton(
                      label: 'Use default photo',
                      onTap: () async {
                        await ProfileStore.instance.setAvatar(null);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                    const SizedBox(height: AppSpace.sm),
                  ],
                  GhostButton(
                    label: 'Close',
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AvatarTile extends StatelessWidget {
  final String asset;
  final int number;
  final bool selected;
  final double size;
  final VoidCallback onTap;

  const _AvatarTile({
    required this.asset,
    required this.number,
    required this.selected,
    required this.size,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Avatar $number',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: size,
          width: size,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: selected ? AppColors.signal : AppColors.surfaceContainer,
            borderRadius: AppRadius.std,
            border: Border.all(
              color: selected ? AppColors.signal : AppColors.outlineVariant,
              width: AppStroke.hairline,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: AppRadius.sm,
                child: Image.asset(
                  asset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: AppColors.surfaceHighest),
                ),
              ),
              if (selected)
                const Align(
                  alignment: Alignment.bottomRight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.signal,
                      borderRadius: AppRadius.sm,
                    ),
                    child: Icon(Icons.check, size: 14, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
