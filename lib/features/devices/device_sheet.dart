import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/text/humanize.dart';
import '../../core/devices/presentation.dart';
import '../../core/devices/rooms.dart';
import '../../core/models/device_state.dart';
import '../../core/models/history_entry.dart';
import '../../core/providers/areas_provider.dart';
import '../../core/providers/automations_provider.dart';
import '../../core/providers/device_history_provider.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/components/hc_attribute_control.dart';
import '../../design/components/hc_controls.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/components/hc_history_chart.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../../shell/hc_sheet.dart';
import '../automations/rule_phrasing.dart';
import 'device_actions.dart';
import 'device_hero.dart';
import 'device_readings.dart';
import 'device_scenes.dart';

/// A device, laid over the house rather than replacing it.
///
/// One panel does everything — glance, control, edit, inspect — so there is no
/// jump to a separate page. It's a bottom sheet on a phone and a right drawer on
/// a wide screen (see [showHcSheet]); a fixed header carries the essentials and
/// the Control / Info / History segments keep even a busy device compact.
Future<void> showDeviceSheet(BuildContext context, String deviceId) =>
    showHcSheet<void>(
      context,
      title: 'Device',
      child: DevicePanel(deviceId: deviceId),
    );

/// The device panel — used both inside the sheet and as the full page reached by
/// deep link / command palette. [showClose] draws the sheet's close button; the
/// full page hides it (its scaffold owns the back arrow).
class DevicePanel extends ConsumerStatefulWidget {
  const DevicePanel({super.key, required this.deviceId, this.showClose = true});

  final String deviceId;
  final bool showClose;

  @override
  ConsumerState<DevicePanel> createState() => _DevicePanelState();
}

class _DevicePanelState extends ConsumerState<DevicePanel> {
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value ?? const [];
    final device = devices
        .where((d) => d.id == widget.deviceId)
        .cast<DeviceState?>()
        .firstOrNull;

    if (device == null) {
      return Padding(
        padding: EdgeInsets.all(t.space.lg),
        child: Text('Device not found.',
            style: TextStyle(color: t.surface.onBaseMuted)),
      );
    }

    // Blocks, not tabs.
    //
    // Control / Info / History put the same three-tab chrome around every
    // device, which flattered none of them: a leak sensor wore a tab bar built
    // for a Sonos, and the tab labelled *Control* held no controls at all for
    // the ~95% of devices that register no schema. So the panel is now a single
    // scroll of blocks, and a block that has nothing to say does not render.
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(device: device, showClose: widget.showClose),
          if (!device.available)
            const _Banner(
              icon: HcIcons.offline,
              message: 'This device is offline. Commands will not reach it.',
            ),

          // The hero: what this device IS, before what it can be told to do.
          // Renders nothing for a facet with nothing worth enlarging.
          Padding(
            padding: EdgeInsets.fromLTRB(
                t.space.lg, t.space.xs, t.space.lg, t.space.md),
            child: DeviceHero(device: device),
          ),

          // Scenes, before the generic verbs: for a Hue bulb "Tropical
          // twilight" is the thing you actually came to press, and a colour
          // wheel is what you use when none of them is right.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: t.space.lg),
            child: DeviceScenesBlock(device: device),
          ),

          // Verbs — "what can I do with this" is the other half of the question
          // the panel is open to answer.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: t.space.lg),
            child: DeviceActionsBlock(
              device: device,
              covered: heroAttributesOf(device),
            ),
          ),

          // Controls — the writable attributes the verbs did not already cover.
          _Controls(device: device),

          // Readings — everything it reports but you cannot set, in units.
          _Readings(device: device),
          SizedBox(height: t.space.md),

          // History — trends and what changed lately.
          _Section(
            title: 'History',
            initiallyOpen: false,
            child: _HistoryTab(device: device),
          ),

          _Section(
            title: 'Details',
            initiallyOpen: false,
            child: _InfoTab(device: device),
          ),
          SizedBox(height: t.space.lg),
        ],
      ),
    );
  }
}

/// A collapsible block. Closed by default for the two that are reference rather
/// than control — the panel opens on what you can *do*.
class _Section extends StatefulWidget {
  const _Section({
    required this.title,
    required this.child,
    this.initiallyOpen = true,
  });

