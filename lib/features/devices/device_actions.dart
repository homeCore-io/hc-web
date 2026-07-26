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
  const DeviceActionsBlock({super.key, required this.device});

  final DeviceState device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final actions = device.schema?.actions ?? const <DeviceActionSpec>[];

    // Rungs 2–4. Only three plugins publish a descriptor, so for almost every
    // device the verbs come from `commandsFor` — the same ladder the automations
    // picker walks (legacy `supported_actions`, then writable schema attributes,
    // then the facet). Reusing it is the point: a capability you can schedule
    // and a capability you can press must not be two different lists.
    if (actions.isEmpty) return _FallbackVerbs(device: device);

    // Grouped, in first-seen order — the plugin's own ordering is meaningful
    // (Power before Navigation), and sorting alphabetically would scramble it.
    final byCategory = <String, List<DeviceActionSpec>>{};
    for (final a in actions) {
      byCategory.putIfAbsent(a.category ?? 'Actions', () => []).add(a);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in byCategory.entries) ...[
          _BlockLabel(entry.key),
          SizedBox(height: t.space.sm),
          Wrap(
            spacing: t.space.sm,
            runSpacing: t.space.sm,
            children: [
              for (final a in entry.value)
                _ActionChip(device: device, action: a),
            ],
          ),
          SizedBox(height: t.space.md),
        ],
      ],
    );
  }
}

/// Verbs for a device that declares no descriptor.
///
/// `commandsFor` returns rule nodes, not device commands — but a
/// `SetDeviceState` node's `state` map *is* the PATCH body, byte for byte. That
/// equivalence is deliberate (see `device_action_descriptor.md`): a rule and a
/// button press send the same payload, so one builder can serve both.
class _FallbackVerbs extends ConsumerStatefulWidget {
  const _FallbackVerbs({required this.device});

  final DeviceState device;

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
