import 'package:atomic_notes/security/two_factor.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/component/my_appbar.dart';
import 'package:atomic_notes/utility/component/my_snackbar.dart';
import 'package:atomic_notes/utility/component/two_factor_code_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

enum _Stage { overview, setup, codes }

/// Turn two-factor on or off, and manage its recovery codes.
class TwoFactorPage extends StatefulWidget {
  /// Only tests pass one; the app uses [TwoFactor.instance].
  final TwoFactor? twoFactor;

  const TwoFactorPage({this.twoFactor, super.key});

  @override
  State<TwoFactorPage> createState() => _TwoFactorPageState();
}

class _TwoFactorPageState extends State<TwoFactorPage> {
  late final TwoFactor _tf = widget.twoFactor ?? TwoFactor.instance;
  final TextEditingController _code = TextEditingController();

  _Stage _stage = _Stage.overview;
  TwoFactorSetup? _setup;
  List<String> _codes = const [];
  bool _saved = false;
  bool _busy = false;
  String? _error;
  int? _codesLeft;

  @override
  void initState() {
    super.initState();
    _refreshCount();
  }

  @override
  void dispose() {
    // Leaving mid-setup discards the key: nothing was stored yet.
    _tf.cancelSetup();
    _code.dispose();
    super.dispose();
  }

  Future<void> _refreshCount() async {
    final int? left = await _tf.recoveryCodesLeft();
    if (!mounted) return;
    setState(() => _codesLeft = left);
  }

  void _say(String text) {
    MySnackBar(text: text, sec: 2500).showMySnackBar(context);
  }

  void _begin() {
    setState(() {
      _setup = _tf.beginSetup();
      _stage = _Stage.setup;
      _error = null;
      _code.clear();
    });
  }

  void _cancelSetup() {
    _tf.cancelSetup();
    setState(() {
      _setup = null;
      _stage = _Stage.overview;
      _error = null;
      _code.clear();
    });
  }

