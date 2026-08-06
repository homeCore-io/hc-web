import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/mode_state.dart';
import '../../core/providers/modes_provider.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/components/hc_surface.dart';
import '../../design/tokens.dart';
import 'mode_id.dart';
import '../../shared/widgets/section_scaffold.dart';
import '../../shared/widgets/skeleton.dart';

/// Modes — the house's coarse states (Guest, Vacation, Night…). Two kinds:
/// *manual* modes you flip yourself, and *solar* modes the sun drives, offset
/// by however many minutes you nudge them.
class ModesPage extends ConsumerWidget {
  const ModesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modesAsync = ref.watch(modesProvider);
    final modes = modesAsync.value ?? const <ModeState>[];
    final on = modes.where((m) => m.on).length;

    return SectionScaffold(
      title: 'Modes',
      stats: modesAsync.hasValue && modes.isNotEmpty
          ? [
              SectionStat(
                  value: '${modes.length}',
                  label: modes.length == 1 ? 'mode' : 'modes'),
              if (on > 0)
                SectionStat(
                    value: '$on',
                    label: 'on',
                    tone: SectionTone.active,
                    glow: true),
            ]
          : const [],
      actions: [
        Builder(builder: (context) {
          final t = HcTokens.of(context);
          return IconButton(
            icon: Icon(Icons.refresh, color: t.surface.onBaseMuted),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(modesProvider),
          );
        }),
        SectionHeaderAction(
          icon: Icons.add_rounded,
          label: 'New mode',
          onPressed: () => _showCreateDialog(context, ref),
        ),
      ],
      child: Builder(builder: (context) {
        final t = HcTokens.of(context);
        return modesAsync.when(
          loading: () => const SkeletonCardList(count: 4),
          error: (e, _) => Center(
              child: Text('$e', style: TextStyle(color: t.accent.danger))),
          data: (modes) {
            if (modes.isEmpty) {
              return Center(
                child: Text('No modes configured',
                    style: TextStyle(color: t.surface.onBaseMuted)),
              );
            }
            return SingleChildScrollView(
              padding: EdgeInsets.all(t.space.lg),
              child: Wrap(
                spacing: t.space.md,
                runSpacing: t.space.md,
                children: [
                  for (final m in modes)
                    SizedBox(width: 340, child: _ModeCard(mode: m)),
                ],
              ),
            );
          },
        );
      }),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    String kind = 'manual';
    // Ids already taken, so a clash is refused here rather than by the API
    // after the dialog has closed.
    final taken = {
      for (final m in ref.read(modesProvider).value ?? const <ModeState>[])
        m.id,
    };

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final t = HcTokens.of(ctx);
          InputDecoration deco(String label) => InputDecoration(
                labelText: label,
                labelStyle: TextStyle(color: t.surface.onBaseMuted),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: t.stroke.hairline)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: t.accent.active)),
              );
          return HcDialog(
            title: 'Create mode',
            actions: [
              HcButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx)),
              HcButton(
                label: 'Create',
                kind: HcButtonKind.primary,
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final id = modeIdFor(name);
                  if (id.isEmpty || taken.contains(id)) return;
                  Navigator.pop(ctx);
                  try {
                    await ref.read(modesApiProvider).createMode(id, name, kind);
                    ref.invalidate(modesProvider);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Failed: $e')));
                    }
                  }
                },
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Name only. The id follows from it — asking for both meant
                // inventing a primary key and then being told off for getting
                // its prefix wrong.
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: TextStyle(color: t.surface.onBase),
                  decoration: deco('Name'),
                  onChanged: (_) => setS(() {}),
                ),
                SizedBox(height: t.space.sm),
                Builder(builder: (_) {
                  final id = modeIdFor(nameCtrl.text.trim());
                  final clash = id.isNotEmpty && taken.contains(id);
                  return Text(
                    id.isEmpty
                        ? 'Rules will refer to this mode by an id derived from '
                            'its name.'
                        : clash
                            ? 'A mode with the id $id already exists.'
                            : 'Rules will refer to it as $id',
                    style: t.text.captionStyle.copyWith(
                        fontFamily: id.isEmpty ? null : 'monospace',
                        color: clash ? t.accent.danger : t.surface.onBaseMuted),
                  );
                }),
                SizedBox(height: t.space.md),
                Row(
                  children: [
                    for (final k in const ['manual', 'solar'])
                      Padding(
                        padding: EdgeInsets.only(right: t.space.sm),
                        child: _KindChip(
                          label: k == 'manual' ? 'Manual' : 'Solar',
                          selected: kind == k,
                          onTap: () => setS(() => kind = k),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    nameCtrl.dispose();
  }
}

/// A selectable kind pill for the create dialog.
class _KindChip extends StatelessWidget {
  const _KindChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? t.accent.active.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(t.radius.pill),
          border: Border.all(
              color: selected ? Colors.transparent : t.stroke.hairline),
        ),
        child: Text(label,
            style: t.text.bodySmallStyle.copyWith(
                fontWeight: FontWeight.w600,
                color: selected ? t.accent.active : t.surface.onBaseMuted)),
      ),
    );
  }
}

class _ModeCard extends ConsumerStatefulWidget {
  final ModeState mode;
  const _ModeCard({required this.mode});

