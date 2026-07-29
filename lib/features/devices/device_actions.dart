import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/schema/device_schema.dart';
import '../../core/text/humanize.dart';
import '../../design/components/hc_controls.dart';
import '../../design/components/hc_dialog.dart';
import '../automations/device_commands.dart';
import '../../design/tokens.dart';

/// The verbs a device declares, as buttons you can press.
///
/// This is the block the old panel had no equivalent of. `device_sheet` rendered
/// `schema.attributes` and nothing else, so a capability a plugin *declared* was
/// reachable only from the automations action picker — you could schedule a
/// thing you could not do. hc-roku declares 35 actions and hc-lutron declares
/// two; none of them had a control anywhere in the panel.
///
/// Nothing here is device-specific. Categories, labels, parameters and their
/// option sources all come off the wire, so a plugin that adds an action gets a
/// control without a client release.
class DeviceActionsBlock extends ConsumerWidget {
  const DeviceActionsBlock({
    super.key,
    required this.device,
    this.covered = const {},
  });

  final DeviceState device;

  /// Attributes the hero already gives a control for. A light's hero IS its
  /// brightness — offering "Set brightness…" beside it, and a brightness slider
  /// below that, is the same knob three times.
  final Set<String> covered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final actions = device.schema?.actions ?? const <DeviceActionSpec>[];

    // Rungs 2–4. Only three plugins publish a descriptor, so for almost every
    // device the verbs come from `commandsFor` — the same ladder the automations
    // picker walks (legacy `supported_actions`, then writable schema attributes,
    // then the facet). Reusing it is the point: a capability you can schedule
    // and a capability you can press must not be two different lists.
    if (actions.isEmpty) {
      return _FallbackVerbs(device: device, covered: covered);
    }

    // Grouped, in first-seen order — the plugin's own ordering is meaningful
    // (Power before Navigation), and sorting alphabetically would scramble it.
    final byCategory = <String, List<DeviceActionSpec>>{};
    for (final a in actions) {
      byCategory.putIfAbsent(a.category ?? 'Actions', () => []).add(a);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in byCategory.entries)
          if (_foldedCategories.contains(entry.key))
            _FoldedCategory(
              title: entry.key,
              child: _category(device, entry.value, t),
            )
          else ...[
            _BlockLabel(entry.key),
            SizedBox(height: t.space.sm),
            _category(device, entry.value, t),
            SizedBox(height: t.space.md),
          ],
      ],
    );
  }

  /// Some categories are not lists.
  ///
  /// hc-roku declares 35 actions and a faithful chip per action is 35 chips —
  /// technically complete and unusable. Eleven of them are a *directional pad*
  /// and three are a *volume rocker*: shapes people already know, which a list
  /// destroys. So a cluster whose members are all present renders as the shape,
  /// and whatever is left over stays chips.
  Widget _category(
      DeviceState device, List<DeviceActionSpec> actions, HcTokens t) {
    final byId = {for (final a in actions) a.id: a};
    final used = <String>{};

    final clusters = <Widget>[];
    for (final c in _clusters) {
      if (!c.ids.every(byId.containsKey)) continue;
      clusters.add(c.build(device, byId, t));
      used
        ..addAll(c.ids)
        ..addAll(c.absorbs);
    }

    final rest = actions.where((a) => !used.contains(a.id)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in clusters) ...[c, SizedBox(height: t.space.sm)],
        if (rest.isNotEmpty)
          Wrap(
            spacing: t.space.sm,
            runSpacing: t.space.sm,
            children: [
              for (final a in rest) _ActionChip(device: device, action: a),
            ],
          ),
      ],
    );
  }
}

/// A set of action ids that together make one familiar control.
class _Cluster {
  const _Cluster(this.ids, this.build, {this.absorbs = const []});

  /// Every one of these must be declared for the cluster to render at all.
  final List<String> ids;

  /// Ids the cluster also renders or supersedes when they happen to be there.
  /// Without this the transport deck drew `stop` AND left it in the chip row,
  /// and `play`/`pause` sat beside a play/pause button that already toggles.
  final List<String> absorbs;
  final Widget Function(
      DeviceState device, Map<String, DeviceActionSpec> byId, HcTokens t) build;
}

