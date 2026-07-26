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
import '../automations/widgets/device_choice_picker.dart';
import '../automations/widgets/editor_style.dart';
import '../automations/widgets/rule_refs.dart';
import 'glue_config.dart';
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
    // Number: a range and a unit. Defaults match what the hub would apply, so
    // leaving them alone changes nothing.
    final minCtrl = TextEditingController(text: '0');
    final maxCtrl = TextEditingController(text: '100');
    final stepCtrl = TextEditingController(text: '1');
    final unitCtrl = TextEditingController();
    // Select: the options it can hold.
    final optionCtrl = TextEditingController();
    final options = <String>[];
    // Group: which devices, read on which attribute, combined how.
    final members = <String>[];
    var groupAttribute = 'on';
    var groupMode = 'any';

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
                  final config = glueConfigFor(
                    type.config,
                    min: minCtrl.text,
                    max: maxCtrl.text,
                    step: stepCtrl.text,
                    unit: unitCtrl.text,
                    options: options,
                    members: members,
                    attribute: groupAttribute,
                    mode: groupMode,
                  );
                  Navigator.pop(ctx);
                  try {
                    await ref
                        .read(glueApiProvider)
                        .create(type.id, id, name, config: config);
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
                if (type.config != GlueConfig.none) ...[
                  SizedBox(height: t.space.md),
                  ..._configFields(
                    ctx,
                    t,
                    type,
                    setS,
                    ref: ref,
                    minCtrl: minCtrl,
                    maxCtrl: maxCtrl,
                    stepCtrl: stepCtrl,
                    unitCtrl: unitCtrl,
                    optionCtrl: optionCtrl,
                    options: options,
                    members: members,
                    groupAttribute: groupAttribute,
                    groupMode: groupMode,
                    onAttribute: (v) => groupAttribute = v,
                    onMode: (v) => groupMode = v,
                  ),
                ],
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
    minCtrl.dispose();
    maxCtrl.dispose();
    stepCtrl.dispose();
    unitCtrl.dispose();
    optionCtrl.dispose();
  }

  /// The extra questions a kind needs before it is any use.
  ///
  /// A number without a range is a 0–100 slider whatever it measures; a select
  /// with no options can never be set; a group with no members reports on
  /// nothing. Sending these at creation is the difference between a helper
  /// that works and one that has to be fixed somewhere else immediately.
  List<Widget> _configFields(
    BuildContext context,
    HcTokens t,
    GlueType type,
    void Function(void Function()) setS, {
    required WidgetRef ref,
    required TextEditingController minCtrl,
    required TextEditingController maxCtrl,
    required TextEditingController stepCtrl,
    required TextEditingController unitCtrl,
    required TextEditingController optionCtrl,
    required List<String> options,
    required List<String> members,
    required String groupAttribute,
    required String groupMode,
    required ValueChanged<String> onAttribute,
    required ValueChanged<String> onMode,
  }) {
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          labelStyle: TextStyle(color: t.surface.onBaseMuted),
          enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: t.stroke.hairline)),
          focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: t.accent.active)),
        );

    switch (type.config) {
      case GlueConfig.number:
        return [
          Row(children: [
            Expanded(
                child: TextField(
                    controller: minCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: t.surface.onBase),
                    decoration: deco('Min'))),
            SizedBox(width: t.space.sm),
            Expanded(
                child: TextField(
                    controller: maxCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: t.surface.onBase),
                    decoration: deco('Max'))),
            SizedBox(width: t.space.sm),
            Expanded(
                child: TextField(
                    controller: stepCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: t.surface.onBase),
                    decoration: deco('Step'))),
            SizedBox(width: t.space.sm),
            Expanded(
                child: TextField(
                    controller: unitCtrl,
                    style: TextStyle(color: t.surface.onBase),
                    decoration: deco('Unit'))),
          ]),
        ];

      case GlueConfig.select:
        return [
          const RailLabel('Options'),
          const SizedBox(height: 6),
          if (options.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final o in options)
                  InputChip(
                    label: Text(o),
                    onDeleted: () => setS(() => options.remove(o)),
                  ),
              ],
            ),
          SizedBox(height: t.space.xs),
          TextField(
            controller: optionCtrl,
            style: TextStyle(color: t.surface.onBase),
            decoration: deco('Add an option, then Enter'),
            onSubmitted: (v) {
              final o = v.trim();
              if (o.isEmpty || options.contains(o)) return;
              setS(() {
                options.add(o);
                optionCtrl.clear();
              });
            },
          ),
          if (options.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'The first option becomes the initial value.',
                style:
                    TextStyle(fontSize: 11.5, color: t.surface.onBaseMuted),
              ),
            ),
        ];

      case GlueConfig.group:
        return [
          const RailLabel('Members'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final m in members)
                InputChip(
                  label: Text(ref.read(ruleRefsProvider).labelFor(m)),
                  onDeleted: () => setS(() => members.remove(m)),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
                onPressed: () async {
                  // The same searchable, room-grouped picker every other
                  // device choice uses.
                  final picked = await pickDeviceRef(
                    context,
                    refs: ref.read(ruleRefsProvider),
                    kicker: 'Group member',
                  );
                  if (picked == null || members.contains(picked)) return;
                  setS(() => members.add(picked));
                },
              ),
            ],
          ),
          SizedBox(height: t.space.md),
          Row(children: [
            Expanded(
              child: TextFormField(
                initialValue: groupAttribute,
                style: TextStyle(color: t.surface.onBase),
                decoration: deco('Attribute'),
                onChanged: onAttribute,
              ),
            ),
            SizedBox(width: t.space.sm),
            // "Any" and "All" are the whole vocabulary, so they are two chips
            // rather than a dropdown of two.
            for (final m in const ['any', 'all'])
              Padding(
                padding: EdgeInsets.only(left: t.space.xs),
                child: _TypeChip(
                  label: m == 'any' ? 'Any on' : 'All on',
                  selected: groupMode == m,
                  onTap: () => setS(() => onMode(m)),
                ),
              ),
          ]),
        ];

      case GlueConfig.none:
        return const [];
    }
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
