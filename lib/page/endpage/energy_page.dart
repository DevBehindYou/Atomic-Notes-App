// ignore_for_file: use_build_context_synchronously

import 'package:atomic_notes/database/energy_models.dart';
import 'package:atomic_notes/database/energy_service.dart';
import 'package:atomic_notes/database/notes_repository.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/component/atomic_icon.dart';
import 'package:atomic_notes/utility/component/energy_bar.dart';
import 'package:atomic_notes/utility/component/logout_dialogbox.dart';
import 'package:atomic_notes/utility/component/my_appbar.dart';
import 'package:atomic_notes/utility/component/my_snackbar.dart';
import 'package:flutter/material.dart';

/// The dedicated Atomic Energy + Atomic Coins screen. Reads everything from
/// [EnergyService]; never computes a balance itself.
class EnergyPage extends StatefulWidget {
  const EnergyPage({super.key});

  @override
  State<EnergyPage> createState() => _EnergyPageState();
}

class _EnergyPageState extends State<EnergyPage> {
  final EnergyService energy = EnergyService.instance;

  /// How many activity rows are visible; "Load more" adds another page.
  static const int _pageSize = 7;
  int _shown = _pageSize;

  @override
  void initState() {
    super.initState();
    energy.refresh();
  }

  // ---- actions ----------------------------------------------------------