/// Categories that are reference rather than reach-for. A Roku's `key`,
/// `key_hold`, `key_down` and `key_up` are the raw ECP escape hatch — four
/// near-identical rows that push the D-pad off the screen, and nothing you
/// press by accident. They fold.
const _foldedCategories = {'Remote'};

final _clusters = <_Cluster>[
  // Transport, as the deck it is on every remote ever made: back, the big
  // play/pause, forward. `stop` joins them when declared.
  _Cluster(
    const ['previous', 'play_pause', 'next'],
    (device, byId, t) => _Transport(device: device, byId: byId),
    absorbs: const ['stop', 'play', 'pause'],
  ),
  // The D-pad. `select` in the middle, arrows around it — the shape of every
  // remote in the house.
  _Cluster(
    const ['up', 'down', 'left', 'right', 'select'],
    (device, byId, t) => _DPad(device: device, byId: byId),
  ),
  // The volume rocker. Deliberately NOT a slider: `supports_audio_volume_control`
  // is false on both Rokus here, so there is no level to read or set — only
  // three key presses. A slider would invent a value the device does not have.
  _Cluster(
    const ['volume_up', 'volume_down', 'mute'],
    (device, byId, t) => _Rocker(device: device, byId: byId),
  ),
];

/// Runs a declared action with no parameters. Shared by the clusters, which are
/// all built from parameterless keys.
Future<void> _fire(
    WidgetRef ref, DeviceState device, DeviceActionSpec a) async {
  await ref.read(devicesProvider.notifier).command(device.id, {'action': a.id});
}

class _DPad extends ConsumerWidget {
  const _DPad({required this.device, required this.byId});

  final DeviceState device;
  final Map<String, DeviceActionSpec> byId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);

    Widget key(String id, Widget child, {bool round = false}) {
      final a = byId[id];
      if (a == null) return const SizedBox(width: 44, height: 44);
      return _Key(
        size: 44,
        round: round,
        enabled: device.available,
        onTap: () => _fire(ref, device, a),
        tooltip: a.label,
        child: child,
      );
    }

    Widget arrow(String id, IconData icon) =>
        key(id, Icon(icon, size: 20, color: t.surface.onBase));

    const gap = SizedBox(width: 44, height: 44);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          gap,
          arrow('up', Icons.keyboard_arrow_up_rounded),
          gap,
        ]),
        SizedBox(height: t.space.xs),
        Row(mainAxisSize: MainAxisSize.min, children: [
          arrow('left', Icons.keyboard_arrow_left_rounded),
          SizedBox(width: t.space.xs),
          key(
            'select',
            Text('OK',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: t.accent.primary)),
            round: true,
          ),
          SizedBox(width: t.space.xs),
          arrow('right', Icons.keyboard_arrow_right_rounded),
        ]),
        SizedBox(height: t.space.xs),
        Row(mainAxisSize: MainAxisSize.min, children: [
          gap,
          arrow('down', Icons.keyboard_arrow_down_rounded),
          gap,
        ]),
      ],
    );
  }
}

class _Transport extends ConsumerWidget {
  const _Transport({required this.device, required this.byId});

  final DeviceState device;
  final Map<String, DeviceActionSpec> byId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final playing = device.playbackState == 'playing';

    Widget key(String id, IconData icon,
        {double size = 40, bool main = false}) {
      final a = byId[id];
      if (a == null) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.only(right: t.space.xs),
        child: _Key(
          size: size,
          round: main,
          enabled: device.available,
          onTap: () => _fire(ref, device, a),
          tooltip: a.label,
          child: Icon(icon,
              size: main ? 22 : 18,
              color: main ? t.accent.active : t.surface.onBase),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        key('previous', Icons.skip_previous_rounded),
        key('play_pause',
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 48, main: true),
        key('next', Icons.skip_next_rounded),
        if (byId.containsKey('stop')) key('stop', Icons.stop_rounded),
      ],
    );
  }
}

class _Rocker extends ConsumerWidget {
  const _Rocker({required this.device, required this.byId});

  final DeviceState device;
  final Map<String, DeviceActionSpec> byId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final muted = device.state['muted'] == true;

