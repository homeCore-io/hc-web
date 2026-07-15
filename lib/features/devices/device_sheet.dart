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
import '../../design/components/hc_history_chart.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../../shell/hc_sheet.dart';
import '../automations/rule_phrasing.dart';

/// A device, laid over the house rather than replacing it.
///
/// Shows what you actually came for: the controls, the live state, and — the
/// part no page offered before — *which automations depend on this device*.
/// That last one is the question you ask right before you rename or delete
/// something, and answering it anywhere other than here means going and looking
/// through 42 rules by hand.
///
/// The full 872-line detail page still exists behind "Open full detail". This is
/// not a replacement for it; it is the 90% you wanted without leaving home.
Future<void> showDeviceSheet(BuildContext context, String deviceId) =>
    showHcSheet<void>(
      context,
      title: 'Device',
      child: _DeviceSheet(deviceId: deviceId),
    );

class _DeviceSheet extends ConsumerWidget {
  const _DeviceSheet({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).valueOrNull ?? const [];
    final device =
        devices.where((d) => d.id == deviceId).cast<DeviceState?>().firstOrNull;

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
          _Identity(device: device),

          if (!device.available)
            const _Banner(
              icon: HcIcons.offline,
              message: 'This device is offline. Commands will not reach it.',
            ),

          // Controls come from the device's own schema, so a plugin that adds an
          // attribute gets a correct control for free — no per-device UI code.
          _Controls(device: device),

          // A number is a fact; a number over the last day is a story. Sensors
          // get their trend inline, not one route away.
          _SheetHistory(device: device),

          _UsedBy(device: device),

          Padding(
            padding: EdgeInsets.fromLTRB(
                t.space.lg, t.space.sm, t.space.lg, t.space.lg),
            child: Row(
              children: [
                TextButton.icon(
                  icon: const Icon(HcIcons.clock, size: 14),
                  label: const Text('History'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/devices/${device.id}/history');
                  },
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/devices/${device.id}');
                  },
                  child: const Text('Open full detail'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The sheet's head: the device's name and where it lives, its power toggle, and
/// — the part that was a whole separate page before — a pencil that turns the
/// name and room into fields you edit right here. A device that arrives named
/// `hue-001788ff` is the reason: you rename it once, in the place you found it,
/// and it is that name everywhere after.
class _Identity extends ConsumerStatefulWidget {
  const _Identity({required this.device});

  final DeviceState device;

  @override
  ConsumerState<_Identity> createState() => _IdentityState();
}

class _IdentityState extends ConsumerState<_Identity> {
  bool _editing = false;
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

  String get _currentArea => _d.area != null ? humanize(_d.area!) : '';

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
    // Areas are stored as snake_case keys and shown humanized, so compare the
    // typed text against the humanized current value; core re-normalizes what we
    // send, so a human "Family Room" lands on the existing `family_room`.
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

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return _editing ? _editor(t) : _display(t);
  }

  Widget _display(HcTokens t) {
    final facet = facetOf(_d, _d.schema);
    final on = _d.available && isOn(_d);
    return Padding(
      padding:
          EdgeInsets.fromLTRB(t.space.lg, t.space.md, t.space.sm, t.space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _d.displayName,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: t.surface.onBase,
                        ),
                      ),
                    ),
                    SizedBox(width: t.space.xs),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 26, height: 26),
                      iconSize: 13,
                      color: t.surface.onBaseMuted,
                      tooltip: 'Rename',
                      icon: const Icon(HcIcons.pencil),
                      onPressed: _start,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (_d.area != null) humanize(_d.area!),
                    if (_d.deviceType != null) humanize(_d.deviceType!),
                    if (!_d.available) 'offline',
                  ].join(' · '),
                  style:
                      TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted),
                ),
              ],
            ),
          ),
          if (facet.isActuator && _d.available)
            Padding(
              padding: EdgeInsets.only(top: t.space.xs),
              child: HcToggle(
                value: on,
                semanticLabel: _d.displayName,
                onChanged: (v) => ref
                    .read(devicesProvider.notifier)
                    .command(_d.id, {'on': v}),
              ),
            ),
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

  Widget _editor(HcTokens t) {
    // Rooms already in use, humanized, so a rename lands things in the same room
    // rather than a snake_case twin.
    final areas = (ref.watch(devicesProvider).valueOrNull ?? const [])
        .map((d) => d.area)
        .whereType<String>()
        .map(humanize)
        .toSet()
        .toList()
      ..sort();

    return Padding(
      padding:
          EdgeInsets.fromLTRB(t.space.lg, t.space.md, t.space.lg, t.space.sm),
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

/// Every writable attribute the device declares, as the control its kind calls
/// for. Read-only attributes are shown as values rather than hidden — a sensor
/// with nothing to twiddle still has something to say.
class _Controls extends ConsumerWidget {
  const _Controls({required this.device});

  final DeviceState device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final schema = device.schema;
    final notifier = ref.read(devicesProvider.notifier);

    if (schema == null || schema.attributes.isEmpty) {
      // No schema is not an error — most plugins do not ship one. Fall back to
      // whatever state the device is actually reporting.
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: t.space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in device.state.entries)
              _Reading(name: e.key, value: _readable(e.value)),
          ],
        ),
      );
    }

    // `on` already has the toggle in the header; repeating it here would be two
    // controls for one fact, which is how they end up disagreeing.
    final entries =
        schema.attributes.entries.where((e) => e.key != 'on').toList();

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