  final String title;
  final Widget child;
  final bool initiallyOpen;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space.lg),
          child: Divider(height: 1, color: t.stroke.hairline),
        ),
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: t.space.lg, vertical: t.space.sm + 2),
            child: Row(
              children: [
                Text(
                  widget.title.toUpperCase(),
                  style: t.text.overlineStyle.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: t.surface.onBaseMuted),
                ),
                const Spacer(),
                Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: t.surface.onBaseMuted),
              ],
            ),
          ),
        ),
        if (_open) widget.child,
        if (_open) SizedBox(height: t.space.md),
      ],
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  const _Header({required this.device, this.showClose = true});
  final DeviceState device;
  final bool showClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final facet = facetOf(device, device.schema);
    final on = device.available && isOn(device);

    final room =
        device.effectiveArea != null ? humanize(device.effectiveArea!) : null;
    final showPower = facet.isActuator && device.available;

    final String stateWord;
    final Color stateColor;
    if (!device.available) {
      stateWord = 'Offline';
      stateColor = t.accent.offline;
    } else if (showPower) {
      // The power control says On/Off in words a centimetre away; repeating it
      // here would be the same fact twice.
      stateWord =
          device.deviceType != null ? humanize(device.deviceType!) : 'Device';
      stateColor = t.surface.onBaseMuted;
    } else if (facet.isActuator) {
      stateWord = on ? 'On' : 'Off';
      stateColor = on ? t.accent.active : t.surface.onBaseMuted;
    } else {
      stateWord =
          device.deviceType != null ? humanize(device.deviceType!) : 'Device';
      stateColor = t.surface.onBaseMuted;
    }

    return Padding(
      padding:
          EdgeInsets.fromLTRB(t.space.lg, t.space.md, t.space.sm, t.space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on
                  ? t.accent.active.withValues(alpha: 0.14)
                  : t.surface.overlay,
              borderRadius: t.radius.mdR,
            ),
            child: Icon(facet.icon,
                size: 21, color: on ? t.accent.active : t.surface.onBaseMuted),
          ),
          SizedBox(width: t.space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: t.space.xs),
                Text(
                  device.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.titleStyle.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: t.surface.onBase),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (room != null) ...[
                      Flexible(
                        child: Text(room,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.text.bodySmallStyle
                                .copyWith(color: t.surface.onBaseMuted)),
                      ),
                      Text(' · ',
                          style: t.text.bodySmallStyle
                              .copyWith(color: t.surface.onBaseMuted)),
                    ],
                    Text(stateWord,
                        style: t.text.bodySmallStyle.copyWith(
                            fontWeight: FontWeight.w600, color: stateColor)),
                  ],
                ),
              ],
            ),
          ),
          if (showPower)
            Padding(
              padding: EdgeInsets.only(top: t.space.xs, right: t.space.xs),
              child: _PowerButton(
                on: on,
                semanticLabel: device.displayName,
                onChanged: (v) => ref
                    .read(devicesProvider.notifier)
                    .command(device.id, {'on': v}),
              ),
            ),
          if (showClose)
            IconButton(
              icon: const Icon(HcIcons.x, size: 16),
              tooltip: 'Close',
              color: t.surface.onBaseMuted,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
        ],
      ),
    );
  }
}