    Widget key(String id, IconData icon, {Color? tint}) {
      final a = byId[id]!;
      return _Key(
        size: 40,
        enabled: device.available,
        onTap: () => _fire(ref, device, a),
        tooltip: a.label,
        child: Icon(icon, size: 18, color: tint ?? t.surface.onBase),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        key('volume_down', Icons.remove_rounded),
        SizedBox(width: t.space.xs),
        key('volume_up', Icons.add_rounded),
        SizedBox(width: t.space.sm),
        key('mute', muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            tint: muted ? t.accent.warn : null),
      ],
    );
  }
}

/// One physical-feeling key. Presses depress; that feedback is most of what
/// makes a remote feel like a remote rather than a form.
class _Key extends StatefulWidget {
  const _Key({
    required this.size,
    required this.child,
    required this.onTap,
    this.round = false,
    this.enabled = true,
    this.tooltip,
  });

  final double size;
  final Widget child;
  final VoidCallback onTap;
  final bool round;
  final bool enabled;
  final String? tooltip;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final radius = widget.round
        ? BorderRadius.circular(999)
        : BorderRadius.circular(t.radius.sm + 2);

    final key = GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.enabled
          ? () {
              setState(() => _down = false);
              widget.onTap();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.93 : 1,
        duration: t.motion.d(t.motion.fast),
        child: Container(
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _down
                ? t.accent.primary.withValues(alpha: 0.16)
                : t.surface.raised,
            borderRadius: radius,
            border: Border.all(
                color: widget.round
                    ? t.accent.primary.withValues(alpha: 0.4)
                    : t.stroke.hairline),
          ),
          child:
              Opacity(opacity: widget.enabled ? 1 : 0.4, child: widget.child),
        ),
      ),
    );

    final tip = widget.tooltip;
    return tip == null || tip.isEmpty ? key : Tooltip(message: tip, child: key);
  }
}

/// Verbs for a device that declares no descriptor.
///
/// `commandsFor` returns rule nodes, not device commands — but a
/// `SetDeviceState` node's `state` map *is* the PATCH body, byte for byte. That
/// equivalence is deliberate (see `device_action_descriptor.md`): a rule and a
/// button press send the same payload, so one builder can serve both.
class _FallbackVerbs extends ConsumerStatefulWidget {
  const _FallbackVerbs({required this.device, this.covered = const {}});

  final DeviceState device;
  final Set<String> covered;

  @override
  ConsumerState<_FallbackVerbs> createState() => _FallbackVerbsState();
}

class _FallbackVerbsState extends ConsumerState<_FallbackVerbs> {
  String? _busy;

  Future<void> _run(DeviceCommand c, Object? value) async {
    final node = c.build(value);
    // Only device-state writes are pressable here. `SetMode` and friends target
    // something other than this device and belong to the automations editor.
    final state = node.fields['state'];
    if (node.tag != 'SetDeviceState' || state is! Map) return;

    setState(() => _busy = c.key);
    try {
      await ref
          .read(devicesProvider.notifier)
          .command(widget.device.id, Map<String, Object?>.from(state));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${c.label} failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _tap(DeviceCommand c) async {
    if (_busy != null) return;
    if (c.param.kind == CmdParamKind.none) {
      await _run(c, null);
      return;
    }
    final value = await showDialog<Object?>(
      context: context,
      builder: (_) => _ValueDialog(command: c),
    );
    if (value != null) await _run(c, value);
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final cmds = commandsFor(widget.device)
        // A colour picker is a control, not a verb — it stays in the Controls
        // block where it has room to be one.
        .where((c) => c.param.kind != CmdParamKind.color)
        // Not what the hero is already a control for.
        .where((c) => c.writes == null || !widget.covered.contains(c.writes))
        .toList();
    if (cmds.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _BlockLabel('Actions'),
        SizedBox(height: t.space.sm),
        Wrap(
          spacing: t.space.sm,
          runSpacing: t.space.sm,
          children: [
            for (final c in cmds)
              _Chip(
                label: c.label,
                icon: c.icon,
                hasParam: c.param.kind != CmdParamKind.none,
                busy: _busy == c.key,
                enabled: widget.device.available && _busy == null,
                onTap: () => _tap(c),
              ),
          ],
        ),
        SizedBox(height: t.space.md),
      ],
    );
  }
}

/// The value form for a fallback command with one parameter.
class _ValueDialog extends StatefulWidget {
  const _ValueDialog({required this.command});

