import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/authentication/auth_services/auth_service.dart';
import 'package:atomic_notes/profile/profile_store.dart';
import 'package:atomic_notes/security/two_factor.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/component/avatar_picker_dialog.dart';
import 'package:atomic_notes/utility/component/my_appbar.dart';
import 'package:atomic_notes/utility/component/my_snackbar.dart';
import 'package:atomic_notes/utility/component/profile_avatar.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Profile: the picture, the username, and the privacy and security choices.
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final String _email = ApiClient.instance.currentUserEmail ?? '';
  final TextEditingController _usernameController = TextEditingController();
  final AuthServices _serve = AuthServices();

  /// The username without the leading "@", or null until it has loaded.
  String? _username;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _loadUsername() async {
    final String name = await _serve.getUserInfo();
    if (!mounted) return;
    setState(() => _username = name.startsWith('@') ? name.substring(1) : name);
  }

  void _say(String text, [int ms = 2000]) {
    MySnackBar(text: text, sec: ms).showMySnackBar(context);
  }

  void _startEditing() {
    setState(() {
      _usernameController.text = _username ?? '';
      _editing = true;
    });
  }

  void _stopEditing() => setState(() => _editing = false);

  Future<void> _copyUsername() async {
    final String? name = _username;
    if (name == null) return;
    await Clipboard.setData(ClipboardData(text: name));
    if (!mounted) return;
    _say('Username copied', 1500);
  }

  Future<void> _save() async {
    if (_saving) return;

    final List<ConnectivityResult> link =
        await Connectivity().checkConnectivity();
    if (!mounted) return;
    if (link.contains(ConnectivityResult.none)) {
      _say('No Internet Connection!');
      return;
    }

    final String name = _usernameController.text.trim().toLowerCase();
    if (!_editing || name.isEmpty) {
      _say('Please enter your username');
      return;
    }

    setState(() => _saving = true);
    try {
      final String? response = await _serve.updateUserInfo(username: name);
      if (!mounted) return;
      _say(response.toString(), 1500);
      await _loadUsername();
    } catch (_) {
      if (!mounted) return;
      _say('Error occurred while updating user info');
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _editing = false;
    });
  }

  void _pickAvatar() {
    showDialog<void>(
      context: context,
      builder: (_) => const AvatarPickerDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: const MyAppBar(text: 'Profile'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.md, AppSpace.lg, AppSpace.md, AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _identity(),
            const SizedBox(height: AppSpace.lg),
            const SectionHeader('ACCOUNT'),
            const SizedBox(height: AppSpace.md),
            _account(),
            const SizedBox(height: AppSpace.lg),
            const SectionHeader('PRIVACY & SECURITY'),
            const SizedBox(height: AppSpace.md),
            _privacy(),
            const SizedBox(height: AppSpace.lg),
            InkActionButton(
              label: 'Save changes',
              loading: _saving,
              onTap: _save,
            ),
          ],
        ),
      ),
    );
  }

  // ---- identity -----------------------------------------------------------

  Widget _identity() {
    return Column(
      children: [
        Center(
          child: Semantics(
            button: true,
            label: 'Change profile photo',
            child: GestureDetector(
              onTap: _pickAvatar,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: 136,
                width: 136,
                child: Stack(
                  children: [
                    const Positioned(
                      left: 4,
                      top: 4,
                      child: ProfileAvatar(size: 128, frame: 4),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 38,
                        width: 38,
                        decoration: BoxDecoration(
                          color: AppColors.paper,
                          borderRadius: AppRadius.std,
                          border: Border.all(
                              color: AppColors.ink, width: AppStroke.hairline),
                        ),
                        child: const Icon(Icons.photo_camera_outlined,
                            size: 18, color: AppColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        EditorialHeading(
          _username ?? 'Loading…',
          style: AppType.headlineLg,
          align: TextAlign.center,
          maxLines: 1,
        ),
        const SizedBox(height: AppSpace.xs),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified, size: 16, color: AppColors.signal),
            SizedBox(width: AppSpace.xs + 2),
            MonoLabel('Verified via Google'),
          ],
        ),
      ],
    );
  }

  // ---- account ------------------------------------------------------------

  Widget _account() {
    return EditorialModule(
      fill: AppColors.surfaceLowest,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _Row(
            label: 'Username',
            onTap: _editing ? null : _startEditing,
            value: _editing
                ? TextField(
                    controller: _usernameController,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                    cursorColor: AppColors.signal,
                    style: AppType.bodyLg,
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: false,
                      hintText: 'Enter username',
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: AppColors.ink, width: AppStroke.rule),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: AppColors.signal, width: AppStroke.offset),
                      ),
                    ),
                  )
                : Text(_username ?? 'Loading…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.bodyMedium15),
            trailing: _editing
                ? _SquareIcon(
                    icon: Icons.close, label: 'Cancel', onTap: _stopEditing)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SquareIcon(
                        icon: Icons.content_copy_outlined,
                        label: 'Copy username',
                        onTap: _copyUsername,
                      ),
                      const SizedBox(width: AppSpace.sm),
                      const Icon(Icons.chevron_right,
                          size: 20, color: AppColors.outline),
                    ],
                  ),
          ),
          const HairRule(),
          _Row(
            label: 'Email',
            value: Text(_email.isEmpty ? '—' : _email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.bodyMedium15),
          ),
        ],
      ),
    );
  }

  // ---- privacy and security -----------------------------------------------

  Widget _privacy() {
    return AnimatedBuilder(
      animation: Listenable.merge([ProfileStore.instance, TwoFactor.instance]),
      builder: (context, _) {
        final bool armed = TwoFactor.instance.isArmed;
        return EditorialModule(
          fill: AppColors.surfaceLowest,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              // Shown for the look of the profile only: nothing else in the app
              // reads it.
              _Row(
                label: 'Public profile',
                value: const Text('Allow others to discover your profile',
                    style: AppType.bodySm),
                trailing: CupertinoSwitch(
                  value: ProfileStore.instance.publicProfile,
                  activeTrackColor: AppColors.signal,
                  onChanged: ProfileStore.instance.setPublicProfile,
                ),
              ),
              const HairRule(),
              _Row(
                label: 'Two-factor authentication',
                onTap: () => Navigator.pushNamed(context, '/twofactor'),
                value: Text(
                  armed ? 'Enabled' : 'Off',
                  style: armed
                      ? AppType.bodySm.copyWith(
                          color: AppColors.signal, fontWeight: FontWeight.w600)
                      : AppType.bodySm,
                ),
                trailing: const Icon(Icons.chevron_right,
                    size: 20, color: AppColors.outline),
              ),
              const HairRule(),
              // Google is the only sign-in there is; the row is informational.
              const _Row(
                label: 'Connected accounts',
                value: Text('Google', style: AppType.bodySm),
                trailing: DataChip('Connected',
                    active: true, activeColor: AppColors.signal),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One line of a settings module: a mono label over its value, with something
/// at the end. The whole row is tappable when [onTap] is set.
class _Row extends StatelessWidget {
  final String label;
  final Widget value;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _Row({
    required this.label,
    required this.value,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md, vertical: AppSpace.md - 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MonoLabel(label, small: true),
                  const SizedBox(height: AppSpace.xs),
                  value,
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpace.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A small square icon button, the copy affordance of the reference layout.
class _SquareIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SquareIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 36,
          width: 36,
          decoration: const BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: AppRadius.std,
          ),
          child: Icon(icon, size: 18, color: AppColors.ink),
        ),
      ),
    );
  }
}