/// The panel's power control: a labelled pill, not a bare switch.
///
/// A 34×20 [HcToggle] in the top-right corner was the least noticeable thing in
/// the panel — unlabelled, low-contrast when off, and sitting a few pixels from
/// the close ✕, which is the one neighbour a power control should not be
/// confused with. Here the word is part of the control, so its state is legible
/// without decoding a switch position, and it is big enough to aim at.
class _PowerButton extends StatelessWidget {
  const _PowerButton({
    required this.on,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool on;
  final ValueChanged<bool> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final fg = on ? t.accent.onPrimary : t.surface.onBaseMuted;

    return Semantics(
      toggled: on,
      button: true,
      label: semanticLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onChanged(!on),
          child: AnimatedContainer(
            duration: t.motion.d(t.motion.fast),
            curve: t.motion.curve,
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: t.space.md),
            decoration: BoxDecoration(
              color: on ? t.accent.active : t.surface.overlay,
              borderRadius: t.radius.pillR,
              border: Border.all(
                color: on ? Colors.transparent : t.stroke.hairline,
              ),
              // The same halo the lit tiles wear, so "on" carries at a glance.
              boxShadow: on && t.glow.enabled
                  ? [
                      BoxShadow(
                        color: t.accent.active.withValues(alpha: 0.32),
                        blurRadius: 14,
                        spreadRadius: -3,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Material's glyph, not the bundled Phosphor face: those two
                // .ttf files carry no glyph names, so a codepoint picked for
                // `power` cannot be verified and renders whatever is next door.
                Icon(Icons.power_settings_new_rounded, size: 16, color: fg),
                SizedBox(width: t.space.xs),
                Text(
                  on ? 'On' : 'Off',
                  style: t.text.bodyStyle.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Control tab ───────────────────────────────────────────────────────────────

/// Every writable attribute the device declares, as the control its kind calls
/// for. `on` already has the header toggle, so it is not repeated. A device with
/// no schema falls back to plainly-worded readings.
class _Controls extends ConsumerStatefulWidget {
  const _Controls({required this.device});
  final DeviceState device;

  @override
  ConsumerState<_Controls> createState() => _ControlsState();
}

class _ControlsState extends ConsumerState<_Controls> {
  bool _advOpen = false;

  DeviceState get _d => widget.device;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final schema = _d.schema;
    final hasSchema = schema != null && schema.attributes.isNotEmpty;

    // An attribute an action already supersedes is not shown twice: a Roku
    // declaring `select_source` (which `writes: source`) would otherwise offer
    // both a "Source" control and a "Select a source" verb for one thing.
    final claimed = {
      ...?schema?.attributesClaimedByActions,
      // …and whatever the hero is already a control for.
      ...heroAttributesOf(_d),
    };

    // Controls are things you can SET. Read-only state moved to the Readings
    // block, which knows units and grouping — mixing the two is what made a
    // weather station's seventeen unitless rows live under a tab called
    // *Control*. With no registered schema there is nothing here at all: an
    // inferred `writable` is a guess, and a slider that does nothing is worse
    // than no slider.
    final keys = (hasSchema
            ? schema.attributes.entries
                .where((e) => e.value.writable && e.key != 'on')
                .map((e) => e.key)
            : const <String>[])
        .where((k) => !claimed.contains(k))
        .toList();
    final present = keys.toSet();

    // Hidden outright: plumbing, and the raw twin of a percentage (a light
    // reports both `brightness` and `brightness_pct` — keep the %).
    bool hidden(String k) =>
        _isMetadata(k) || (!k.endsWith('_pct') && present.contains('${k}_pct'));
    final visible = keys.where((k) => !hidden(k)).toList();

    // Advanced: Z-wave command-class dumps (cc134_… firmware versions, cc99_…
    // user-code slots) — real, but noise for most people, so folded away.
    final primary = visible.where((k) => !_isAdvancedAttr(k)).toList();
    final advanced = visible.where((k) => _isAdvancedAttr(k)).toList();

    // Nothing to set is not worth a sentence saying so — the block just goes.
    if (primary.isEmpty && advanced.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final k in primary) _item(t, hasSchema, k),
          if (advanced.isNotEmpty) ...[
            SizedBox(height: t.space.xs),
            InkWell(
              onTap: () => setState(() => _advOpen = !_advOpen),
              borderRadius: t.radius.smR,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: t.space.sm),
                child: Row(
                  children: [
                    Text('Advanced · ${advanced.length}',
                        style: t.text.bodySmallStyle
                            .copyWith(color: t.surface.onBaseMuted)),
                    const Spacer(),
                    Icon(
                        _advOpen
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: t.surface.onBaseMuted),
                  ],
                ),
              ),
            ),
            if (_advOpen)
              for (final k in advanced) _item(t, hasSchema, k),
          ],
        ],
      ),
    );
  }

  Widget _item(HcTokens t, bool hasSchema, String k) {
    if (!hasSchema) {
      return _Reading(
          name: _metricName(k), value: _readingValue(_d, k, _d.state[k]));
    }
    final attr = _d.schema!.attributes[k]!;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.md),
      child: HcAttributeControl(
        name: k,
        schema: attr,
        value: _d.state[k],
        enabled: _d.available,
        onCommit: attr.writable
            ? (v) => ref.read(devicesProvider.notifier).command(_d.id, {k: v})
            : null,
      ),
    );
  }
}

