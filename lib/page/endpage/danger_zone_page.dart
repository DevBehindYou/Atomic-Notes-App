import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/component/my_appbar.dart';
import 'package:atomic_notes/utility/component/my_snackbar.dart';
import 'package:atomic_notes/utility/component/slide_confirm_dialog.dart';
import 'package:flutter/material.dart';

/// Danger Zone: the two ways to destroy notes, each behind a slide-to-confirm.
///
/// The two are deliberately independent. Wiping the cloud never touches this
/// device, and wiping this device never touches the cloud.
class DangerZonePage extends StatefulWidget {
  const DangerZonePage({super.key});

  @override
  State<DangerZonePage> createState() => _DangerZonePageState();
}

class _DangerZonePageState extends State<DangerZonePage> {
  final NotesRepository repo = NotesRepository.instance;

  Future<WipeOutcome> _wipeCloud() => repo.wipeRemote();

  Future<WipeOutcome> _wipeLocal() async {
    final removed = await repo.wipeLocalNotes();
    return WipeOutcome(
      true,
      removed == 1
          ? 'Removed 1 note from this device. Cloud notes are untouched and download again on the next sync.'
          : 'Removed $removed notes from this device. Cloud notes are untouched and download again on the next sync.',
    );
  }

  void _confirm({
    required String title,
    required String slideLabel,
    required List<String> consequences,
    required Future<WipeOutcome> Function() run,
    String? warning,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => SlideConfirmDialog(
        title: title,
        slideLabel: slideLabel,
        consequences: consequences,
        warning: warning,
        onConfirmed: () async {
          final outcome = await run();
          if (dialogContext.mounted) Navigator.pop(dialogContext);
          if (mounted) {
            MySnackBar(text: outcome.message, sec: 4000).showMySnackBar(context);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: const MyAppBar(text: 'Danger Zone'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.md, AppSpace.lg, AppSpace.md, AppSpace.xl),
        child: AnimatedBuilder(
          animation: repo,
          builder: (context, _) {
            final int onDevice = repo.count;
            final int unsynced = repo.pendingCount;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _HazardStrip(),
                const SizedBox(height: AppSpace.md),
                const EditorialHeading('Two actions. No undo.',
                    style: AppType.headlineMd),
                const SizedBox(height: AppSpace.xs),
                const Text(
                  'Each one asks you to slide across a bar before it runs. '
                  'They are independent: one never touches the other.',
                  style: AppType.bodySm,
                ),
                const SizedBox(height: AppSpace.lg),
                _WipeCard(
                  scope: 'Cloud',
                  icon: Icons.cloud_off_outlined,
                  title: 'Wipe cloud notes',
                  removes:
                      'Every note stored in your Google Drive folder '
                      '"My-Atomic-Notes" (moved to your Drive trash) and the '
                      'note records held by the Atomic server.',
                  keeps: 'Every note on this device, your account, your '
                      'encryption setup and your energy.',
                  buttonLabel: 'Wipe cloud notes',
                  onTap: () => _confirm(
                    title: 'Wipe cloud notes',
                    slideLabel: 'wipe cloud',
                    consequences: const [
                      'All notes in your cloud storage are removed. Their '
                          'files move to your Google Drive trash.',
                      'Notes on this device are not touched.',
                      'To put them back in the cloud later, edit a note or '
                          'use "Upload all" in Cloud Notes.',
                    ],
                    run: _wipeCloud,
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                _WipeCard(
                  scope: 'This device',
                  icon: Icons.phone_android_outlined,
                  title: 'Wipe local notes',
                  removes: onDevice == 1
                      ? '1 note stored on this device.'
                      : '$onDevice notes stored on this device.',
                  keeps: 'Every note in the cloud, your account and your '
                      'settings. Cloud notes download again on the next sync.',
                  buttonLabel: 'Wipe local notes',
                  onTap: () => _confirm(
                    title: 'Wipe local notes',
                    slideLabel: 'wipe local',
                    consequences: [
                      onDevice == 1
                          ? '1 note is removed from this device.'
                          : '$onDevice notes are removed from this device.',
                      'Notes in the cloud are not touched and download again '
                          'on the next sync.',
                    ],
                    warning: unsynced > 0
                        ? (unsynced == 1
                            ? '1 note has not been uploaded yet. It exists only '
                                'on this device and will be lost for good.'
                            : '$unsynced notes have not been uploaded yet. They '
                                'exist only on this device and will be lost for '
                                'good.')
                        : null,
                    run: _wipeLocal,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One destructive action: what it removes, what it keeps, and the button
/// that opens the slide-to-confirm.
class _WipeCard extends StatelessWidget {
  final String scope;
  final IconData icon;
  final String title;
  final String removes;
  final String keeps;
  final String buttonLabel;
  final VoidCallback onTap;

  const _WipeCard({
    required this.scope,
    required this.icon,
    required this.title,
    required this.removes,
    required this.keeps,
    required this.buttonLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return EditorialModule(
      fill: AppColors.surfaceLowest,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: const BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: AppRadius.std,
                ),
                child: Icon(icon, color: AppColors.paper, size: 22),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MonoLabel(scope, color: AppColors.error),
                    const SizedBox(height: 2),
                    EditorialHeading(title, style: AppType.headlineSm),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          const HairRule(),
          const SizedBox(height: AppSpace.md),
          const MonoLabel('Removes', small: true, color: AppColors.error),
          const SizedBox(height: AppSpace.xs),
          Text(removes, style: AppType.bodySm),
          const SizedBox(height: AppSpace.md),
          const MonoLabel('Keeps', small: true),
          const SizedBox(height: AppSpace.xs),
          Text(keeps, style: AppType.bodySm),
          const SizedBox(height: AppSpace.md),
          InkActionButton(label: buttonLabel, danger: true, onTap: onTap),
        ],
      ),
    );
  }
}

/// A row of diagonal red bars: the universal "careful" marking, drawn in the
/// design system's own error colour.
class _HazardStrip extends StatelessWidget {
  const _HazardStrip();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 12,
      width: double.infinity,
      child: ClipRect(child: CustomPaint(painter: _HazardPainter())),
    );
  }
}

class _HazardPainter extends CustomPainter {
  const _HazardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.error;
    const double stripe = 12;
    for (double x = -size.height; x < size.width; x += stripe * 2) {
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + stripe, size.height)
        ..lineTo(x + stripe + size.height, 0)
        ..lineTo(x + size.height, 0)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
