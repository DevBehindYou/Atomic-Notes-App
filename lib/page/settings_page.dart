// ignore_for_file: use_build_context_synchronously, prefer_final_fields, deprecated_member_use

import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/authentication/auth_services/auth_service.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/database/sync_status.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/utility/component/logo_container.dart';
import 'package:atomic_notes/utility/component/logout_dialogbox.dart';
import 'package:atomic_notes/utility/component/my_snackbar.dart';
import 'package:atomic_notes/utility/component/profile_container.dart';
import 'package:atomic_notes/utility/app_info.dart';
import 'package:atomic_notes/utility/component/settings_card.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive_ce.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _api = ApiClient.instance;
  late String? userId = _api.currentUserEmail;
  final AuthServices serve = AuthServices();
  final NotesRepository repo = NotesRepository.instance;
  bool _isLoading = false;
  String? username = "@atomicuser";
  bool _isMounted = true;

  @override
  void dispose() {
    _isMounted = false;
    _isLoading = false;
    super.dispose();
  }

  _showPopUp({required String txt, required Function func}) {
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (_) {
        return DialogBoxLogout(
          action: func,
          text: txt,
        );
      },
    );
  }

  //logout function
  Future<void> _logOut() async {
    if (!_isMounted) return;

    setState(() {
      _isLoading = true;
    });
    try {
      // Flush anything unpushed BEFORE wiping the local cache. Logout clears
      // the device copy, so an unsynced note would otherwise be gone for good.
      if (repo.pendingCount > 0) {
        if (!SyncStatusHelper.isSyncOn) {
          // Don't push their notes to a cloud they explicitly opted out of —
          // but don't erase them either. Refusing with an actionable message
          // is the only option here that can't lose data.
          if (!_isMounted) return;
          const MySnackBar(
            text: "Turn on Cloud Sync and sync first — "
                "logging out erases the notes on this device",
            sec: 4000,
          ).showMySnackBar(context);
          return;
        }
        final synced = await repo.syncNow();
        if (!synced) {
          if (!_isMounted) return;
          final next = repo.nextAutoSyncAt;
          MySnackBar(
            text: next != null
                ? "Logout cancelled — your changes are not sent yet. Automatic "
                    "sync opens again in ${(next.difference(DateTime.now()).inSeconds / 60).ceil().clamp(1, 60)} min. "
                    "To log out now, use Sync now in Cloud Notes first."
                : "Logout cancelled — your notes could not be backed up",
            sec: next != null ? 6000 : 3000,
          ).showMySnackBar(context);
          return;
        }
      }
      await repo.stop();
      await repo.clearLocal();
      final authBox = await Hive.openBox<bool>('authBox');
      await authBox.put('isAuthOn', false);
      await SyncStatusHelper.setSyncStatus(true);
      // Wipe the encryption key from this device before the session ends.
      await Vault.instance.clearLocal();
      // End the session. Logout must never be blocked by the network: if the
      // server can't be reached, still sign out locally so the app cannot stay
      // authenticated. ApiClient.signOut() already falls back to a local-only
      // clear if the revoke call fails, and fires the same signal SessionGuard
      // reacts to either way — it's what tears down remaining state and resets
      // the stack to the login screen.
      await _api.signOut();
    } catch (error) {
      if (!_isMounted) return;
      const MySnackBar(
        text: "Unable to logout",
        sec: 2000,
      ).showMySnackBar(context);
    } finally {
      if (_isMounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Two cards side by side, the same height however much text each holds.
  Widget _cardRow(Widget left, Widget right) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm + 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            const SizedBox(width: AppSpace.sm + 4),
            Expanded(child: right),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const EditorialHeading('Settings', style: AppType.headlineLg),
            const SizedBox(height: AppSpace.xs),
            // The signed-in address, as mono metadata rather than a pill.
            MonoLabel(userId ?? '—'),
            const SizedBox(height: AppSpace.md),
            const HairRule(color: AppColors.ink),
            const SizedBox(height: AppSpace.md),

            // logout button section
            ProConatainer(
              isLoading: _isLoading,
              logout: () => _showPopUp(
                  txt:
                      "Are you sure you want to log out? Before you log out, make sure to backup or sync your notes data to the cloud by tapping on cloud sync button",
                  func: _logOut),
            ),
            const SizedBox(height: AppSpace.lg),
            const SectionHeader('MANAGE'),

            const SizedBox(height: AppSpace.md),
            AnimatedBuilder(
              animation: repo,
              builder: (context, _) {
                final int binned = repo.binNotes.length;
                return Column(
                  children: [
                    _cardRow(
                      SettingsCard(
                        icon: Icons.person_outline,
                        title: 'Profile',
                        caption: 'Photo, name, 2FA',
                        onTap: () =>
                            Navigator.pushNamed(context, '/editprofilepage'),
                      ),
                      SettingsCard(
                        icon: Icons.cloud_sync_outlined,
                        title: 'Cloud Sync',
                        caption: 'Drive backup',
                        onTap: () =>
                            Navigator.pushNamed(context, '/cloudsyncpage'),
                      ),
                    ),
                    _cardRow(
                      SettingsCard(
                        icon: Icons.delete_outline,
                        title: 'Recycle Bin',
                        caption: binned == 0 ? 'Empty' : '$binned deleted',
                        onTap: () =>
                            Navigator.pushNamed(context, '/recyclebin'),
                      ),
                      SettingsCard(
                        icon: Icons.lock_outline,
                        title: 'Security',
                        caption: 'Lock, screenshots',
                        onTap: () =>
                            Navigator.pushNamed(context, '/biompage'),
                      ),
                    ),
                    _cardRow(
                      SettingsCard(
                        icon: Icons.enhanced_encryption_outlined,
                        title: 'Encryption',
                        caption: 'End-to-end',
                        onTap: () =>
                            Navigator.pushNamed(context, '/encryptionpage'),
                      ),
                      SettingsCard(
                        icon: Icons.bolt_outlined,
                        title: 'Atomic Energy',
                        caption: 'Coins, quota',
                        onTap: () =>
                            Navigator.pushNamed(context, '/energypage'),
                      ),
                    ),
                    // The destructive entry stands apart, on its own row.
                    SettingsCard(
                      icon: Icons.warning_amber_rounded,
                      title: 'Danger Zone',
                      caption: 'Wipe cloud or this device',
                      danger: true,
                      wide: true,
                      onTap: () =>
                          Navigator.pushNamed(context, '/dangerzone'),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpace.xl),

            //logo section
            const LogoContainer(),
            const SizedBox(height: AppSpace.xl),

            // Colophon: inverted module, the system's way of closing a page.
            EditorialModule(
              inverted: true,
              padding: const EdgeInsets.all(AppSpace.md + 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const MonoLabel('ABOUT ATOMIC', color: AppColors.signal),
                  const SizedBox(height: AppSpace.sm),
                  EditorialHeading(
                    'Local-first notes',
                    style: AppType.headlineMd.copyWith(color: AppColors.paper),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    AppInfoText.versionLabel,
                    style: AppType.labelMonoSm
                        .copyWith(color: AppColors.outlineVariant),
                  ),
                  Text(
                    AppInfoText.copyright,
                    style: AppType.labelMonoSm
                        .copyWith(color: AppColors.outlineVariant),
                  ),
                  const SizedBox(height: AppSpace.md),
                  ArrowLink(
                    'App info',
                    onTap: () => Navigator.pushNamed(context, '/appinfo'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
          ],
        ),
      ),
    );
  }
}
