import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/glue_api.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/glue_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/components/hc_surface.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';
import '../../shared/widgets/skeleton.dart';
import 'glue_id.dart';

/// Helpers — the devices the hub provides itself.
///
/// Timers, switches, counters and flags are real devices: rules trigger on
/// them, dashboards render them, and the device list shows them. But the only
/// way to *make* one was to POST to `/glue` by hand, and the only way to remove
/// one was to DELETE by hand. The CRUD has been on the hub the whole time with
/// nothing calling it.
class GluePage extends ConsumerWidget {
  const GluePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(glueProvider);
    final all = async.valueOrNull ?? const <DeviceState>[];

    return SectionScaffold(
      title: 'Helpers',
      stats: async.hasValue && all.isNotEmpty
          ? [
              SectionStat(
                  value: '${all.length}',
                  label: all.length == 1 ? 'helper' : 'helpers'),
            ]
          : const [],
      actions: [
        Builder(builder: (context) {
          final t = HcTokens.of(context);
          return IconButton(
            icon: Icon(Icons.refresh, color: t.surface.onBaseMuted),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(glueProvider),
          );
        }),
        SectionHeaderAction(
          icon: Icons.add_rounded,
          label: 'New helper',
          onPressed: () => _create(context, ref),
        ),
      ],
      child: Builder(builder: (context) {
        final t = HcTokens.of(context);
        return async.when(
          loading: () => const SkeletonCardList(count: 4),
          error: (e, _) => Center(
              child: Text('$e', style: TextStyle(color: t.accent.danger))),
          data: (devices) {
            if (devices.isEmpty) {
              return Center(
                child: Padding(
                  padding: EdgeInsets.all(t.space.lg),
                  child: Text(
                    'No helpers yet. A timer or a switch is often the simplest '
                    'way to hold state between rules.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.surface.onBaseMuted),
                  ),
                ),
              );
            }
            // Grouped by kind, because eleven kinds in one flat wall is the
            // device list again.
            final groups = <String, List<DeviceState>>{};
            for (final d in devices) {
              groups.putIfAbsent(d.deviceType ?? 'other', () => []).add(d);
            }
            return SingleChildScrollView(
              padding: EdgeInsets.all(t.space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in groups.entries) ...[
                    Padding(
                      padding: EdgeInsets.only(bottom: t.space.sm),
                      child: Text(
                        glueTypeFor(entry.key)?.label ?? humanize(entry.key),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: t.accent.active,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: t.space.md,
                      runSpacing: t.space.md,
                      children: [
                        for (final d in entry.value)
                          SizedBox(width: 340, child: _HelperCard(device: d)),
                      ],
                    ),
                    SizedBox(height: t.space.lg),
                  ],
                ],
              ),
            );
          },
        );
      }),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    var type = kGlueTypes.first;
    final taken = {
      for (final d
          in ref.read(glueProvider).valueOrNull ?? const <DeviceState>[])
        d.id,
    };

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final t = HcTokens.of(ctx);
          final id = glueIdFor(type.id, nameCtrl.text.trim());
          final clash = id.isNotEmpty && taken.contains(id);

          return HcDialog(
            title: 'New helper',
            width: 460,
            actions: [
              HcButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx)),
              HcButton(
                label: 'Create',
                kind: HcButtonKind.primary,
                onPressed: () async {
                  if (id.isEmpty || clash) return;
                  final name = nameCtrl.text.trim();
                  Navigator.pop(ctx);
                  try {
                    await ref.read(glueApiProvider).create(type.id, id, name);
                    ref.invalidate(glueProvider);
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
                // Kind first: it decides what the thing IS, and the name only
                // makes sense once you have picked.
                Wrap(
                  spacing: t.space.xs,
                  runSpacing: t.space.xs,
                  children: [
                    for (final g in kGlueTypes)
                      _TypeChip(
                        label: g.label,
                        selected: g.id == type.id,
                        onTap: () => setS(() => type = g),
                      ),
                  ],
                ),
                SizedBox(height: t.space.sm),
                Text(type.blurb,
                    style:
                        TextStyle(fontSize: 12, color: t.surface.onBaseMuted)),
                SizedBox(height: t.space.md),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  style: TextStyle(color: t.surface.onBase),
                  decoration: InputDecoration(
                    labelText: 'Name',
                    labelStyle: TextStyle(color: t.surface.onBaseMuted),
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: t.stroke.hairline)),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: t.accent.active)),
                  ),
                  onChanged: (_) => setS(() {}),
                ),
                SizedBox(height: t.space.sm),
                Text(
                  id.isEmpty
                      ? 'Rules will refer to this helper by an id derived from '
                          'its name.'
                      : clash
                          ? 'A helper with the id $id already exists.'
                          : 'Rules will refer to it as $id',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: id.isEmpty ? null : 'monospace',
                    color: clash ? t.accent.danger : t.surface.onBaseMuted,
                  ),
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

class _TypeChip extends StatelessWidget {
  const _TypeChip(
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
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? t.accent.active.withValues(alpha: 0.16)
              : t.surface.raised,
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: selected ? t.accent.active : t.stroke.hairline),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? t.surface.onBase : t.surface.onBaseMuted,
            )),
      ),
    );
  }
}

/// One helper: what it is, what it currently reads, and a way to remove it.
class _HelperCard extends ConsumerWidget {
  const _HelperCard({required this.device});

  final DeviceState device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    return HcSurface(
      padding: EdgeInsets.all(t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: t.surface.onBase)),
                  Text(device.id,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: t.surface.onBaseMuted)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline,
                  size: 18, color: t.surface.onBaseMuted),
              onPressed: () => _confirmDelete(context, ref),
            ),
          ]),
          if (device.state.isNotEmpty) ...[
            SizedBox(height: t.space.sm),
            // The live reading, so the card says what the helper is doing
            // rather than only that it exists.
            for (final e in device.state.entries)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  Expanded(
                    child: Text(humanize(e.key),
                        style: TextStyle(
                            fontSize: 12, color: t.surface.onBaseMuted)),
                  ),
                  Text('${e.value}',
                      style: TextStyle(
                          fontSize: 12,
                          fontFeatures: t.numericFontFeatures,
                          color: t.surface.onBase)),
                ]),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => HcDialog(
        title: 'Delete ${device.displayName}?',
        // Deleting a helper a rule references breaks that rule: core rewrites
        // the reference to DELETED: and disables the rule rather than guessing.
        description: 'Rules referring to it will be disabled.',
        actions: [
          HcButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
          HcButton(
            label: 'Delete',
            kind: HcButtonKind.danger,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
        child: const SizedBox.shrink(),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(glueApiProvider).delete(device.id);
      ref.invalidate(glueProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }
}