  Future<void> _confirm([String? typed]) async {
    if (_busy) return;
    final String text = (typed ?? _code.text).trim();
    if (text.length != 6) {
      setState(() => _error = 'Type the 6-digit code from your app.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final List<String>? codes = await _tf.confirmSetup(text);
    if (!mounted) return;
    if (codes == null) {
      _code.clear();
      setState(() {
        _busy = false;
        _error = "That code didn't match. Check that your app shows "
            'Atomic Notes and try the next code.';
      });
      return;
    }
    setState(() {
      _busy = false;
      _codes = codes;
      _saved = false;
      _stage = _Stage.codes;
      _setup = null;
    });
    _code.clear();
    _refreshCount();
  }

  Future<void> _copy(String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _say(done);
  }

  Future<void> _newCodes() async {
    final TwoFactorCheck? result = await showDialog<TwoFactorCheck>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CodePromptDialog(
        title: 'New recovery codes',
        body: 'Type a code from your authenticator app. The old recovery '
            'codes stop working.',
        confirmLabel: 'Make new codes',
        submit: _tf.regenerateRecoveryCodes,
      ),
    );
    if (!mounted || result == null || !result.ok || result.codes == null) {
      return;
    }
    setState(() {
      _codes = result.codes!;
      _saved = false;
      _stage = _Stage.codes;
    });
    _refreshCount();
  }

  Future<void> _turnOff() async {
    final TwoFactorCheck? result = await showDialog<TwoFactorCheck>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CodePromptDialog(
        title: 'Turn off two-factor',
        body: 'Type a code from your authenticator app, or a recovery code, '
            'to turn it off.',
        confirmLabel: 'Turn off',
        danger: true,
        submit: _tf.disable,
      ),
    );
    if (!mounted || result == null || !result.ok) return;
    setState(() => _codesLeft = null);
    _say('Two-factor is off');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: const MyAppBar(text: 'Two-factor'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.md, AppSpace.lg, AppSpace.md, AppSpace.xl),
        child: AnimatedBuilder(
          animation: _tf,
          builder: (context, _) {
            return switch (_stage) {
              _Stage.setup => _setupView(),
              _Stage.codes => _codesView(),
              _Stage.overview =>
                _tf.isArmed ? _armedView() : _offView(),
            };
          },
        ),
      ),
    );
  }

  // ---- off ----------------------------------------------------------------

  Widget _offView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          'TWO-FACTOR',
          trailing: DataChip('OFF', active: true, activeColor: AppColors.outline),
        ),
        const SizedBox(height: AppSpace.md),
        const EditorialModule(
          padding: EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EditorialHeading('A second step to open Atomic',
                  style: AppType.headlineSm),
              SizedBox(height: AppSpace.xs),
              Text(
                'After your device lock, Atomic asks for a 6-digit code from '
                'an authenticator app. It works with Google Authenticator, '
                'Authy, Aegis, 1Password and any app that reads a QR code for '
                'time-based codes.',
                style: AppType.bodySm,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        EditorialModule(
          fill: AppColors.surfaceLow,
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MonoLabel('GOOD TO KNOW'),
              const SizedBox(height: AppSpace.sm),
              _bullet('It protects this device. The key is kept in its secure '
                  'storage and does not move to other devices.'),
              _bullet('You get ${TwoFactor.recoveryCodeCount} recovery codes. '
                  'Keep them somewhere safe: they are your way in if you lose '
                  'the authenticator.'),
              _bullet('Signing in with Google is protected by your Google '
                  "account's own two-step verification."),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        InkActionButton(
          label: 'Set up two-factor',
          icon: Icons.shield_outlined,
          onTap: _begin,
        ),
      ],
    );
  }

  // ---- on -----------------------------------------------------------------

  Widget _armedView() {
    final int? left = _codesLeft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          'TWO-FACTOR',
          trailing:
              DataChip('ARMED', active: true, activeColor: AppColors.signal),
        ),
        const SizedBox(height: AppSpace.md),
        EditorialModule(
          accent: true,
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EditorialHeading('Two-factor is on',
                  style: AppType.headlineSm),
              const SizedBox(height: AppSpace.xs),
              const Text(
                'Atomic asks for a code from your authenticator app each time '
                'it opens.',
                style: AppType.bodySm,
              ),
              const SizedBox(height: AppSpace.md),
              const HairRule(),
              const SizedBox(height: AppSpace.sm + 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const MonoLabel('Recovery codes left', small: true),
                  Text(left == null ? '–' : '$left', style: AppType.statNumber),
                ],
              ),
            ],
          ),
        ),
        if (left != null && left <= 2) ...[
          const SizedBox(height: AppSpace.md),
          EditorialModule(
            fill: AppColors.errorContainer,
            padding: const EdgeInsets.all(AppSpace.md),
            child: Text(
              left == 0
                  ? 'You have no recovery codes left. Make new ones so you '
                      'are not locked out if you lose your authenticator.'
                  : 'Only $left recovery ${left == 1 ? 'code is' : 'codes are'} '
                      'left. Consider making new ones.',
              style: AppType.bodySm.copyWith(color: AppColors.onErrorContainer),
            ),
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        GhostButton(
          label: 'New recovery codes',
          icon: Icons.key_outlined,
          onTap: _newCodes,
        ),
        const SizedBox(height: AppSpace.md),
        InkActionButton(
          label: 'Turn off two-factor',
          danger: true,
          onTap: _turnOff,
        ),
      ],
    );
  }

  // ---- setup --------------------------------------------------------------

  Widget _setupView() {
    final TwoFactorSetup setup = _setup!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('STEP 1 · ADD TO YOUR APP'),
        const SizedBox(height: AppSpace.md),
        const Text(
          'In your authenticator app, add a new account. Scan this code with '
          'another device, or choose "enter a setup key" and type the key '
          'below.',
          style: AppType.bodySm,
        ),
        const SizedBox(height: AppSpace.md),
        Center(
          child: Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppRadius.std,
              border: Border.all(
                  color: AppColors.ink, width: AppStroke.hairline),
            ),
            child: QrImageView(
              data: setup.uri,
              size: 192,
              backgroundColor: Colors.white,
              semanticsLabel: 'Two-factor setup QR code',
              eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square, color: AppColors.ink),
              dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppColors.ink),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        EditorialModule(
          fill: AppColors.surfaceLowest,
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MonoLabel('Setup key', small: true),
              const SizedBox(height: AppSpace.xs),
              SelectableText(
                _grouped(setup.secret),
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  height: 1.6,
                  letterSpacing: 1.2,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              ArrowLink('Copy key',
                  onTap: () => _copy(setup.secret, 'Setup key copied')),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        const SectionHeader('STEP 2 · CONFIRM'),
        const SizedBox(height: AppSpace.md),
        const Text(
          'Type the 6-digit code your app now shows for Atomic Notes.',
          style: AppType.bodySm,
        ),
        const SizedBox(height: AppSpace.md),
        TwoFactorCodeField(
          controller: _code,
          enabled: !_busy,
          onCompleted: _confirm,
          onSubmitted: _confirm,
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpace.sm),
          Text(_error!,
              style: AppType.bodySm.copyWith(color: AppColors.error)),
        ],
        const SizedBox(height: AppSpace.lg),
        InkActionButton(
          label: 'Verify and turn on',
          signal: true,
          loading: _busy,
          onTap: _confirm,
        ),
        const SizedBox(height: AppSpace.md),
        Center(child: ArrowLink('Cancel', onTap: _cancelSetup)),
      ],
    );
  }

  // ---- recovery codes -----------------------------------------------------

  Widget _codesView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          'RECOVERY CODES',
          trailing:
              DataChip('SHOWN ONCE', active: true, activeColor: AppColors.error),
        ),
        const SizedBox(height: AppSpace.md),
        const EditorialHeading('Save these now.', style: AppType.headlineMd),
        const SizedBox(height: AppSpace.xs),
        const Text(
          'If you lose your authenticator, each code opens Atomic once. They '
          'are not stored in a readable form, so this is the only time you '
          'will see them.',
          style: AppType.bodySm,
        ),
        const SizedBox(height: AppSpace.md),
        EditorialModule(
          inverted: true,
          padding: const EdgeInsets.all(AppSpace.md),
          child: Wrap(
            runSpacing: AppSpace.sm + 2,
            children: [
              for (final code in _codes)
                FractionallySizedBox(
                  widthFactor: 0.5,
                  child: SelectableText(
                    code,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.4,
                      color: AppColors.onInk,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        GhostButton(
          label: 'Copy all codes',
          icon: Icons.copy_all_outlined,
          onTap: () => _copy(_codes.join('\n'), 'Recovery codes copied'),
        ),
        const SizedBox(height: AppSpace.md),
        GestureDetector(
          onTap: () => setState(() => _saved = !_saved),
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Container(
                height: 22,
                width: 22,
                decoration: BoxDecoration(
                  color: _saved ? AppColors.signal : Colors.transparent,
                  borderRadius: AppRadius.sm,
                  border: Border.all(
                      color: _saved ? AppColors.signal : AppColors.ink,
                      width: AppStroke.hairline),
                ),
                child: _saved
                    ? const Icon(Icons.check, size: 15, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: AppSpace.sm + 2),
              const Expanded(
                child: Text('I saved these codes somewhere safe',
                    style: AppType.bodyMd),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        InkActionButton(
          label: 'Done',
          signal: true,
          onTap: _saved
              ? () => setState(() {
                    _codes = const [];
                    _stage = _Stage.overview;
                  })
              : null,
        ),
      ],
    );
  }

  // ---- bits ---------------------------------------------------------------

  static Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7, right: AppSpace.sm),
            child: SizedBox(
              height: 5,
              width: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(color: AppColors.ink),
              ),
            ),
          ),
          Expanded(child: Text(text, style: AppType.bodySm)),
        ],
      ),
    );
  }

  /// The key in groups of four, easier to read against an app.
  static String _grouped(String secret) {
    final parts = <String>[];
    for (int i = 0; i < secret.length; i += 4) {
      parts.add(secret.substring(i, i + 4 > secret.length ? secret.length : i + 4));
    }
    return parts.join(' ');
  }
}