  @override
  ConsumerState<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends ConsumerState<_ModeCard> {
  late double _onOffset;
  late double _offOffset;

  @override
  void initState() {
    super.initState();
    _onOffset = widget.mode.onOffsetMinutes.toDouble();
    _offOffset = widget.mode.offOffsetMinutes.toDouble();
  }

  Future<void> _deleteMode() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => HcDialog(
        title: 'Delete ${widget.mode.displayName}?',
        description: 'This cannot be undone.',
        actions: [
          HcButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
          HcButton(
              label: 'Delete',
              kind: HcButtonKind.danger,
              onPressed: () => Navigator.pop(ctx, true)),
        ],
        child: const SizedBox.shrink(),
      ),
    );
    if (ok == true) {
      try {
        await ref.read(modesApiProvider).deleteMode(widget.mode.id);
        ref.invalidate(modesProvider);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final mode = widget.mode;
    final isSolar = mode.kind == 'solar';
    final isNight = mode.id == 'mode_night';

    return HcSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.surface.sunken,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.stroke.hairline),
                ),
                child: Icon(
                  isSolar ? Icons.wb_twilight_rounded : Icons.tune_rounded,
                  size: 18,
                  color: mode.on ? t.accent.active : t.surface.onBaseMuted,
                ),
              ),
              SizedBox(width: t.space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(mode.displayName,
                        style: t.text.subtitleStyle.copyWith(
                            fontWeight: FontWeight.w600,
                            color: t.surface.onBase)),
                    Text(isSolar ? 'Solar' : 'Manual',
                        style: t.text.bodySmallStyle
                            .copyWith(color: t.surface.onBaseMuted)),
                  ],
                ),
              ),
              if (isSolar)
                _DayNightChip(night: mode.isNightNow ?? mode.on)
              else
                _Toggle(
                  on: mode.on,
                  onChanged: (v) async {
                    await ref.read(modesApiProvider).setModeOn(mode.id, v);
                    ref.invalidate(modesProvider);
                  },
                ),
              if (!isNight)
                Padding(
                  padding: EdgeInsets.only(left: t.space.xs),
                  child: IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 18, color: t.surface.onBaseMuted),
                    tooltip: 'Delete',
                    onPressed: _deleteMode,
                  ),
                ),
            ],
          ),
          if (isSolar) ...[
            Padding(
              padding: EdgeInsets.symmetric(vertical: t.space.md),
              child: Divider(height: 1, color: t.stroke.hairline),
            ),
            if (mode.sunsetToday != null)
              _kv(t, 'Sunset today', mode.sunsetToday!),
            if (mode.sunriseToday != null)
              _kv(t, 'Sunrise today', mode.sunriseToday!),
            if (mode.effectiveOn != null)
              _kv(t, 'Effective ON', mode.effectiveOn!),
            if (mode.effectiveOff != null)
              _kv(t, 'Effective OFF', mode.effectiveOff!),
            SizedBox(height: t.space.md),
            _offsetSlider(
              t,
              label: 'ON offset',
              value: _onOffset,
              onChanged: (v) => setState(() => _onOffset = v),
              onEnd: (v) async {
                await ref
                    .read(modesApiProvider)
                    .setOffset(mode.id, 'on_offset_minutes', v.round());
                ref.invalidate(modesProvider);
              },
            ),
            _offsetSlider(
              t,
              label: 'OFF offset',
              value: _offOffset,
              onChanged: (v) => setState(() => _offOffset = v),
              onEnd: (v) async {
                await ref
                    .read(modesApiProvider)
                    .setOffset(mode.id, 'off_offset_minutes', v.round());
                ref.invalidate(modesProvider);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(HcTokens t, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
                width: 118,
                child: Text(label,
                    style: t.text.bodySmallStyle
                        .copyWith(color: t.surface.onBaseMuted))),
            Text(value,
                style: t.text.bodySmallStyle.copyWith(
                    color: t.surface.onBase,
                    fontFeatures: t.numericFontFeatures)),
          ],
        ),
      );

  Widget _offsetSlider(
    HcTokens t, {
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onEnd,
  }) {
    final mins = value.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: t.text.bodySmallStyle
                    .copyWith(color: t.surface.onBaseMuted)),
            const Spacer(),
            Text('${mins >= 0 ? '+' : ''}$mins min',
                style: t.text.bodySmallStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: t.surface.onBase,
                    fontFeatures: t.numericFontFeatures)),
          ],
        ),
        Slider(
          value: value.clamp(-120, 120),
          min: -120,
          max: 120,
          divisions: 48,
          activeColor: t.accent.active,
          inactiveColor: t.surface.overlay,
          onChanged: onChanged,
          onChangeEnd: onEnd,
        ),
      ],
    );
  }
}

/// The studio on/off pill — amber when on, matching the "active = amber"
/// language the rest of the app uses.
class _Toggle extends StatelessWidget {
  const _Toggle({required this.on, required this.onChanged});
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return GestureDetector(
      onTap: () => onChanged(!on),
      child: AnimatedContainer(
        duration: t.motion.fast,
        width: 42,
        height: 24,
        decoration: BoxDecoration(
          color:
              on ? t.accent.active.withValues(alpha: 0.3) : t.surface.overlay,
          borderRadius: BorderRadius.circular(999),
          border:
              Border.all(color: on ? Colors.transparent : t.stroke.hairline),
        ),
        child: AnimatedAlign(
          duration: t.motion.fast,
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: on ? t.accent.active : t.surface.onBaseMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// DAY / NIGHT indicator for solar modes — read-only, since the sun decides.
class _DayNightChip extends StatelessWidget {
  const _DayNightChip({required this.night});
  final bool night;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final color = night ? t.accent.primary : t.surface.onBaseMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: night
            ? t.accent.primary.withValues(alpha: 0.16)
            : t.surface.overlay,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        night ? 'NIGHT' : 'DAY',
        style: t.text.captionStyle.copyWith(
            fontWeight: FontWeight.w700, letterSpacing: 0.5, color: color),
      ),
    );
  }
}
