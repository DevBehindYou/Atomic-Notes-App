import 'dart:async';

import 'package:atomic_notes/security/two_factor.dart';
import 'package:atomic_notes/security/vault.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/component/logo_container.dart';
import 'package:atomic_notes/utility/component/logout_dialogbox.dart';
import 'package:atomic_notes/utility/component/two_factor_code_field.dart';
import 'package:flutter/material.dart';

/// The second step when Atomic opens: the 6-digit code from the authenticator
/// app, or a recovery code. Shown after the device lock and before the notes.
class TwoFactorGatePage extends StatefulWidget {
  /// Only tests pass one; the app uses [TwoFactor.instance].
  final TwoFactor? twoFactor;

  const TwoFactorGatePage({this.twoFactor, super.key});

  @override
  State<TwoFactorGatePage> createState() => _TwoFactorGatePageState();
}

class _TwoFactorGatePageState extends State<TwoFactorGatePage> {
  late final TwoFactor _tf = widget.twoFactor ?? TwoFactor.instance;
  final TextEditingController _controller = TextEditingController();

  bool _probing = true;
  bool _unavailable = false;
  bool _recovery = false;
  bool _busy = false;
  String? _error;

  Timer? _ticker;
  DateTime? _lockEnds;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    setState(() => _probing = true);
    final bool readable = await _tf.hasVerificationData();
    if (!mounted) return;
    setState(() {
      _probing = false;
      _unavailable = !readable;
    });
  }

  Future<void> _submit([String? typed]) async {
    if (_busy || _lockLeft > 0) return;
    final String text = (typed ?? _controller.text).trim();
    if (text.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final TwoFactorCheck check = await _tf.check(text);
    if (!mounted) return;

    switch (check.result) {
      case TwoFactorResult.ok:
        _enter();
      case TwoFactorResult.wrong:
        _controller.clear();
        setState(() {
          _busy = false;
          _error = _recovery
              ? "That recovery code didn't match."
              : "That code didn't match. Wait for a fresh one and try again.";
        });
      case TwoFactorResult.locked:
        _controller.clear();
        setState(() => _busy = false);
        _startLock(check.retryAfter ?? const Duration(seconds: 30));
      case TwoFactorResult.unavailable:
        setState(() {
          _busy = false;
          _unavailable = true;
        });
    }
  }

  void _startLock(Duration wait) {
    _lockEnds = DateTime.now().add(wait);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_lockLeft <= 0) timer.cancel();
      setState(() {});
    });
    setState(() {});
  }

  /// Whole seconds left on a lock, or 0.
  int get _lockLeft {
    final DateTime? ends = _lockEnds;
    if (ends == null) return 0;
    final int ms = ends.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  void _enter() {
    // The device lock and this check have both passed. If the vault is still
    // sealed on this device, ask for the recovery phrase before the notes.
    if (Vault.instance.isLocked) {
      Navigator.pushReplacementNamed(context, '/vaultunlock', arguments: true);
    } else {
      Navigator.pushReplacementNamed(context, '/mainpage');
    }
  }

  Future<void> _turnOffHere() async {
    bool done = false;
    await showDialog<void>(
      context: context,
      builder: (_) => DialogBoxLogout(
        text: 'This device can no longer read its two-factor key, so no code '
            'can be checked. Turn two-factor off on this device? Your device '
            'lock and Google sign-in stay as they are. You can set it up again '
            'in Profile.',
        action: () async {
          await _tf.resetOnThisDevice();
          done = true;
        },
      ),
    );
    if (done && mounted) _enter();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.screenMargin),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.sizeOf(context).height -
                  MediaQuery.paddingOf(context).vertical -
                  AppSpace.screenMargin * 2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpace.xl),
                const LogoContainer(showTagline: false),
                const SizedBox(height: AppSpace.xl),
                const MonoLabel('TWO-FACTOR', color: AppColors.signal),
                const SizedBox(height: AppSpace.sm),
                const HairRule(color: AppColors.ink),
                const SizedBox(height: AppSpace.lg),
                const EditorialHeading('Enter your\ncode.',
                    style: AppType.displayLg),
                const SizedBox(height: AppSpace.sm),
                if (_probing)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpace.lg),
                    child: Center(
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.signal),
                      ),
                    ),
                  )
                else if (_unavailable)
                  ..._unavailableBody()
                else
                  ..._entryBody(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _entryBody() {
    final int locked = _lockLeft;
    return [
      Text(
        _recovery
            ? 'Type one of the recovery codes you saved. Each works once.'
            : 'Open your authenticator app and type the 6-digit code for '
                'Atomic Notes.',
        style: AppType.bodyMd.copyWith(color: AppColors.slateData),
      ),
      const SizedBox(height: AppSpace.lg),
      TwoFactorCodeField(
        key: ValueKey(_recovery),
        controller: _controller,
        recovery: _recovery,
        enabled: !_busy && locked == 0,
        autofocus: true,
        onCompleted: _submit,
        onSubmitted: _submit,
      ),
      if (locked > 0) ...[
        const SizedBox(height: AppSpace.md),
        EditorialModule(
          fill: AppColors.errorContainer,
          padding: const EdgeInsets.all(AppSpace.md),
          child: Text(
            'Too many wrong tries. Try again in $locked s.',
            style: AppType.bodySm.copyWith(color: AppColors.onErrorContainer),
          ),
        ),
      ] else if (_error != null) ...[
        const SizedBox(height: AppSpace.md),
        Text(_error!, style: AppType.bodySm.copyWith(color: AppColors.error)),
      ],
      const SizedBox(height: AppSpace.lg),
      InkActionButton(
        label: 'Verify',
        loading: _busy,
        signal: true,
        onTap: locked > 0 ? null : _submit,
      ),
      const SizedBox(height: AppSpace.md),
      Center(
        child: ArrowLink(
          _recovery ? 'Use authenticator code' : 'Use a recovery code',
          onTap: _busy
              ? null
              : () => setState(() {
                    _recovery = !_recovery;
                    _error = null;
                    _controller.clear();
                  }),
        ),
      ),
    ];
  }

  List<Widget> _unavailableBody() {
    return [
      const SizedBox(height: AppSpace.md),
      EditorialModule(
        fill: AppColors.errorContainer,
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MonoLabel('KEY UNAVAILABLE', color: AppColors.onErrorContainer),
            const SizedBox(height: AppSpace.sm),
            Text(
              "This device can't read its two-factor key. That can happen "
              'after a restore from backup or a system reset.',
              style: AppType.bodySm.copyWith(color: AppColors.onErrorContainer),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpace.lg),
      InkActionButton(label: 'Try again', onTap: _probe),
      const SizedBox(height: AppSpace.sm + 2),
      GhostButton(label: 'Turn off on this device', onTap: _turnOffHere),
    ];
  }
}
