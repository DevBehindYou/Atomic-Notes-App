import 'package:atomic_notes/profile/profile_store.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:flutter/material.dart';

/// The user's picture in an Ink frame, matching how the logo mark is framed.
/// Follows [ProfileStore], so changing the avatar updates every place at once.
class ProfileAvatar extends StatelessWidget {
  final double size;
  final double frame;

  const ProfileAvatar({required this.size, this.frame = 3, super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ProfileStore.instance,
      builder: (context, _) {
        return Container(
          height: size,
          width: size,
          padding: EdgeInsets.all(frame),
          decoration: const BoxDecoration(
            color: AppColors.ink,
            borderRadius: AppRadius.std,
          ),
          child: ClipRRect(
            borderRadius: AppRadius.sm,
            child: Image.asset(
              ProfileStore.instance.avatarAsset,
              fit: BoxFit.cover,
              // A missing file should leave a blank frame, not a red screen.
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: AppColors.surfaceHighest),
            ),
          ),
        );
      },
    );
  }
}