/// The automations that mention this device.
///
/// This is the question you ask before renaming or deleting something, and until
/// now the only way to answer it was to read 42 rules by hand.
class _UsedBy extends ConsumerWidget {
  const _UsedBy({required this.device});

  final DeviceState device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final rules = ref.watch(automationsProvider).valueOrNull ?? const [];
    final all = ref.watch(devicesProvider).valueOrNull ?? const <DeviceState>[];

    // Without this the sentence reads "the yolink_d88b4c0400064299 closes".
    // A rule may name a device by raw id OR canonical name, so index both.
    final names = <String, String>{
      for (final d in all) ...{
        d.id: d.displayName,
        if (d.canonicalName != null) d.canonicalName!: d.displayName,
      },
    };
    String label(String ref) => names[ref] ?? ref;

    // A rule may refer to a device by its raw id OR its canonical name — core's
    // resolver accepts both — so match on either, or the count silently lies.
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
        padding: EdgeInsets.fromLTRB(t.space.lg, 0, t.space.lg, t.space.md),
        child: Text(
          'No automations use this device.',
          style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted),
        ),
      );
    }

    return Padding(
      padding:
          EdgeInsets.fromLTRB(t.space.lg, t.space.sm, t.space.lg, t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          SizedBox(height: t.space.sm),
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
                          Text(
                            r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: t.surface.onBase,
                            ),
                          ),
                          Text(
                            triggerSentence(r.trigger, label: label) ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: t.surface.onBaseMuted,
                            ),
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
        ],
      ),
    );
  }
}

/// A raw state value, said the way a person would say it.
///
/// `on: false` is not a reading, it is a field dump — the same habit the rule
/// sentences exist to kill.
String _readable(Object? v) => switch (v) {
      true => 'on',
      false => 'off',
      null => '—',
      _ => '$v',
    };

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
          Text(
            name.replaceAll('_', ' '),
            style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: t.surface.onBase,
              fontFeatures: t.numericFontFeatures,
            ),
          ),
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
      margin: EdgeInsets.fromLTRB(t.space.lg, 0, t.space.lg, t.space.md),
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
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: t.accent.warn),
            ),
          ),
        ],
      ),
    );
  }
}

/// The metrics worth trending, in the order we'd rather show them. A device may
/// report several numbers; this picks the one a person came to see.
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

bool _isMetric(String attr, Object? value) =>
    value is num && (_metricPriority.contains(attr) || attr.endsWith('_pct'));

/// True when the device exposes at least one number worth a chart — so we never
/// fire a history request for a plain on/off switch.
bool _hasMetric(DeviceState d) =>
    d.state.entries.any((e) => _isMetric(e.key, e.value));

final _sheetHistoryProvider =
    FutureProvider.family.autoDispose<List<HistoryEntry>, String>((ref, id) {
  final client = ref.watch(homecoreClientProvider);
  return HistoryApi(client).getHistory(id, limit: 500);
});

/// The recent trend for a device's primary metric, drawn inline in the sheet.
class _SheetHistory extends ConsumerWidget {
  const _SheetHistory({required this.device});

  final DeviceState device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    if (!_hasMetric(device)) return const SizedBox.shrink();

    final async = ref.watch(_sheetHistoryProvider(device.id));
    return async.when(
      loading: () => const SizedBox(height: 44),
      error: (_, __) => const SizedBox.shrink(),
      data: (entries) {
        final attr = _pickAttribute(entries);
        if (attr == null) return const SizedBox.shrink();
        final series = entries
            .where((e) => e.attribute == attr && e.value is num)
            .toList();
        if (series.length < 2) return const SizedBox.shrink();

        return Padding(
          padding: EdgeInsets.fromLTRB(
              t.space.lg, t.space.sm, t.space.lg, t.space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    attr.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: t.surface.onBaseMuted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'RECENT',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: t.surface.onBaseMuted.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              SizedBox(height: t.space.sm),
              HcHistoryChart(entries: series),
            ],
          ),
        );
      },
    );
  }

  /// The numeric attribute to chart: the highest-priority metric that actually
  /// has history, falling back to whichever numeric attribute has the most
  /// points.
  static String? _pickAttribute(List<HistoryEntry> entries) {
    final numericAttrs = <String, int>{};
    for (final e in entries) {
      if (e.value is num) {
        numericAttrs[e.attribute] = (numericAttrs[e.attribute] ?? 0) + 1;
      }
    }
    if (numericAttrs.isEmpty) return null;
    for (final metric in _metricPriority) {
      if (numericAttrs.containsKey(metric)) return metric;
    }
    return numericAttrs.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }
}