  Future<void> _convert() async {
    final maxCoins = energy.coins;
    if (maxCoins <= 0) {
      const MySnackBar(text: 'No Atomic Coins to convert yet.', sec: 2000)
          .showMySnackBar(context);
      return;
    }
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.paper,
      showDragHandle: true,
      builder: (ctx) => _ConvertSheet(
        maxCoins: maxCoins,
        energy: energy.energy,
        energyCap: energy.energyCap,
      ),
    );
    if (chosen == null || chosen <= 0) return;
    final err = await energy.convertCoins(chosen);
    if (!mounted) return;
    MySnackBar(
      text: err ??
          'Converted $chosen coin${chosen == 1 ? '' : 's'} to '
              '${chosen * EnergyService.coinToEnergy} energy.',
      sec: 2500,
    ).showMySnackBar(context);
  }

  Future<void> _raiseLimit() async {
    final l = energy.limits;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DialogBoxLogout(
        text: 'Spend ${l.noteLimitStepCostCoins} coins to raise your note limit '
            'from ${energy.noteLimit} to ${energy.nextNoteLimit}?',
        action: () async {
          final err = await energy.upgradeNoteLimit();
          if (!mounted) return;
          MySnackBar(
            text: err ?? 'You can now keep ${energy.noteLimit} notes.',
            sec: 3000,
          ).showMySnackBar(context);
        },
      ),
    );
  }

  void _needCoins() {
    MySnackBar(
      text: 'The next ${energy.limits.noteLimitStep} notes cost '
          '${energy.limits.noteLimitStepCostCoins} coins. You have ${energy.coins}.',
      sec: 3000,
    ).showMySnackBar(context);
  }

  void _buySoon() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.paper,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, 0, AppSpace.lg, AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MonoLabel('COIN STORE', color: AppColors.signal),
            const SizedBox(height: AppSpace.sm),
            const HairRule(color: AppColors.ink),
            const SizedBox(height: AppSpace.md),
            const EditorialHeading('Buying coins is\ncoming soon.',
                style: AppType.headlineLg),
            const SizedBox(height: AppSpace.sm),
            const Text(
              'Atomic Coin purchases need the payment backend (Lemon Squeezy '
              'and Razorpay), which is the next phase. Until it ships, coins '
              'are not sold in-app. The first pack is planned as 50 Atomic Coins '
              'for \$3.99. You can support the build on Patreon.',
              style: AppType.bodyMd,
            ),
            const SizedBox(height: AppSpace.lg),
            InkActionButton(
              label: 'Got it',
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  // ---- build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: const MyAppBar(text: "Atomic Energy"),
      body: AnimatedBuilder(
        animation: energy,
        builder: (context, _) {
          // Loading state (first load, nothing cached yet).
          if (energy.loading && !energy.hasLoaded) {
            return const Center(
              child: SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.signal),
              ),
            );
          }
          return RefreshIndicator(
            color: AppColors.signal,
            onRefresh: energy.refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.md, AppSpace.lg, AppSpace.md, AppSpace.xl),
              children: [
                _energyHero(),
                const SizedBox(height: AppSpace.sm),
                _coinsModule(),
                const SizedBox(height: AppSpace.sm),
                _capacityModule(),
                const SizedBox(height: AppSpace.md),
                GhostButton(
                  label: 'How Atomic Energy works',
                  icon: Icons.info_outline,
                  onTap: () => Navigator.pushNamed(context, '/energyintro'),
                ),
                const SizedBox(height: AppSpace.lg),
                _activity(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _energyHero() {
    return EditorialModule(
      inverted: true,
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MonoLabel('ATOMIC ENERGY', color: AppColors.signal),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      '${energy.energy}',
                      style: AppType.statNumber.copyWith(color: AppColors.paper),
                    ),
                    Text(
                      'of ${energy.energyCap} capacity',
                      style: AppType.labelMonoSm
                          .copyWith(color: AppColors.outlineVariant),
                    ),
                  ],
                ),
              ),
              const AtomicIcon('atom', size: 56, set: 'Icons-Without-label-2.5D'),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          EnergyBar(
            fraction: energy.wallet.energyFraction,
            height: 12,
            color: EnergyBar.colorFor(energy.energy),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            '+20 energy every 24h, up to 120. Automatic sync 5 (once an hour), '
            'instant sync 10. Local notes are always free.',
            style: AppType.bodySm.copyWith(color: AppColors.outlineVariant),
          ),
        ],
      ),
    );
  }

  Widget _coinsModule() {
    final noCoins = energy.coins <= 0;
    return EditorialModule(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AtomicIcon.coin(size: 34),
              const SizedBox(width: AppSpace.sm + 2),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MonoLabel('ATOMIC COINS'),
                    SizedBox(height: 2),
                    Text('1 coin = 40 energy', style: AppType.bodySm),
                  ],
                ),
              ),
              Text('${energy.coins}', style: AppType.statNumber),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          InkActionButton(
            label: 'Buy Atomic Coins',
            signal: true,
            icon: Icons.add,
            onTap: _buySoon,
          ),
          const SizedBox(height: AppSpace.sm),
          GhostButton(
            label: noCoins ? 'No coins to convert' : 'Convert coins to energy',
            icon: Icons.bolt,
            onTap: noCoins ? null : _convert,
          ),
        ],
      ),
    );
  }

  /// How many notes the account can hold, and the way to raise it with coins.
  Widget _capacityModule() {
    final l = energy.limits;
    final int used = NotesRepository.instance.count;
    final int limit = energy.noteLimit;
    final bool atCeiling = !energy.canRaiseNoteLimit;
    return EditorialModule(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                height: 34,
                width: 34,
                decoration: const BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: AppRadius.std,
                ),
                child: const Icon(Icons.sticky_note_2_outlined,
                    size: 18, color: AppColors.paper),
              ),
              const SizedBox(width: AppSpace.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MonoLabel('NOTE CAPACITY'),
                    const SizedBox(height: 2),
                    Text('$used of $limit notes used', style: AppType.bodySm),
                  ],
                ),
              ),
              Text('$limit', style: AppType.statNumber),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              for (int v = l.noteLimitFree; v <= l.noteLimitCeiling; v += l.noteLimitStep)
                Expanded(
                  child: Container(
                    key: ValueKey('capacity-$v'),
                    margin: EdgeInsets.only(
                        right: v + l.noteLimitStep <= l.noteLimitCeiling ? 4 : 0),
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: v <= limit ? AppColors.ink : Colors.transparent,
                      borderRadius: AppRadius.sm,
                      border: Border.all(
                          color: v <= limit ? AppColors.ink : AppColors.outlineVariant,
                          width: AppStroke.rule),
                    ),
                    child: Text(
                      '$v',
                      style: AppType.labelMonoSm.copyWith(
                          color: v <= limit ? AppColors.paper : AppColors.slateData),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            atCeiling
                ? 'This is the most notes an account can hold.'
                : 'Each step adds ${l.noteLimitStep} notes for '
                    '${l.noteLimitStepCostCoins} coins, up to ${l.noteLimitCeiling}.',
            style: AppType.bodySm,
          ),
          if (!atCeiling) ...[
            const SizedBox(height: AppSpace.md),
            InkActionButton(
              label: 'Add ${l.noteLimitStep} notes  ·  ${l.noteLimitStepCostCoins} coins',
              icon: Icons.add,
              onTap: energy.canAffordNoteLimit ? _raiseLimit : _needCoins,
            ),
          ],
        ],
      ),
    );
  }

  Widget _activity() {
    final all = energy.history;
    final shown = all.take(_shown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'ACTIVITY',
          trailing: GestureDetector(
            onTap: () {
              setState(() => _shown = _pageSize);
              energy.refresh();
            },
            behavior: HitTestBehavior.opaque,
            child: const Icon(Icons.refresh, size: 18, color: AppColors.ink),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (energy.error != null)
          _note('Could not load activity. Pull down to retry.')
        else if (all.isEmpty)
          _note('No transactions yet. Daily energy and conversions will '
              'show up here.')
        else ...[
          ...shown.map(_historyRow),
          if (all.length > _shown) ...[
            const SizedBox(height: AppSpace.xs),
            GhostButton(
              label: 'Load more',
              icon: Icons.expand_more,
              onTap: () => setState(() => _shown += _pageSize),
            ),
          ],
        ],
      ],
    );
  }

  Widget _note(String text) => EditorialModule(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Text(text, style: AppType.bodySm),
      );

  Widget _historyRow(EnergyTx tx) {
    final iconName = switch (tx.kind) {
      EnergyTxKind.purchase => 'atomic-coin',
      EnergyTxKind.convert => 'atomic-coin',
      _ => 'atom',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest,
        borderRadius: AppRadius.std,
        border: Border.all(color: AppColors.outlineVariant, width: AppStroke.rule),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AtomicIcon(iconName, size: 24),
          const SizedBox(width: AppSpace.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // Prefer the specific note ("Instant sync", "Standard sync",
                  // "Daily energy grant", "Welcome gift…") over the generic kind
                  // label, so the user sees exactly where energy/coins went.
                  (tx.note != null && tx.note!.isNotEmpty)
                      ? tx.note!
                      : tx.kind.label,
                  style: AppType.bodyMedium15,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                MonoLabel(_stamp(tx.createdAt), small: true),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (tx.energyDelta != 0) _delta(tx.energyDelta, 'ENERGY'),
              if (tx.coinsDelta != 0) _delta(tx.coinsDelta, 'COINS'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _delta(int value, String unit) {
    final positive = value > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${positive ? '+' : ''}$value',
            style: AppType.bodyMedium15.copyWith(
              color: positive ? AppColors.signal : AppColors.slateData,
            ),
          ),
          const SizedBox(width: 4),
          MonoLabel(unit, small: true, color: AppColors.slateData),
        ],
      ),
    );
  }

  static String _stamp(DateTime d) {
    final l = d.toLocal();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${p(l.month)}-${p(l.day)} ${p(l.hour)}:${p(l.minute)}';
  }
}

