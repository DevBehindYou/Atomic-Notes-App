import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:flutter/material.dart';

/// A settings entry as a small card: an Ink icon block, the name, and one line
/// of mono status. Two sit side by side; a [wide] card takes the full row.
///
/// Same vocabulary as the Cloud Notes card in Cloud Sync, so entries read as
/// one family wherever they appear.
class SettingsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback onTap;

  /// Red variant for the destructive entry.
  final bool danger;

  /// Icon, text and arrow in one row instead of stacked.
  final bool wide;

  const SettingsCard({
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
    this.danger = false,
    this.wide = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final Color block = danger ? AppColors.error : AppColors.ink;
    final Widget iconBlock = Container(
      height: 40,
      width: 40,
      decoration: BoxDecoration(color: block, borderRadius: AppRadius.std),
      child: Icon(icon, color: Colors.white, size: 21),
    );
    final Widget arrow = Icon(Icons.arrow_forward,
        size: 16, color: danger ? AppColors.error : AppColors.signal);
    final Widget label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        EditorialHeading(title, style: AppType.headlineSm, maxLines: 1),
        const SizedBox(height: 2),
        MonoLabel(
          caption,
          small: true,
          color: danger ? AppColors.onErrorContainer : null,
        ),
      ],
    );

    return Semantics(
      button: true,
      label: '$title. $caption',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: EditorialModule(
          fill: danger ? AppColors.errorContainer : null,
          padding: const EdgeInsets.all(AppSpace.md - 2),
          child: wide
              ? Row(
                  children: [
                    iconBlock,
                    const SizedBox(width: AppSpace.md),
                    Expanded(child: label),
                    const SizedBox(width: AppSpace.sm),
                    arrow,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [iconBlock, arrow],
                    ),
                    const SizedBox(height: AppSpace.md),
                    label,
                  ],
                ),
        ),
      ),
    );
  }
}