/// Asks for a code, runs [submit] with it, and pops the result once it is ok.
class _CodePromptDialog extends StatefulWidget {
  final String title;
  final String body;
  final String confirmLabel;
  final bool danger;
  final Future<TwoFactorCheck> Function(String) submit;

  const _CodePromptDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.submit,
    this.danger = false,
  });

  @override
  State<_CodePromptDialog> createState() => _CodePromptDialogState();
}

class _CodePromptDialogState extends State<_CodePromptDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _recovery = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _go([String? typed]) async {
    if (_busy) return;
    final String text = (typed ?? _controller.text).trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final TwoFactorCheck result = await widget.submit(text);
    if (!mounted) return;
    if (result.ok) {
      Navigator.pop(context, result);
      return;
    }
    _controller.clear();
    setState(() {
      _busy = false;
      _error = switch (result.result) {
        TwoFactorResult.locked =>
          'Too many wrong tries. Try again in ${result.retryAfter?.inSeconds ?? 30} s.',
        TwoFactorResult.unavailable =>
          "This device can't read its two-factor key.",
        _ => _recovery
            ? "That recovery code didn't match."
            : "That code didn't match. Wait for a fresh one and try again.",
      };
    });
  }

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MonoLabel('CONFIRM',
                  color: widget.danger ? AppColors.error : null),
              const SizedBox(height: AppSpace.sm),
              const HairRule(color: AppColors.ink),
              const SizedBox(height: AppSpace.md),
              EditorialHeading(widget.title, style: AppType.headlineSm),
              const SizedBox(height: AppSpace.xs),
              Text(widget.body, style: AppType.bodySm),
              const SizedBox(height: AppSpace.md),
              TwoFactorCodeField(
                key: ValueKey(_recovery),
                controller: _controller,
                recovery: _recovery,
                enabled: !_busy,
                autofocus: true,
                onCompleted: _go,
                onSubmitted: _go,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpace.sm),
                Text(_error!,
                    style: AppType.bodySm.copyWith(color: AppColors.error)),
              ],
              const SizedBox(height: AppSpace.sm + 2),
              Center(
                child: ArrowLink(
                  _recovery ? 'Use the authenticator code' : 'Use a recovery code',
                  onTap: _busy
                      ? null
                      : () => setState(() {
                            _recovery = !_recovery;
                            _error = null;
                            _controller.clear();
                          }),
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      label: 'Cancel',
                      onTap: _busy ? null : () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm + 2),
                  Expanded(
                    child: InkActionButton(
                      label: widget.confirmLabel,
                      danger: widget.danger,
                      loading: _busy,
                      onTap: _go,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