/// Readings, with the attributes another block already owns held back.
///
/// The hide set is assembled here rather than inside the readings block so the
/// panel stays the one place that knows which blocks are on screen — otherwise
/// adding a hero means remembering to teach a second file about it.
class _Readings extends StatelessWidget {
  const _Readings({required this.device});

  final DeviceState device;

  @override
  Widget build(BuildContext context) {
    final schema = device.schema;
    return DeviceReadingsBlock(
      device: device,
      hide: {
        ...heroAttributesOf(device),
        // Whatever the Controls block is rendering as a control.
        ...?schema?.attributes.entries
            .where((e) => e.value.writable)
            .map((e) => e.key),
        ...?schema?.attributesClaimedByActions,
      },
    );
  }
}

// ── Info tab ──────────────────────────────────────────────────────────────────

class _InfoTab extends ConsumerStatefulWidget {
  const _InfoTab({required this.device});
  final DeviceState device;

  @override
  ConsumerState<_InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends ConsumerState<_InfoTab> {
  bool _editing = false;
  bool _tech = false;
  bool _busy = false;
  String? _error;
  final _name = TextEditingController();
  final _area = TextEditingController();

  /// The chosen icon while editing, or null for "whatever the device is".
  DeviceFacet? _icon;

  DeviceState get _d => widget.device;

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    super.dispose();
  }

  /// Manufacturer and model as one line, because they are read together and
  /// either can be absent: "Signify LCT015", or just "Signify", or nothing.
  String? get _hardware {
    final parts = [_d.manufacturer, _d.model]
        .where((s) => s != null && s.trim().isNotEmpty)
        .map((s) => s!.trim());
    return parts.isEmpty ? null : parts.join(' ');
  }

  String get _currentArea =>
      _d.effectiveArea != null ? humanize(_d.effectiveArea!) : '';