  final DeviceCommand command;

  @override
  State<_ValueDialog> createState() => _ValueDialogState();
}

class _ValueDialogState extends State<_ValueDialog> {
  Object? _value;

  @override
  void initState() {
    super.initState();
    final p = widget.command.param;
    _value = p.defaultValue ??
        (p.options?.isNotEmpty == true ? p.options!.first : p.min);
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final p = widget.command.param;

    Widget control;
    if (p.options case final opts? when opts.isNotEmpty) {
      control = DropdownButtonFormField<String>(
        initialValue: '${_value ?? opts.first}',
        isExpanded: true,
        decoration: const InputDecoration(isDense: true),
        items: [
          for (final o in opts)
            DropdownMenuItem(value: o, child: Text(p.labelFor(o))),
        ],
        onChanged: (v) => setState(() => _value = v),
      );
    } else if (p.min != null && p.max != null) {
      final v = (_value as num?)?.toDouble() ?? p.min!.toDouble();
      control = Row(
        children: [
          Expanded(
            child: Slider(
              value: v.clamp(p.min!.toDouble(), p.max!.toDouble()),
              min: p.min!.toDouble(),
              max: p.max!.toDouble(),
              onChanged: (nv) => setState(() => _value = nv.round()),
            ),
          ),
          Text('${(_value as num?)?.round() ?? p.min}${p.unit ?? ''}',
              style: TextStyle(
                  fontSize: 13,
                  color: t.surface.onBase,
                  fontFeatures: t.numericFontFeatures)),
        ],
      );
    } else {
      control = TextField(
        decoration: const InputDecoration(isDense: true),
        onChanged: (v) => setState(() => _value = v),
      );
    }

    return HcDialog(
      title: widget.command.label,
      actions: [
        HcButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        HcButton(
          label: 'Run',
          kind: HcButtonKind.primary,
          onPressed:
              _value == null ? null : () => Navigator.pop(context, _value),
        ),
      ],
      child: control,
    );
  }
}

/// A category that is there when wanted and out of the way otherwise.
class _FoldedCategory extends StatefulWidget {
  const _FoldedCategory({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  State<_FoldedCategory> createState() => _FoldedCategoryState();
}

class _FoldedCategoryState extends State<_FoldedCategory> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: t.radius.smR,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: t.space.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BlockLabel(widget.title),
                SizedBox(width: t.space.xs),
                Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: t.surface.onBaseMuted),
              ],
            ),
          ),
        ),
        if (_open) ...[widget.child, SizedBox(height: t.space.md)],
      ],
    );
  }
}

class _BlockLabel extends StatelessWidget {
  const _BlockLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
        color: t.surface.onBaseMuted,
      ),
    );
  }
}

/// One action. No parameters means the chip *is* the button; parameters open a
/// small form, because firing `tune` with a guessed channel is worse than asking.
class _ActionChip extends ConsumerStatefulWidget {
  const _ActionChip({required this.device, required this.action});

  final DeviceState device;
  final DeviceActionSpec action;

  @override
  ConsumerState<_ActionChip> createState() => _ActionChipState();
}

class _ActionChipState extends ConsumerState<_ActionChip> {
  bool _busy = false;

  DeviceActionSpec get a => widget.action;

