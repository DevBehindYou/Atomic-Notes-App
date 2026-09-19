import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/component/logout_dialogbox.dart';
import 'package:atomic_notes/utility/component/my_appbar.dart';
import 'package:atomic_notes/utility/component/my_snackbar.dart';
import 'package:atomic_notes/utility/component/slide_confirm_dialog.dart';
import 'package:flutter/material.dart';

/// Recycle Bin: notes that were deleted on a device, waiting to be restored or
/// removed for good.
///
/// Deleting a note never destroys it at once. Its content stays here, and its
/// cloud file sits in the Google Drive trash, until it is deleted forever.
class RecycleBinPage extends StatefulWidget {
  const RecycleBinPage({super.key});

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  final NotesRepository repo = NotesRepository.instance;

  static String _stamp(DateTime d) {
    final l = d.toLocal();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${p(l.month)}-${p(l.day)} ${p(l.hour)}:${p(l.minute)}';
  }

  Future<void> _restore(Note note) async {
    if (repo.isAtLimit) {
      MySnackBar(
        text: 'Note limit reached (${repo.limit}). Delete a note to make room.',
        sec: 3000,
      ).showMySnackBar(context);
      return;
    }
    final bool ok = await repo.restoreNote(note.id);
    if (!mounted) return;
    MySnackBar(
      text: ok ? 'Note restored' : 'Could not restore this note',
      sec: 2000,
    ).showMySnackBar(context);
  }

  void _deleteForever(Note note) {
    final String name = note.title.trim().isEmpty ? 'this note' : '"${note.title.trim()}"';
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DialogBoxLogout(
        text: 'Delete $name for good? It is removed from this device. '
            'Its cloud copy stays in your Google Drive trash until Drive '
            'empties it.',
        action: () async {
          final int removed = await repo.deleteForever([note.id]);
          if (!mounted) return;
          MySnackBar(
            text: removed > 0
                ? 'Deleted for good'
                : 'Could not delete yet. Turn on Cloud Sync and sync first.',
            sec: 3000,
          ).showMySnackBar(context);
        },
      ),
    );
  }

  void _emptyBin(int count) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => SlideConfirmDialog(
        title: 'Empty the Recycle Bin',
        slideLabel: 'empty bin',
        consequences: [
          count == 1
              ? '1 deleted note is removed from this device for good.'
              : '$count deleted notes are removed from this device for good.',
          'Their cloud copies stay in your Google Drive trash until Drive '
              'empties it.',
        ],
        onConfirmed: () async {
          final int removed =
              await repo.deleteForever(repo.binNotes.map((n) => n.id).toList());
          if (dialogContext.mounted) Navigator.pop(dialogContext);
          if (mounted) {
            MySnackBar(
              text: removed > 0
                  ? 'Recycle Bin emptied'
                  : 'Could not empty the bin yet. Turn on Cloud Sync and sync first.',
              sec: 3000,
            ).showMySnackBar(context);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: const MyAppBar(text: 'Recycle Bin'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.md, AppSpace.lg, AppSpace.md, AppSpace.xl),
        child: AnimatedBuilder(
          animation: repo,
          builder: (context, _) {
            final List<Note> items = repo.binNotes;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  'DELETED NOTES',
                  trailing: DataChip(
                    '${items.length}',
                    active: items.isNotEmpty,
                    activeColor: AppColors.ink,
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                const Text(
                  'Deleted notes wait here. Restore one to put it back, or '
                  'delete it for good. Their cloud copies sit in your Google '
                  'Drive trash meanwhile.',
                  style: AppType.bodySm,
                ),
                const SizedBox(height: AppSpace.md),
                if (items.isEmpty)
                  const EditorialModule(
                    padding: EdgeInsets.all(AppSpace.lg),
                    child: Column(
                      children: [
                        Icon(Icons.delete_outline,
                            size: 32, color: AppColors.outline),
                        SizedBox(height: AppSpace.sm),
                        EditorialHeading('Bin is empty',
                            style: AppType.headlineSm),
                        SizedBox(height: AppSpace.xs),
                        Text(
                          'Notes you delete land here first.',
                          textAlign: TextAlign.center,
                          style: AppType.bodySm,
                        ),
                      ],
                    ),
                  )
                else ...[
                  for (final note in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: _BinCard(
                        note: note,
                        deletedAt: _stamp(note.updatedAt),
                        onRestore: () => _restore(note),
                        onDeleteForever: () => _deleteForever(note),
                      ),
                    ),
                  const SizedBox(height: AppSpace.md),
                  InkActionButton(
                    label: 'Empty bin',
                    icon: Icons.delete_forever_outlined,
                    danger: true,
                    onTap: () => _emptyBin(items.length),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One deleted note: what it was, when it was deleted, and the two things
/// that can happen to it.
class _BinCard extends StatelessWidget {
  final Note note;
  final String deletedAt;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;

  const _BinCard({
    required this.note,
    required this.deletedAt,
    required this.onRestore,
    required this.onDeleteForever,
  });

  @override
  Widget build(BuildContext context) {
    final String title = note.title.trim().isEmpty ? 'Untitled' : note.title.trim();
    final String preview = note.preview.trim();
    return EditorialModule(
      fill: AppColors.surfaceLowest,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DataChip(note.kind == NoteKind.todo ? 'Checklist' : 'Note'),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: MonoLabel('Deleted $deletedAt', small: true),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          EditorialHeading(title, style: AppType.headlineSm, maxLines: 1),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.bodySm,
            ),
          ],
          const SizedBox(height: AppSpace.md),
          const HairRule(),
          const SizedBox(height: AppSpace.sm + 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ArrowLink('Restore', onTap: onRestore),
              ArrowLink('Delete forever',
                  color: AppColors.error, onTap: onDeleteForever),
            ],
          ),
        ],
      ),
    );
  }
}