  void _start() => setState(() {
        _editing = true;
        _error = null;
        _name.text = _d.displayName;
        _area.text = _currentArea;
        _icon = deviceIconOverride(_d);
      });

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name cannot be empty');
      return;
    }
    final areaText = _area.text.trim();
    final body = <String, dynamic>{};
    if (name != _d.displayName) body['name'] = name;
    if (areaText != _currentArea) {
      body['area'] = areaText.isEmpty ? null : areaText;
    }
    // Null clears it, which is how you get back to the device's own icon.
    if (_icon != deviceIconOverride(_d)) {
      body['status_icon'] = _icon?.iconKey;
    }
    if (body.isEmpty) {
      setState(() => _editing = false);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(devicesProvider.notifier).updateDevice(_d.id, body);
      // Areas carry their membership, so moving a device makes the cached list
      // wrong — the Areas manager would keep showing the room you just left.
      if (body.containsKey('area')) ref.invalidate(areasProvider);
      if (mounted) setState(() => _editing = _busy = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => HcDialog(
        title: 'Remove ${_d.displayName}?',
        description:
            'The device is removed from homeCore. If its plugin still sees it, '
            'it may reappear on the next sync.',
        actions: [
          HcButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
          HcButton(
              label: 'Remove',
              kind: HcButtonKind.danger,
              onPressed: () => Navigator.pop(ctx, true)),
        ],
        child: const SizedBox.shrink(),
      ),
    );
    if (ok == true) {
      try {
        await ref.read(devicesProvider.notifier).deleteDevice(_d.id);
        if (mounted) Navigator.of(context).maybePop();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Remove failed: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    if (_editing) return _editor(t);

    final source = humanize(_d.pluginId.replaceFirst('plugin.', ''));
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kv(t, 'Name', _d.displayName, onEdit: _start),
          _kv(t, 'Room', _currentArea.isEmpty ? 'No room' : _currentArea,
              onEdit: _start, actionLabel: 'change'),
          if (_d.deviceType != null) _kv(t, 'Type', humanize(_d.deviceType!)),
          _kv(t, 'Source', source),

          // What the thing actually is, when its plugin says. Above the
          // technical fold rather than inside it: "which of my three of these
          // is this" and "what firmware is it on" are questions an owner asks,
          // not an integrator debugging a rule.
          //
          // Absent for most devices — a plugin has to have been taught to
          // report it — so each row appears only when there is something to
          // say, rather than a column of "Unknown".
          if (_hardware != null) _kv(t, 'Hardware', _hardware!),
          if (_d.swVersion != null) _kv(t, 'Firmware', _d.swVersion!),
          SizedBox(height: t.space.sm),
          Divider(height: 1, color: t.stroke.hairline),
          SizedBox(height: t.space.sm),
          _UsedBy(device: _d),
          Divider(height: 1, color: t.stroke.hairline),

          // Technical details — folded away; a person renaming a lamp does not
          // need its raw id, but an integrator debugging a rule does.
          InkWell(
            onTap: () => setState(() => _tech = !_tech),
            borderRadius: t.radius.smR,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: t.space.sm),
              child: Row(
                children: [
                  Text('Technical details',
                      style: t.text.bodySmallStyle
                          .copyWith(color: t.surface.onBaseMuted)),
                  const Spacer(),
                  Icon(
                      _tech
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: t.surface.onBaseMuted),
                ],
              ),
            ),
          ),
          if (_tech) ...[
            _mono(t, 'Device ID', _d.id),
            // Where the device sits. Technical because acting on it means
            // knowing the other device's id — the reason it is worth showing
            // is that twenty things going offline together usually have one
            // cause, and this names it.
            if (_d.parentDeviceId != null)
              _mono(t, 'Behind', _d.parentDeviceId!),
            if (_d.canonicalName != null)
              _mono(t, 'Canonical', _d.canonicalName!),
            _mono(t, 'Plugin', _d.pluginId),
            SizedBox(height: t.space.sm),
          ],
          Divider(height: 1, color: t.stroke.hairline),
          SizedBox(height: t.space.md),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _remove,
              icon:
                  Icon(Icons.delete_outline, size: 16, color: t.accent.danger),
              label: Text('Remove device',
                  style: TextStyle(
                      color: t.accent.danger, fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(HcTokens t, String key, String value,
      {VoidCallback? onEdit, String actionLabel = 'edit'}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xs + 1),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(key,
                style: t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted)),
          ),
          Expanded(
            child: Text(value,
                style: t.text.bodyStyle.copyWith(color: t.surface.onBase)),
          ),
          if (onEdit != null)
            GestureDetector(
              onTap: onEdit,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(actionLabel,
                    style: t.text.bodySmallStyle.copyWith(
                        fontWeight: FontWeight.w600, color: t.accent.active)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _mono(HcTokens t, String key, String value) => Padding(
        padding: EdgeInsets.symmetric(vertical: t.space.xs),
        child: Row(
          children: [
            SizedBox(
                width: 76,
                child: Text(key,
                    style: t.text.bodySmallStyle
                        .copyWith(color: t.surface.onBaseMuted))),
            Expanded(
              child: Text(value,
                  style: t.text.captionStyle.copyWith(
                      color: t.surface.onBaseMuted,
                      fontFeatures: t.numericFontFeatures)),
            ),
          ],
        ),
      );

  Widget _editor(HcTokens t) {
    // Declared rooms as well as occupied ones — reading only the devices, which
    // is what this did, hid every empty room the Areas manager had just made.
    final areas = roomOptions(
      registered: ref.watch(areasProvider).value ?? const [],
      devices: ref.watch(devicesProvider).value ?? const [],
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Name', isDense: true),
            onSubmitted: (_) => _save(),
          ),
          SizedBox(height: t.space.sm),
          TextField(
            controller: _area,
            enabled: !_busy,
            decoration: const InputDecoration(
                labelText: 'Room', isDense: true, hintText: 'No room'),
            onSubmitted: (_) => _save(),
          ),
          if (areas.isNotEmpty) ...[
            SizedBox(height: t.space.sm),
            Wrap(
              spacing: t.space.xs,
              runSpacing: t.space.xs,
              children: [
                for (final a in areas)
                  ActionChip(
                    label: Text(a, style: t.text.bodySmallStyle),
                    onPressed: _busy ? null : () => _area.text = a,
                  ),
              ],
            ),
          ],
          SizedBox(height: t.space.md),
          Text('ICON',
              style:
                  t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(height: t.space.xs),
          Text(
            "The picture only. What the device *is* — and so what it lets you "
            'do — is set by its type, not by this.',
            style: t.text.captionStyle
                .copyWith(color: t.surface.onBaseMuted, height: 1.4),
          ),
          SizedBox(height: t.space.xs),
          _IconPicker(
            value: _icon,
            fallback: facetOf(_d, _d.schema),
            enabled: !_busy,
            onChanged: (f) => setState(() => _icon = f),
          ),
          if (_error != null) ...[
            SizedBox(height: t.space.sm),
            Text(_error!,
                style: t.text.bodySmallStyle.copyWith(color: t.accent.danger)),
          ],
          SizedBox(height: t.space.sm),
          Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed:
                    _busy ? null : () => setState(() => _editing = false),
                child: const Text('Cancel'),
              ),
              SizedBox(width: t.space.xs),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The automations that mention this device — the question you ask before
/// renaming or deleting something.
class _UsedBy extends ConsumerWidget {
  const _UsedBy({required this.device});
  final DeviceState device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final rules = ref.watch(automationsProvider).value ?? const [];
    final all = ref.watch(devicesProvider).value ?? const <DeviceState>[];

    final names = <String, String>{
      for (final d in all) ...{
        d.id: d.displayName,
        if (d.canonicalName != null) d.canonicalName!: d.displayName,
      },
    };
    String label(String ref) => names[ref] ?? ref;

    final refs = {
      device.id,
      if (device.canonicalName != null) device.canonicalName!
    };
    final using = rules.where((r) {
      final json = r.toJson().toString();
      return refs.any(json.contains);
    }).toList();

    if (using.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: t.space.sm),
        child: Text('Not used by any automation.',
            style:
                t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: t.space.xs),
        Text(
          using.length == 1
              ? 'USED BY 1 AUTOMATION'
              : 'USED BY ${using.length} AUTOMATIONS',
          style: t.text.captionStyle.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: t.surface.onBaseMuted),
        ),
        SizedBox(height: t.space.xs),
        for (final r in using)
          InkWell(
            onTap: () {
              Navigator.of(context).pop();
              context.push('/automations/${r.id}');
            },
            borderRadius: t.radius.smR,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: t.space.xs + 2),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: r.enabled
                          ? t.accent.success
                          : t.surface.onBaseMuted.withValues(alpha: 0.5),
                    ),
                  ),
                  SizedBox(width: t.space.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.text.bodyStyle
                                .copyWith(color: t.surface.onBase)),
                        Text(
                          triggerSentence(r.trigger, label: label) ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.text.captionStyle
                              .copyWith(color: t.surface.onBaseMuted),
                        ),
                      ],
                    ),
                  ),
                  Icon(HcIcons.caretRight,
                      size: 12, color: t.surface.onBaseMuted),
                ],
              ),
            ),
          ),
        SizedBox(height: t.space.xs),
      ],
    );
  }
}

