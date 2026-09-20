import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/component/slide_to_confirm.dart';
import 'package:flutter/material.dart';

/// A confirmation popup for destructive actions. Nothing runs until the slide is completed.
class SlideConfirmDialog extends StatelessWidget {
  final String title;
  final String slideLabel;
  final List<String> consequences;
  final String? warning;
  final Future<void> Function() onConfirmed;

  const SlideConfirmDialog({
    required this.title,
    required this.slideLabel,
    required this.consequences,
    required this.onConfirmed,
    this.warning,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.std,
        side: BorderSide(color: AppColors.error, width: AppStroke.hairline),
      ),
      insetPadding: const EdgeInsets.all(AppSpace.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MonoLabel('Final confirmation', color: AppColors.error),
              const SizedBox(height: AppSpace.sm),
              const HairRule(color: AppColors.error),
              const SizedBox(height: AppSpace.md),
              EditorialHeading(title, style: AppType.headlineMd),
              const SizedBox(height: AppSpace.md),
              for (final line in consequences)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(Icons.chevron_right,
                            size: 16, color: AppColors.error),
                      ),
                      const SizedBox(width: AppSpace.xs),
                      Expanded(child: Text(line, style: AppType.bodySm)),
                    ],
                  ),
                ),
              if (warning != null) ...[
                const SizedBox(height: AppSpace.xs),
                EditorialModule(
                  fill: AppColors.errorContainer,
                  padding: const EdgeInsets.all(AppSpace.md - 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MonoLabel('Not uploaded',
                          small: true, color: AppColors.onErrorContainer),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        warning!,
                        style: AppType.bodySm
                            .copyWith(color: AppColors.onErrorContainer),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.lg),
              SlideToConfirm(label: slideLabel, onConfirmed: onConfirmed),
              const SizedBox(height: AppSpace.md),
              GhostButton(
                label: 'Cancel',
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
