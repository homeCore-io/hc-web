import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/text/humanize.dart';
import '../../core/api/history_api.dart';
import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/models/history_entry.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/automations_provider.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/components/hc_attribute_control.dart';
import '../../design/components/hc_controls.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/components/hc_history_chart.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../../shell/hc_sheet.dart';
import '../automations/rule_phrasing.dart';

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
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).valueOrNull ?? const [];
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
          Padding(
            padding: EdgeInsets.fromLTRB(t.space.lg, t.space.xs, t.space.lg, 0),
            child: _Segmented(
              index: _tab,
              labels: const ['Control', 'Info', 'History'],
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          SizedBox(height: t.space.md),
          switch (_tab) {
            0 => _Controls(device: device),
            1 => _InfoTab(device: device),
            _ => _HistoryTab(device: device),
          },
          SizedBox(height: t.space.lg),
        ],
      ),
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
    final String stateWord;
    final Color stateColor;
    if (!device.available) {
      stateWord = 'Offline';
      stateColor = t.accent.offline;
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
              borderRadius: BorderRadius.circular(13),
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
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: t.surface.onBase,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (room != null) ...[
                      Flexible(
                        child: Text(room,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5, color: t.surface.onBaseMuted)),
                      ),
                      Text(' · ',
                          style: TextStyle(
                              fontSize: 12.5, color: t.surface.onBaseMuted)),
                    ],
                    Text(stateWord,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: stateColor)),
                  ],
                ),
              ],
            ),
          ),
          if (facet.isActuator && device.available)
            Padding(
              padding: EdgeInsets.only(top: t.space.sm, right: t.space.xs),
              child: HcToggle(
                value: on,
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

// ── Segmented control ─────────────────────────────────────────────────────────

class _Segmented extends StatelessWidget {
  const _Segmented(
      {required this.index, required this.labels, required this.onChanged});
  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: index == i ? t.surface.overlay : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(labels[i],
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: index == i
                              ? t.surface.onBase
                              : t.surface.onBaseMuted)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Control tab ───────────────────────────────────────────────────────────────

/// Every writable attribute the device declares, as the control its kind calls
/// for. `on` already has the header toggle, so it is not repeated. A device with
/// no schema falls back to plainly-worded readings.
class _Controls extends ConsumerWidget {
  const _Controls({required this.device});
  final DeviceState device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final schema = device.schema;
    final notifier = ref.read(devicesProvider.notifier);

    if (schema == null || schema.attributes.isEmpty) {
      if (device.state.isEmpty) {
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space.lg),
          child: Text('No adjustable settings.',
              style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted)),
        );
      }
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: t.space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in device.state.entries)
              if (!_isMetadata(e.key))
                _Reading(
                  name: _metricName(e.key),
                  value: _readingValue(device, e.key, e.value),
                ),
          ],
        ),
      );
    }

    final entries =
        schema.attributes.entries.where((e) => e.key != 'on').toList();

    if (entries.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: t.space.lg),
        child: Text('No adjustable settings beyond power.',
            style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted)),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in entries)
            Padding(
              padding: EdgeInsets.only(bottom: t.space.md),
              child: HcAttributeControl(
                name: e.key,
                schema: e.value,
                value: device.state[e.key],
                enabled: device.available,
                onCommit: e.value.writable
                    ? (v) => notifier.command(device.id, {e.key: v})
                    : null,
              ),
            ),
        ],
      ),
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

  DeviceState get _d => widget.device;

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    super.dispose();
  }

  String get _currentArea =>
      _d.effectiveArea != null ? humanize(_d.effectiveArea!) : '';

  void _start() => setState(() {
        _editing = true;
        _error = null;
        _name.text = _d.displayName;
        _area.text = _currentArea;
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
    if (body.isEmpty) {
      setState(() => _editing = false);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(devicesProvider.notifier).updateDevice(_d.id, body);
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
                      style: TextStyle(
                          fontSize: 12.5, color: t.surface.onBaseMuted)),
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
                style: TextStyle(fontSize: 13, color: t.surface.onBaseMuted)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 13, color: t.surface.onBase)),
          ),
          if (onEdit != null)
            GestureDetector(
              onTap: onEdit,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(actionLabel,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: t.accent.active)),
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
                    style:
                        TextStyle(fontSize: 12, color: t.surface.onBaseMuted))),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: t.surface.onBaseMuted,
                      fontFeatures: t.numericFontFeatures)),
            ),
          ],
        ),
      );

  Widget _editor(HcTokens t) {
    final areas = (ref.watch(devicesProvider).valueOrNull ?? const [])
        .map((d) => d.effectiveArea)
        .whereType<String>()
        .map(humanize)
        .toSet()
        .toList()
      ..sort();

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
                    label: Text(a, style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy ? null : () => _area.text = a,
                  ),
              ],
            ),
          ],
          if (_error != null) ...[
            SizedBox(height: t.space.sm),
            Text(_error!,
                style: TextStyle(fontSize: 12, color: t.accent.danger)),
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
    final rules = ref.watch(automationsProvider).valueOrNull ?? const [];
    final all = ref.watch(devicesProvider).valueOrNull ?? const <DeviceState>[];

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
            style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted)),
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
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
            color: t.surface.onBaseMuted,
          ),
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
                            style: TextStyle(
                                fontSize: 13, color: t.surface.onBase)),
                        Text(
                          triggerSentence(r.trigger, label: label) ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5, color: t.surface.onBaseMuted),
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
    final async = ref.watch(_sheetHistoryProvider(widget.device.id));

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space.lg),
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, __) => Text('Could not load history.',
            style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted)),
        data: (entries) {
          if (entries.isEmpty) {
            return Text('No recent changes.',
                style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted));
          }

          // Every numeric metric with enough points gets its own vibrant chart,
          // its own colour — a temp/humidity/lux multisensor shows all three.
          final metrics = _chartableMetrics(entries);
          final recent = [
            for (final e in entries)
              if (!_isMetadata(e.attribute)) e
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
                  style: TextStyle(
                      fontSize: 10,
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
                          style: TextStyle(
                              fontSize: 12.5, color: t.surface.onBase),
                        ),
                      ),
                      SizedBox(width: t.space.sm),
                      Text(_ago(e.recordedAt),
                          style: TextStyle(
                              fontSize: 11,
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
                        style: TextStyle(
                            fontSize: 12.5,
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
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: t.surface.onBaseMuted)),
        const Spacer(),
        if (latest != null)
          Text(_readingValue(widget.device, attr, latest.value),
              style: TextStyle(
                  fontSize: 13,
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
              style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
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
                style: TextStyle(fontSize: 12, color: t.accent.warn)),
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

final _sheetHistoryProvider =
    FutureProvider.family.autoDispose<List<HistoryEntry>, String>((ref, id) {
  final client = ref.watch(homecoreClientProvider);
  return HistoryApi(client).getHistory(id, limit: 500);
});

/// Numeric metrics worth charting, best-first — priority metrics ahead of the
/// rest — and capped so a chatty device doesn't become a wall of charts.
List<String> _chartableMetrics(List<HistoryEntry> entries) {
  final counts = <String, int>{};
  for (final e in entries) {
    if (e.value is num) counts[e.attribute] = (counts[e.attribute] ?? 0) + 1;
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
        'kind',
        'bridge_id',
        'resource_id',
        'group_rid',
        'group_name',
        'group_kind',
      }.contains(k);
}

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