// ── History tab ───────────────────────────────────────────────────────────────

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab({required this.device});
  final DeviceState device;

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab> {
  static const _cap = 8;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final async = ref.watch(deviceHistoryProvider(widget.device.id));

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space.lg),
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, __) => Text('Could not load history.',
            style:
                t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted)),
        data: (entries) {
          if (entries.isEmpty) {
            return Text('No recent changes.',
                style: t.text.bodySmallStyle
                    .copyWith(color: t.surface.onBaseMuted));
          }

          // Every numeric metric with enough points gets its own vibrant chart,
          // its own colour — a temp/humidity/lux multisensor shows all three.
          final metrics = _chartableMetrics(entries);
          final recent = [
            for (final e in entries)
              if (!_isMetadata(e.attribute) && !_isAdvancedAttr(e.attribute)) e
          ]..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
          final shown = _expanded ? recent : recent.take(_cap).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final attr in metrics) ...[
                _metricLabel(t, attr, entries),
                SizedBox(height: t.space.sm),
                HcHistoryChart(
                  entries: entries
                      .where((e) => e.attribute == attr && e.value is num)
                      .toList(),
                  height: 112,
                  color: _metricColor(t, attr),
                ),
                SizedBox(height: t.space.md),
              ],
              Text('RECENT CHANGES',
                  style: t.text.overlineStyle.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: t.surface.onBaseMuted)),
              SizedBox(height: t.space.xs),
              for (final e in shown)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: t.space.xs + 1),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_metricName(e.attribute)} → '
                          '${_readingValue(widget.device, e.attribute, e.value)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.text.bodySmallStyle
                              .copyWith(color: t.surface.onBase),
                        ),
                      ),
                      SizedBox(width: t.space.sm),
                      Text(_ago(e.recordedAt),
                          style: t.text.captionStyle.copyWith(
                              color: t.surface.onBaseMuted,
                              fontFeatures: t.numericFontFeatures)),
                    ],
                  ),
                ),
              if (!_expanded && recent.length > _cap)
                Padding(
                  padding: EdgeInsets.only(top: t.space.sm),
                  child: GestureDetector(
                    onTap: () => setState(() => _expanded = true),
                    behavior: HitTestBehavior.opaque,
                    child: Text('Show all ${recent.length} changes',
                        style: t.text.bodySmallStyle.copyWith(
                            fontWeight: FontWeight.w600,
                            color: t.accent.active)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _metricLabel(HcTokens t, String attr, List<HistoryEntry> entries) {
    HistoryEntry? latest;
    for (final e in entries) {
      if (e.attribute == attr && e.value is num) {
        if (latest == null || e.recordedAt.isAfter(latest.recordedAt)) {
          latest = e;
        }
      }
    }
    final c = _metricColor(t, attr);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        SizedBox(width: t.space.sm),
        Text(_metricName(attr).toUpperCase(),
            style: t.text.overlineStyle.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: t.surface.onBaseMuted)),
        const Spacer(),
        if (latest != null)
          Text(_readingValue(widget.device, attr, latest.value),
              style: t.text.bodyStyle.copyWith(
                  fontWeight: FontWeight.w700,
                  color: c,
                  fontFeatures: t.numericFontFeatures)),
      ],
    );
  }
}

