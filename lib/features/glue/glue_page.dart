import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/glue_api.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/glue_provider.dart';
import '../../core/schema/attribute_policy.dart';
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
import 'group_attributes.dart';
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
    final all = async.value ?? const <DeviceState>[];

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
                        style: t.text.bodySmallStyle.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                            color: t.accent.active),
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
    // Timer: how long it runs, and whether it restarts itself.
    final durationCtrl = TextEditingController(text: '5');
    var durationUnit = 'minutes';
    var repeat = false;
    // Number: a range and a unit. Defaults match what the hub would apply, so
    // leaving them alone changes nothing.
    final minCtrl = TextEditingController(text: '0');
    final maxCtrl = TextEditingController(text: '100');
    final stepCtrl = TextEditingController(text: '1');
    final unitCtrl = TextEditingController();
    // Text: how long a line it accepts.
    final maxLengthCtrl = TextEditingController();
    // Date & time: which halves it holds.
    var hasDate = true;
    var hasTime = true;
    // Threshold: which reading, and where the line sits.
    var sourceRef = '';
    var sourceAttribute = 'value';
    final thresholdCtrl = TextEditingController(text: '0');
    final hysteresisCtrl = TextEditingController(text: '0');
    // Select: the options it can hold.
    final optionCtrl = TextEditingController();
    final options = <String>[];
    // Group: which devices, read on which attribute, combined how.
    final members = <String>[];
    var groupAttribute = 'on';
    var groupMode = 'any';
    var groupExpect = true;

    var type = kGlueTypes.first;
    final taken = {
      for (final d in ref.read(glueProvider).value ?? const <DeviceState>[])
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
                    expect: groupExpect,
                    durationSecs:
                        _durationSecs(durationCtrl.text, durationUnit),
                    repeat: repeat,
                    maxLength: maxLengthCtrl.text,
                    hasDate: hasDate,
                    hasTime: hasTime,
                    sourceDeviceId: sourceRef,
                    sourceAttribute: sourceAttribute,
                    threshold: thresholdCtrl.text,
                    hysteresis: hysteresisCtrl.text,
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
                    style: t.text.bodySmallStyle
                        .copyWith(color: t.surface.onBaseMuted)),
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
                    durationCtrl: durationCtrl,
                    durationUnit: durationUnit,
                    repeat: repeat,
                    onDurationUnit: (v) => durationUnit = v,
                    onRepeat: (v) => repeat = v,
                    maxLengthCtrl: maxLengthCtrl,
                    hasDate: hasDate,
                    hasTime: hasTime,
                    onHasDate: (v) => hasDate = v,
                    onHasTime: (v) => hasTime = v,
                    sourceRef: sourceRef,
                    sourceAttribute: sourceAttribute,
                    thresholdCtrl: thresholdCtrl,
                    hysteresisCtrl: hysteresisCtrl,
                    onSource: (r, a) {
                      sourceRef = r;
                      sourceAttribute = a;
                    },
                    options: options,
                    members: members,
                    groupAttribute: groupAttribute,
                    groupMode: groupMode,
                    groupExpect: groupExpect,
                    onState: (a, e) {
                      groupAttribute = a;
                      groupExpect = e;
                    },
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
                  style: t.text.captionStyle.copyWith(
                      fontFamily: id.isEmpty ? null : 'monospace',
                      color: clash ? t.accent.danger : t.surface.onBaseMuted),
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

  /// Change an existing helper.
  ///
  /// Before this the only way to fix a select's options or a group's members
  /// was to delete and recreate — which breaks every rule referring to it,
  /// since core rewrites a deleted reference to `DELETED:` and disables the
  /// rule. Editing keeps the id, so the rules keep working.
  static Future<void> edit(
    BuildContext context,
    WidgetRef ref,
    DeviceState device,
  ) async {
    final type = glueTypeFor(device.deviceType);
    final nameCtrl = TextEditingController(text: device.displayName);
    final attrs = device.state;

    // Seeded from what the helper currently holds, so opening the dialog and
    // pressing Save changes nothing.
    final seconds = (attrs['duration_secs'] as num?)?.toInt() ?? 0;
    final (seedValue, seedUnit) = _splitDuration(seconds);
    final durationCtrl = TextEditingController(text: '$seedValue');
    var durationUnit = seedUnit;
    var repeat = attrs['repeat'] as bool? ?? false;
    final minCtrl = TextEditingController(text: '${attrs['min'] ?? ''}');
    final maxCtrl = TextEditingController(text: '${attrs['max'] ?? ''}');
    final stepCtrl = TextEditingController(text: '${attrs['step'] ?? ''}');
    final unitCtrl = TextEditingController(text: '${attrs['unit'] ?? ''}');
    final maxLengthCtrl =
        TextEditingController(text: '${attrs['max_length'] ?? ''}');
    var hasDate = attrs['has_date'] as bool? ?? true;
    var hasTime = attrs['has_time'] as bool? ?? true;
    var sourceRef = '${attrs['source_device_id'] ?? ''}';
    var sourceAttribute = '${attrs['source_attribute'] ?? 'value'}';
    final thresholdCtrl =
        TextEditingController(text: '${attrs['threshold'] ?? 0}');
    final hysteresisCtrl =
        TextEditingController(text: '${attrs['hysteresis'] ?? 0}');
    final optionCtrl = TextEditingController();
    final options = [
      for (final o in (attrs['options'] as List? ?? const [])) '$o',
    ];
    final members = [
      for (final m in (attrs['member_ids'] as List? ?? const [])) '$m',
    ];
    var groupAttribute = '${attrs['attribute'] ?? 'on'}';
    var groupMode = '${attrs['mode'] ?? 'any'}';
    var groupExpect = attrs['expect'] as bool? ?? true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final t = HcTokens.of(ctx);
          return HcDialog(
            title: 'Edit ${device.displayName}',
            width: 460,
            actions: [
              HcButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx)),
              HcButton(
                label: 'Save',
                kind: HcButtonKind.primary,
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  Navigator.pop(ctx);
                  final api = ref.read(glueApiProvider);
                  try {
                    if (name.isNotEmpty && name != device.displayName) {
                      await api.rename(device.id, name);
                    }
                    if (type != null && type.config != GlueConfig.none) {
                      await api.update(
                        device.id,
                        glueConfigFor(
                          type.config,
                          min: minCtrl.text,
                          max: maxCtrl.text,
                          step: stepCtrl.text,
                          unit: unitCtrl.text,
                          options: options,
                          members: members,
                          attribute: groupAttribute,
                          mode: groupMode,
                          expect: groupExpect,
                          durationSecs:
                              _durationSecs(durationCtrl.text, durationUnit),
                          repeat: repeat,
                          maxLength: maxLengthCtrl.text,
                          hasDate: hasDate,
                          hasTime: hasTime,
                          sourceDeviceId: sourceRef,
                          sourceAttribute: sourceAttribute,
                          threshold: thresholdCtrl.text,
                          hysteresis: hysteresisCtrl.text,
                        ),
                      );
                    }
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
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(color: t.surface.onBase),
                  decoration: InputDecoration(
                    labelText: 'Name',
                    labelStyle: TextStyle(color: t.surface.onBaseMuted),
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: t.stroke.hairline)),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: t.accent.active)),
                  ),
                ),
                SizedBox(height: t.space.sm),
                Text(
                  // The id never changes: rules refer to it, and renaming the
                  // key would break them for a cosmetic edit.
                  device.id,
                  style: t.text
                      .resolve(t.text.caption, mono: true)
                      .copyWith(color: t.surface.onBaseMuted),
                ),
                if (type != null && type.config != GlueConfig.none) ...[
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
                    durationCtrl: durationCtrl,
                    durationUnit: durationUnit,
                    repeat: repeat,
                    onDurationUnit: (v) => durationUnit = v,
                    onRepeat: (v) => repeat = v,
                    maxLengthCtrl: maxLengthCtrl,
                    hasDate: hasDate,
                    hasTime: hasTime,
                    onHasDate: (v) => hasDate = v,
                    onHasTime: (v) => hasTime = v,
                    sourceRef: sourceRef,
                    sourceAttribute: sourceAttribute,
                    thresholdCtrl: thresholdCtrl,
                    hysteresisCtrl: hysteresisCtrl,
                    onSource: (r, a) {
                      sourceRef = r;
                      sourceAttribute = a;
                    },
                    options: options,
                    members: members,
                    groupAttribute: groupAttribute,
                    groupMode: groupMode,
                    groupExpect: groupExpect,
                    onState: (a, e) {
                      groupAttribute = a;
                      groupExpect = e;
                    },
                    onMode: (v) => groupMode = v,
                  ),
                ] else
                  Padding(
                    padding: EdgeInsets.only(top: t.space.sm),
                    child: Text(
                      'A ${type?.label.toLowerCase() ?? 'helper'} of this kind '
                      'has nothing to configure beyond its name.',
                      style: t.text.bodySmallStyle
                          .copyWith(color: t.surface.onBaseMuted),
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
    maxLengthCtrl.dispose();
    thresholdCtrl.dispose();
    hysteresisCtrl.dispose();
  }

  /// Seconds from a value and a unit, however the field was left.
  ///
  /// A blank or unparseable field is zero, which the dialog shows in the
  /// running total — a timer that counts down from nothing finishes the
  /// instant it starts, and that should be visible before Create.
  static int _durationSecs(String value, String unit) {
    final n = int.tryParse(value.trim()) ?? 0;
    return switch (unit) {
      'hours' => n * 3600,
      'minutes' => n * 60,
      _ => n,
    };
  }

  /// Seconds back into the largest unit that divides them exactly, so editing
  /// a five-minute timer shows "5 minutes" rather than "300 seconds".
  static (int, String) _splitDuration(int seconds) {
    if (seconds == 0) return (0, 'minutes');
    if (seconds % 3600 == 0) return (seconds ~/ 3600, 'hours');
    if (seconds % 60 == 0) return (seconds ~/ 60, 'minutes');
    return (seconds, 'seconds');
  }

  /// The extra questions a kind needs before it is any use.
  ///
  /// A number without a range is a 0–100 slider whatever it measures; a select
  /// with no options can never be set; a group with no members reports on
  /// nothing. Sending these at creation is the difference between a helper
  /// that works and one that has to be fixed somewhere else immediately.
  static List<Widget> _configFields(
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
    required TextEditingController durationCtrl,
    required String durationUnit,
    required bool repeat,
    required ValueChanged<String> onDurationUnit,
    required ValueChanged<bool> onRepeat,
    required TextEditingController maxLengthCtrl,
    required bool hasDate,
    required bool hasTime,
    required ValueChanged<bool> onHasDate,
    required ValueChanged<bool> onHasTime,
    required String sourceRef,
    required String sourceAttribute,
    required TextEditingController thresholdCtrl,
    required TextEditingController hysteresisCtrl,
    required void Function(String device, String attribute) onSource,
    required List<String> options,
    required List<String> members,
    required String groupAttribute,
    required String groupMode,
    required bool groupExpect,
    required void Function(String attribute, bool expect) onState,
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
      case GlueConfig.timer:
        return [
          const RailLabel('Counts down for'),
          const SizedBox(height: 6),
          Row(children: [
            SizedBox(
              width: 90,
              child: TextField(
                controller: durationCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(color: t.surface.onBase),
                decoration: deco(''),
                onChanged: (_) => setS(() {}),
              ),
            ),
            SizedBox(width: t.space.sm),
            // Seconds is what the hub stores; nobody thinks in it for a
            // five-minute timer, and typing 300 is a conversion the UI can do.
            for (final u in const ['seconds', 'minutes', 'hours'])
              Padding(
                padding: EdgeInsets.only(right: t.space.xs),
                child: _TypeChip(
                  label: u,
                  selected: durationUnit == u,
                  onTap: () => setS(() => onDurationUnit(u)),
                ),
              ),
          ]),
          SizedBox(height: t.space.xs),
          Text(
            '= ${_durationSecs(durationCtrl.text, durationUnit)} seconds',
            style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
          ),
          SizedBox(height: t.space.md),
          const RailLabel('When it finishes'),
          const SizedBox(height: 6),
          Row(children: [
            for (final r in const [false, true])
              Padding(
                padding: EdgeInsets.only(right: t.space.xs),
                child: _TypeChip(
                  label: r ? 'Start again' : 'Stop',
                  selected: repeat == r,
                  onTap: () => setS(() => onRepeat(r)),
                ),
              ),
          ]),
        ];

      case GlueConfig.counter:
        return [
          Row(children: [
            Expanded(
                child: TextField(
                    controller: stepCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: t.surface.onBase),
                    decoration: deco('Step'))),
            SizedBox(width: t.space.sm),
            // Blank means unbounded, which is what the hub does when the key
            // is absent — a zero here would silently floor the counter.
            Expanded(
                child: TextField(
                    controller: minCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: t.surface.onBase),
                    decoration: deco('Min (optional)'))),
            SizedBox(width: t.space.sm),
            Expanded(
                child: TextField(
                    controller: maxCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: t.surface.onBase),
                    decoration: deco('Max (optional)'))),
          ]),
        ];

      case GlueConfig.text:
        return [
          TextField(
            controller: maxLengthCtrl,
            keyboardType: TextInputType.number,
            style: TextStyle(color: t.surface.onBase),
            decoration: deco('Max length (optional)'),
          ),
          const SizedBox(height: 4),
          Text('Leave empty for no limit.',
              style:
                  t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
        ];

      case GlueConfig.datetime:
        return [
          const RailLabel('Holds'),
          const SizedBox(height: 6),
          Row(children: [
            for (final o in const [
              ('Date and time', true, true),
              ('Date only', true, false),
              ('Time only', false, true),
            ])
              Padding(
                padding: EdgeInsets.only(right: t.space.xs),
                child: _TypeChip(
                  label: o.$1,
                  selected: hasDate == o.$2 && hasTime == o.$3,
                  // One choice, not two switches: "neither" is a helper that
                  // holds nothing, and the pair is really three options.
                  onTap: () => setS(() {
                    onHasDate(o.$2);
                    onHasTime(o.$3);
                  }),
                ),
              ),
          ]),
        ];

      case GlueConfig.threshold:
        final numeric =
            numericAttributes(ref.read(ruleRefsProvider), sourceRef);
        return [
          const RailLabel('Watches'),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.tune, size: 16),
                label: Text(
                  sourceRef.isEmpty
                      ? 'Pick a device'
                      : ref.read(ruleRefsProvider).labelFor(sourceRef),
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () async {
                  final picked = await pickDeviceRef(
                    context,
                    refs: ref.read(ruleRefsProvider),
                    current: sourceRef.isEmpty ? null : sourceRef,
                    kicker: 'Threshold source',
                  );
                  if (picked == null) return;
                  // The attribute belongs to the device it was chosen for.
                  final attrs =
                      numericAttributes(ref.read(ruleRefsProvider), picked);
                  setS(() =>
                      onSource(picked, attrs.isEmpty ? 'value' : attrs.first));
                },
              ),
            ),
          ]),
          SizedBox(height: t.space.sm),
          Row(children: [
            Expanded(
              child: numeric.isEmpty
                  ? TextFormField(
                      initialValue: sourceAttribute,
                      style: TextStyle(color: t.surface.onBase),
                      decoration: deco(sourceRef.isEmpty
                          ? 'Reading'
                          : 'Reading (device reports no numbers)'),
                      onChanged: (v) => onSource(sourceRef, v),
                    )
                  : DropdownButtonFormField<String>(
                      initialValue: numeric.contains(sourceAttribute)
                          ? sourceAttribute
                          : null,
                      isExpanded: true,
                      style: TextStyle(color: t.surface.onBase),
                      dropdownColor: t.surface.overlay,
                      decoration: deco('Reading'),
                      items: [
                        for (final a in numeric)
                          DropdownMenuItem(value: a, child: Text(humanize(a))),
                      ],
                      onChanged: (v) =>
                          setS(() => onSource(sourceRef, v ?? sourceAttribute)),
                    ),
            ),
            SizedBox(width: t.space.sm),
            SizedBox(
              width: 110,
              child: TextField(
                controller: thresholdCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(color: t.surface.onBase),
                decoration: deco('Above'),
              ),
            ),
            SizedBox(width: t.space.sm),
            // Without a guard a reading sitting on the line toggles the
            // helper — and every rule watching it — over and over.
            SizedBox(
              width: 110,
              child: TextField(
                controller: hysteresisCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(color: t.surface.onBase),
                decoration: deco('± deadband'),
              ),
            ),
          ]),
        ];

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
                    t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
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
                  // Multi-select: four door sensors used to mean four visits
                  // to the same panel, each starting from the top.
                  final picked = await pickDeviceRefs(
                    context,
                    refs: ref.read(ruleRefsProvider),
                    current: members,
                    kicker: 'Group members',
                    title: 'Which devices?',
                  );
                  if (picked == null || picked.isEmpty) return;
                  setS(() {
                    for (final p in picked) {
                      if (!members.contains(p)) members.add(p);
                    }
                    // The state is chosen from what the members share, so a
                    // new member can invalidate it.
                    final shared =
                        sharedStates(ref.read(ruleRefsProvider), members);
                    if (shared.isNotEmpty &&
                        !shared.any((s) => s.attribute == groupAttribute)) {
                      onState(shared.first.attribute, shared.first.expect);
                    }
                  });
                },
              ),
            ],
          ),
          SizedBox(height: t.space.md),
          // Read as a sentence. "Members are: Open / closed" named the pair
          // without saying which state counted, and "Any ON" baked in a word
          // that is wrong for a door — a group of doors is on when they are
          // OPEN, not "on".
          const RailLabel('This group is on when'),
          const SizedBox(height: 6),
          Row(children: [
            for (final m in const ['any', 'all'])
              Padding(
                padding: EdgeInsets.only(right: t.space.xs),
                child: _TypeChip(
                  label: m == 'any' ? 'Any' : 'All',
                  selected: groupMode == m,
                  onTap: () => setS(() => onMode(m)),
                ),
              ),
            SizedBox(width: t.space.xs),
            Expanded(
              child: Builder(builder: (_) {
                final shared =
                    sharedStates(ref.read(ruleRefsProvider), members);
                // The verb agrees with the quantifier: "any member is open",
                // "all members are open".
                final lead = groupMode == 'any' ? 'member is' : 'members are';
                if (shared.isEmpty) {
                  // No members yet, or members with nothing in common. Free
                  // text is the honest control then — we have nothing to
                  // offer, and refusing to let them type would be worse.
                  return TextFormField(
                    initialValue: groupAttribute,
                    style: TextStyle(color: t.surface.onBase),
                    decoration: deco(members.isEmpty
                        ? lead
                        : '$lead … (members share no yes/no state)'),
                    onChanged: (v) => onState(v, groupExpect),
                  );
                }
                // Every attribute contributes BOTH of its states: a group is
                // as often about the off one — "all deck doors closed" — as
                // the on one.
                final current = '$groupAttribute:$groupExpect';
                return DropdownButtonFormField<String>(
                  initialValue:
                      shared.any((s) => s.key == current) ? current : null,
                  isExpanded: true,
                  style: TextStyle(color: t.surface.onBase),
                  dropdownColor: t.surface.overlay,
                  decoration: deco(lead),
                  items: [
                    for (final s in shared)
                      DropdownMenuItem(value: s.key, child: Text(s.label)),
                  ],
                  onChanged: (v) => setS(() {
                    final picked = GroupState.fromKey(v, shared);
                    if (picked != null) {
                      onState(picked.attribute, picked.expect);
                    }
                  }),
                );
              }),
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
            style: t.text.bodySmallStyle.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? t.surface.onBase : t.surface.onBaseMuted)),
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
                      style: t.text.subtitleStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          color: t.surface.onBase)),
                  Text(device.id,
                      overflow: TextOverflow.ellipsis,
                      style: t.text
                          .resolve(t.text.caption, mono: true)
                          .copyWith(color: t.surface.onBaseMuted)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit',
              icon: Icon(Icons.edit_outlined,
                  size: 17, color: t.surface.onBaseMuted),
              onPressed: () => GluePage.edit(context, ref, device),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline,
                  size: 18, color: t.surface.onBaseMuted),
              onPressed: () => _confirmDelete(context, ref),
            ),
          ]),
          SizedBox(height: t.space.sm),
          // A summary of what this helper is set up to DO, where that is not
          // obvious from its readings. A group's configuration is four
          // attributes — member_ids, attribute, expect, mode — and dumping
          // them raw wrapped `Member Ids` one letter per line and overflowed
          // the card by 27 pixels with a device-id array.
          if (_summary(ref) case final summary?) ...[
            Text(
              summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted),
            ),
            SizedBox(height: t.space.sm),
          ],
          // Live readings only. Configuration is what the edit dialog is for.
          for (final e in device.state.entries)
            if (!_configKeys.contains(e.key))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  Expanded(
                    child: Text(humanize(e.key),
                        overflow: TextOverflow.ellipsis,
                        style: t.text.bodySmallStyle
                            .copyWith(color: t.surface.onBaseMuted)),
                  ),
                  const SizedBox(width: 8),
                  // Constrained and ellipsised: an unbounded value is what
                  // overflowed the card.
                  Flexible(
                    child: Text(
                      _render(e.value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: t.text.bodySmallStyle.copyWith(
                          fontFeatures: t.numericFontFeatures,
                          color: t.surface.onBase),
                    ),
                  ),
                ]),
              ),
        ],
      ),
    );
  }

  /// Attributes that describe how the helper is CONFIGURED rather than what it
  /// currently reads. They belong in the edit dialog, not on the card.
  static const _configKeys = {
    'attribute',
    'expect',
    'mode',
    'member_ids',
    'options',
    'min',
    'max',
    'step',
    'unit',
    'max_length',
    'has_date',
    'has_time',
    'source_device_id',
    'source_attribute',
    'threshold',
    'duration_secs',
    'repeat',
  };

  /// 300 → "5 minutes". The card should not make anyone divide by sixty.
  static String _humanDuration(int seconds) {
    String plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'}';
    if (seconds % 3600 == 0) return plural(seconds ~/ 3600, 'hour');
    if (seconds % 60 == 0) return plural(seconds ~/ 60, 'minute');
    return plural(seconds, 'second');
  }

  static String _render(Object? v) {
    if (v is List) return v.isEmpty ? 'none' : '${v.length}';
    return '$v';
  }

  /// What this helper is set up to do, in one line.
  String? _summary(WidgetRef ref) {
    final a = device.state;
    switch (device.deviceType) {
      case 'timer':
        final secs = (a['duration_secs'] as num?)?.toInt() ?? 0;
        final repeat = a['repeat'] as bool? ?? false;
        if (secs == 0) {
          // Worth saying outright: a timer with no duration finishes the
          // instant it starts, which looks like a timer that does nothing.
          return 'No duration set — finishes immediately';
        }
        return '${_humanDuration(secs)}${repeat ? ', repeating' : ''}';
      case 'group':
        final members = (a['member_ids'] as List? ?? const []).length;
        final attribute = '${a['attribute'] ?? 'on'}';
        final expect = a['expect'] as bool? ?? true;
        final all = a['mode'] == 'all';
        // Named from the plugin's own declaration, so it reads "closed" for a
        // door group and "off" for a light group rather than "open = false".
        final states = sharedAttributes(ref.read(ruleRefsProvider), [
          for (final m in (a['member_ids'] as List? ?? const [])) '$m',
        ]);
        final named = states.where((s) => s.name == attribute).firstOrNull;
        // The plugin's own words first. Failing that — the members may not be
        // loaded yet — the client lexicon still knows a door from a lock, and
        // "open false" would be a poor thing to show meanwhile.
        final lexicon = boolStatesFor(attribute, null);
        final word = named != null
            ? (expect ? named.whenTrue : named.whenFalse)
            : lexicon != null
                ? lexicon[expect].label
                : '$attribute ${expect ? 'true' : 'false'}';
        final noun = members == 1 ? 'member' : 'members';
        return 'On when ${all ? 'all' : 'any'} of $members $noun '
            '${members == 1 && !all ? 'is' : 'are'} $word';
      case 'number':
        final unit = a['unit'] == null ? '' : ' ${a['unit']}';
        return '${a['min'] ?? 0} to ${a['max'] ?? 100}$unit, '
            'step ${a['step'] ?? 1}';
      case 'select':
        final options = (a['options'] as List? ?? const []).map((o) => '$o');
        return options.isEmpty ? 'No options set' : options.join(' · ');
      case 'counter':
        final min = a['min'];
        final max = a['max'];
        final bounds = (min == null && max == null)
            ? 'unbounded'
            : '${min ?? '−∞'} to ${max ?? '∞'}';
        return 'Steps by ${a['step'] ?? 1}, $bounds';
      case 'text':
        final limit = a['max_length'];
        return limit == null ? 'No length limit' : 'Up to $limit characters';
      case 'datetime':
        final date = a['has_date'] as bool? ?? true;
        final time = a['has_time'] as bool? ?? true;
        if (date && time) return 'Date and time';
        return date ? 'Date only' : 'Time only';
      case 'threshold':
        final source = '${a['source_device_id'] ?? ''}';
        if (source.isEmpty) return 'No source set';
        final name = ref.read(ruleRefsProvider).labelFor(source);
        return 'On when $name '
            '${humanize('${a['source_attribute'] ?? 'value'}').toLowerCase()} '
            'is above ${a['threshold'] ?? 0}';
      default:
        return null;
    }
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