  Future<void> _run(Map<String, Object?> params) async {
    setState(() => _busy = true);
    try {
      await ref.read(devicesProvider.notifier).command(widget.device.id, {
        'action': a.id,
        ...params,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${a.label} failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _tap() async {
    if (_busy) return;
    if (a.params.isEmpty) {
      if (a.confirm != null && !await _confirmed()) return;
      await _run(const {});
      return;
    }
    final values = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _ParamDialog(device: widget.device, action: a),
    );
    if (values != null) await _run(values);
  }

  Future<bool> _confirmed() async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => HcDialog(
          title: a.label,
          description: a.confirm,
          actions: [
            HcButton(
                label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
            HcButton(
                label: a.label,
                kind: HcButtonKind.primary,
                onPressed: () => Navigator.pop(ctx, true)),
          ],
          child: const SizedBox.shrink(),
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => _Chip(
        label: a.label,
        icon: actionIcon(a),
        hasParam: a.params.isNotEmpty,
        busy: _busy,
        enabled: widget.device.available && !_busy,
        tooltip: a.description,
        onTap: _tap,
      );
}

/// The form for a parameterised action.
class _ParamDialog extends ConsumerStatefulWidget {
  const _ParamDialog({required this.device, required this.action});

  final DeviceState device;
  final DeviceActionSpec action;

  @override
  ConsumerState<_ParamDialog> createState() => _ParamDialogState();
}

class _ParamDialogState extends ConsumerState<_ParamDialog> {
  final _values = <String, Object?>{};
  final _text = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final p in widget.action.params) {
      final initial = p.defaultValue ?? _firstOption(p);
      _values[p.name] = initial;
      if (p.kind == ParamKind.string || p.kind == ParamKind.json) {
        _text[p.name] = TextEditingController(text: '${initial ?? ''}');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Object? _firstOption(ActionParamSpec p) {
    final opts = _optionsFor(p);
    return opts.isEmpty ? null : opts.first.value;
  }

  /// A parameter's choices: the fixed set, or the live catalogue the plugin
  /// pointed at. This is why a client can offer "Netflix" without knowing what
  /// a Roku channel is.
  List<ParamOption> _optionsFor(ActionParamSpec p) {
    if (p.options case final fixed? when fixed.isNotEmpty) return fixed;

    switch (p.optionsFrom) {
      case AttributeSource(
          attribute: final attr,
          labelKey: final lk,
          valueKey: final vk
        ):
        final raw = widget.device.state[attr];
        if (raw is! List) return const [];
        return [
          for (final item in raw)
            if (item is Map)
              ParamOption('${item[vk ?? 'id'] ?? item[lk ?? 'name'] ?? item}',
                  '${item[lk ?? 'name'] ?? item[vk ?? 'id'] ?? item}')
            else
              ParamOption('$item'),
        ];

      case DevicesSource(excludeSelf: final excludeSelf, facet: final facet):
        final all = ref.watch(devicesProvider).valueOrNull ?? const [];
        return [
          for (final d in all)
            if (!(excludeSelf && d.id == widget.device.id) &&
                (facet == null || facetOf(d, d.schema).name == facet))
              ParamOption(d.id, d.displayName),
        ];

      case _:
        return const [];
    }
  }

  bool get _complete => widget.action.params
      .where((p) => p.required)
      .every((p) => _values[p.name] != null && '${_values[p.name]}'.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final a = widget.action;

    return HcDialog(
      title: a.label,
      description: a.description ?? a.sentenceFor(widget.device.displayName),
      actions: [
        HcButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        HcButton(
          label: 'Run',
          kind: HcButtonKind.primary,
          onPressed: _complete
              ? () => Navigator.pop(context, Map<String, Object?>.from(_values))
              : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in a.params) ...[
            _field(t, p),
            SizedBox(height: t.space.md),
          ],
        ],
      ),
    );
  }

  Widget _field(HcTokens t, ActionParamSpec p) {
    final label = p.label ?? humanize(p.name);
    final options = _optionsFor(p);

    Widget control;
    if (options.isNotEmpty) {
      control = DropdownButtonFormField<String>(
        initialValue: '${_values[p.name] ?? options.first.value}',
        isExpanded: true,
        decoration: const InputDecoration(isDense: true),
        items: [
          for (final o in options)
            DropdownMenuItem(value: o.value, child: Text(o.display)),
        ],
        onChanged: (v) => setState(() => _values[p.name] = v),
      );
    } else if (p.kind == ParamKind.bool_) {
      control = Row(
        children: [
          HcToggle(
            value: _values[p.name] == true,
            semanticLabel: label,
            onChanged: (v) => setState(() => _values[p.name] = v),
          ),
          SizedBox(width: t.space.sm),
          Text(_values[p.name] == true ? 'Yes' : 'No',
              style: TextStyle(fontSize: 13, color: t.surface.onBase)),
        ],
      );
    } else if (p.kind.isNumeric && p.hasRange) {
      final v = (_values[p.name] as num?)?.toDouble() ?? p.min!;
      control = Row(
        children: [
          Expanded(
            child: Slider(
              value: v.clamp(p.min!, p.max!),
              min: p.min!,
              max: p.max!,
              divisions: p.step != null && p.step! > 0
                  ? ((p.max! - p.min!) / p.step!).round()
                  : null,
              onChanged: (nv) => setState(() => _values[p.name] =
                  p.kind == ParamKind.float_ ? nv : nv.round()),
            ),
          ),
          Text('${_values[p.name] ?? p.min!.round()}${p.unit ?? ''}',
              style: TextStyle(
                  fontSize: 13,
                  color: t.surface.onBase,
                  fontFeatures: t.numericFontFeatures)),
        ],
      );
    } else if (p.kind.isNumeric) {
      control = TextFormField(
        initialValue: '${_values[p.name] ?? ''}',
        keyboardType: TextInputType.number,
        decoration: InputDecoration(isDense: true, suffixText: p.unit),
        onChanged: (v) => setState(
            () => _values[p.name] = num.tryParse(v) ?? _values[p.name]),
      );
    } else {
      control = TextField(
        controller: _text[p.name],
        decoration: const InputDecoration(isDense: true),
        onChanged: (v) => setState(() => _values[p.name] = v),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.surface.onBaseMuted)),
        SizedBox(height: t.space.xs),
        control,
      ],
    );
  }
}

/// The one chip both rungs render as, so a declared verb and a fallback verb
/// are indistinguishable to the person pressing them.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.hasParam = false,
    this.busy = false,
    this.enabled = true,
    this.tooltip,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool hasParam;
  final bool busy;
  final bool enabled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final chip = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(t.radius.pill),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: t.space.md, vertical: t.space.sm),
          decoration: BoxDecoration(
            color: t.surface.raised,
            borderRadius: BorderRadius.circular(t.radius.pill),
            border: Border.all(color: t.stroke.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(icon,
                    size: 14,
                    color: enabled ? t.surface.onBase : t.surface.onBaseMuted),
              SizedBox(width: t.space.sm),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: enabled ? t.surface.onBase : t.surface.onBaseMuted,
                ),
              ),
              // An action that needs saying-more says so, rather than firing a
              // default the moment it is touched.
              if (hasParam) ...[
                SizedBox(width: t.space.xs),
                Text('…',
                    style: TextStyle(
                        fontSize: 12.5, color: t.surface.onBaseMuted)),
              ],
            ],
          ),
        ),
      ),
    );
    final tip = tooltip;
    return tip == null || tip.isEmpty
        ? chip
        : Tooltip(
            message: tip,
            waitDuration: const Duration(milliseconds: 600),
            child: chip);
  }
}