// ── Shared bits ───────────────────────────────────────────────────────────────

String _readable(Object? v) => switch (v) {
      true => 'on',
      false => 'off',
      null => '—',
      _ => '$v',
    };

String _ago(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

class _Reading extends StatelessWidget {
  const _Reading({required this.name, required this.value});
  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xs),
      child: Row(
        children: [
          Text(name.replaceAll('_', ' '),
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted)),
          const Spacer(),
          Text(value,
              style: t.text.bodyStyle.copyWith(
                  color: t.surface.onBase,
                  fontFeatures: t.numericFontFeatures)),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      margin: EdgeInsets.fromLTRB(t.space.lg, 0, t.space.lg, t.space.sm),
      padding: EdgeInsets.all(t.space.sm + 2),
      decoration: BoxDecoration(
        color: t.accent.warn.withValues(alpha: 0.10),
        borderRadius: t.radius.smR,
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: t.accent.warn),
          SizedBox(width: t.space.sm),
          Expanded(
            child: Text(message,
                style: t.text.bodySmallStyle.copyWith(color: t.accent.warn)),
          ),
        ],
      ),
    );
  }
}

// The metrics worth trending, best-first.
const _metricPriority = <String>[
  'temperature',
  'current_temperature',
  'humidity',
  'illuminance_lux',
  'illuminance',
  'co2',
  'pm25',
  'pressure',
  'power',
  'setpoint',
  'battery',
];

/// Numeric metrics worth charting, best-first — priority metrics ahead of the
/// rest — and capped so a chatty device doesn't become a wall of charts.
List<String> _chartableMetrics(List<HistoryEntry> entries) {
  final counts = <String, int>{};
  for (final e in entries) {
    if (e.value is num &&
        !_isAdvancedAttr(e.attribute) &&
        !_isMetadata(e.attribute)) {
      counts[e.attribute] = (counts[e.attribute] ?? 0) + 1;
    }
  }
  final withHistory =
      counts.entries.where((e) => e.value >= 2).map((e) => e.key).toSet();
  final ordered = <String>[
    for (final m in _metricPriority)
      if (withHistory.contains(m)) m,
    for (final a in withHistory)
      if (!_metricPriority.contains(a)) a,
  ];
  return ordered.take(4).toList();
}