/// Bottom sheet to pick how many coins to convert. Local state only; the
/// service performs the (server-authoritative) conversion after it returns.
class _ConvertSheet extends StatefulWidget {
  final int maxCoins;
  final int energy;
  final int energyCap;
  const _ConvertSheet({
    required this.maxCoins,
    required this.energy,
    required this.energyCap,
  });

  @override
  State<_ConvertSheet> createState() => _ConvertSheetState();
}

class _ConvertSheetState extends State<_ConvertSheet> {
  int _amount = 1;

  int get _gain => _amount * EnergyService.coinToEnergy;
  bool get _overflows => widget.energy + _gain > widget.energyCap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MonoLabel('CONVERT COINS', color: AppColors.signal),
          const SizedBox(height: AppSpace.sm),
          const HairRule(color: AppColors.ink),
          const SizedBox(height: AppSpace.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _stepBtn(Icons.remove, () {
                if (_amount > 1) setState(() => _amount--);
              }),
              Column(
                children: [
                  Text('$_amount', style: AppType.statNumber),
                  const MonoLabel('COINS', small: true),
                ],
              ),
              _stepBtn(Icons.add, () {
                if (_amount < widget.maxCoins) setState(() => _amount++);
              }),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Text('= $_gain energy', style: AppType.headlineMd),
          const SizedBox(height: AppSpace.xs),
          if (_overflows)
            Text(
              'That would overflow your ${widget.energyCap} cap. Use some '
              'energy first or convert fewer coins.',
              style: AppType.bodySm.copyWith(color: AppColors.error),
            )
          else
            Text('You have ${widget.maxCoins} coins.', style: AppType.bodySm),
          const SizedBox(height: AppSpace.lg),
          InkActionButton(
            label: 'Convert',
            signal: true,
            icon: Icons.bolt,
            onTap: _overflows ? null : () => Navigator.of(context).pop(_amount),
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        width: 48,
        decoration: BoxDecoration(
          borderRadius: AppRadius.std,
          border: Border.all(color: AppColors.ink, width: AppStroke.hairline),
        ),
        child: Icon(icon, color: AppColors.ink),
      ),
    );
  }
}