/// A plugin names an icon semantically (`remote`, `volume-up`) because it cannot
/// know the client's icon set. Anything unrecognised falls back to a neutral
/// glyph rather than a missing one.
IconData actionIcon(DeviceActionSpec a) => switch (a.icon) {
      'play' => Icons.play_arrow_rounded,
      'pause' => Icons.pause_rounded,
      'stop' => Icons.stop_rounded,
      'next' => Icons.skip_next_rounded,
      'previous' => Icons.skip_previous_rounded,
      'power' => Icons.power_settings_new_rounded,
      'volume' || 'volume-up' => Icons.volume_up_rounded,
      'volume-down' => Icons.volume_down_rounded,
      'mute' => Icons.volume_off_rounded,
      'remote' => Icons.settings_remote_outlined,
      'lightbulb' => Icons.lightbulb_outline,
      'app' || 'apps' => Icons.apps_rounded,
      'tv' => Icons.tv_rounded,
      'search' => Icons.search_rounded,
      'keyboard' || 'text' => Icons.keyboard_outlined,
      'home' => Icons.home_outlined,
      'back' => Icons.arrow_back_rounded,
      'up' => Icons.keyboard_arrow_up_rounded,
      'down' => Icons.keyboard_arrow_down_rounded,
      'left' => Icons.keyboard_arrow_left_rounded,
      'right' => Icons.keyboard_arrow_right_rounded,
      'select' || 'ok' => Icons.radio_button_checked,
      'lock' => Icons.lock_outline,
      'fan' => Icons.toys_outlined,
      _ => Icons.bolt_outlined,
    };

extension on DeviceActionSpec {
  /// The plugin's own phrasing, with `{device}` filled in. Used as the dialog's
  /// description so the form says what pressing Run will do.
  String? sentenceFor(String deviceName) =>
      sentence?.replaceAll('{device}', deviceName);
}