/// A vibrant, distinct colour per metric so a multisensor's charts read apart.
Color _metricColor(HcTokens t, String attr) {
  final a = attr.toLowerCase();
  if (a.contains('temp')) return const Color(0xFFFF8A5B); // warm orange
  if (a.contains('humid')) return const Color(0xFF4CC9F0); // cyan
  if (a.contains('illumin') || a.contains('lux')) {
    return const Color(0xFFFFD166); // amber-yellow
  }
  if (a.contains('co2')) return const Color(0xFF6FD1A6); // green
  if (a.contains('pm2')) return const Color(0xFFB98BFF); // violet
  if (a.contains('pressure')) return const Color(0xFF7CC4FF); // blue
  if (a.contains('power') || a.contains('watt')) return t.accent.active;
  if (a.contains('batt')) return const Color(0xFF6FD1A6); // green
  if (a.contains('bright')) return const Color(0xFFFFD166);
  return t.accent.primary;
}

/// A metric name without its unit suffix, humanized: `humidity_pct` → Humidity.
String _metricName(String attr) {
  var s = attr;
  for (final suffix in const ['_pct', '_lux', '_f', '_c']) {
    if (s.endsWith(suffix)) {
      s = s.substring(0, s.length - suffix.length);
      break;
    }
  }
  return humanize(s);
}

/// A best-effort unit for a numeric metric, for a humanized reading.
String _unit(String attr) {
  final a = attr.toLowerCase();
  if (a.endsWith('_pct') || a.contains('humid') || a.contains('batt')) {
    return '%';
  }
  if (a.contains('temp')) return '°';
  if (a.contains('lux') || a.contains('illumin')) return ' lux';
  if (a.contains('power') || a.contains('watt')) return ' W';
  return '';
}

/// Attributes that are plumbing, not readings — a unit field belongs *on* the
/// value it describes, and ids/kinds aren't something a person reads.
bool _isMetadata(String key) {
  final k = key.toLowerCase();
  return k.endsWith('_unit') ||
      const {
        'name',
        'kind',
        'bridge_id',
        'resource_id',
        'group_rid',
        'group_name',
        'group_kind',
      }.contains(k);
}

/// Z-wave (and similar) command-class dumps — `cc134_applicationversion`,
/// `cc99_usercode_pk7` — real data, but noise the drawer folds behind "Advanced"
/// and keeps out of the charts and change log.
final _ccAttr = RegExp(r'^cc\d+_');
bool _isAdvancedAttr(String key) => _ccAttr.hasMatch(key);

/// A reading said the human way, with its unit folded in — temperature carries
/// the device's own `°F`/`°C` when it reports one.
String _readingValue(DeviceState d, String key, Object? value) {
  if (value is! num) return _readable(value);
  if (key.toLowerCase().contains('temp')) {
    final u = d.state['temperature_unit'];
    return '${_readable(value)}°${u is String && u.isNotEmpty ? u : ''}';
  }
  return '${_readable(value)}${_unit(key)}';
}

/// The icons a device can wear.
///
/// Drawn from the facets, so every option already has artwork the skin reaches
/// — there is no second icon set to keep in step, and adding a facet adds an
/// option for free.
///
/// The first entry is *not* an icon: it is "whatever the device is", which is
/// the state every device starts in and the one you need a way back to.
class _IconPicker extends StatelessWidget {
  const _IconPicker({
    required this.value,
    required this.fallback,
    required this.enabled,
    required this.onChanged,
  });

  final DeviceFacet? value;

  /// What the device would show with no override, so "Automatic" can show it
  /// rather than a question mark.
  final DeviceFacet fallback;
  final bool enabled;
  final ValueChanged<DeviceFacet?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    Widget cell(DeviceFacet? facet, IconData icon, String tooltip) {
      final chosen = facet == value;
      return Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          selected: chosen,
          label: tooltip,
          child: GestureDetector(
            onTap: enabled ? () => onChanged(facet) : null,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: chosen ? t.surface.raised : null,
                borderRadius: BorderRadius.circular(t.radius.sm),
                border: Border.all(
                  color: chosen ? t.accent.active : t.stroke.hairline,
                  width: t.stroke.width,
                ),
              ),
              child: Icon(icon,
                  size: 18,
                  color: chosen ? t.accent.active : t.surface.onBaseMuted),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: t.space.xs,
      runSpacing: t.space.xs,
      children: [
        cell(null, HcIcons.forFacet(fallback), 'Automatic'),
        for (final facet in DeviceFacet.values)
          if (facet != DeviceFacet.unknown)
            cell(facet, HcIcons.forFacet(facet), humanize(facet.iconKey)),
      ],
    );
  }
}
