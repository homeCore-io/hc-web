import 'package:flutter/material.dart';

import '../../../core/devices/presentation.dart';
import '../../../core/models/device_state.dart';
import '../../../core/schema/attribute_policy.dart';
import '../../../core/text/humanize.dart';
import '../../../design/tokens.dart';
import 'device_picker_shell.dart';
import 'rule_refs.dart';

/// Choosing a device, on the same shell every other picker uses.
///
/// The chip editors used a `DropdownButtonFormField` over every device the hub
/// knows — no search, no rooms, no live state, in registration order. On a real
/// house that is a full-height list of a hundred-odd entries mixing modes,
/// timers, sensors and speakers, and picking the right one means reading all of
/// them. The three "add a node" flows were given the searchable, room-grouped
/// shell; *editing* an existing node was left on the dropdown, so the same rule
/// was authored through one interface and edited through another.
///
/// This is that shell with the detail pane dropped: rail + list, nothing new.

/// What a device is doing right now, in the words its plugin uses.
///
/// **Not a hard-coded convention.** The previous version of this read
/// `state['contact'] == true` as "closed", which is the usual meaning of a
/// contact circuit and the *opposite* of what hc-yolink and hc-isy publish —
/// both set `contact` equal to `open`, so `true` means the door is open. A
/// chip that says "closed" over an open door is worse than no chip.
///
/// So the label comes from the attribute's declared [BoolStates] where the
/// plugin gave them, and from the client lexicon otherwise.
(String?, PickerTone?) deviceLiveChip(DeviceState d) {
  const interesting = [
    ('open', PickerTone.on, PickerTone.off),
    ('contact', PickerTone.on, PickerTone.off),
    ('motion', PickerTone.on, PickerTone.off),
    ('occupancy', PickerTone.on, PickerTone.off),
    ('leak', PickerTone.on, PickerTone.off),
    ('locked', PickerTone.ok, PickerTone.on),
    ('on', PickerTone.on, PickerTone.off),
  ];

  for (final (name, whenTrue, whenFalse) in interesting) {
    final value = d.state[name];
    if (value is! bool) continue;
    final states = boolStatesFor(name, d.schema?[name]);
    if (states == null) continue;
    return (states[value].label, value ? whenTrue : whenFalse);
  }

  // A media player says what it is doing rather than nothing at all.
  final playback = d.state['state'];
  if (playback is String && playback.isNotEmpty) {
    return (playback, playback == 'playing' ? PickerTone.play : PickerTone.off);
  }
  return (null, null);
}

/// One device, flattened for the list.
class _Row {
  _Row(this.device, this.ref)
      : label = device.displayName,
        sub = device.canonicalName ?? device.id,
        room = (device.effectiveArea?.isNotEmpty ?? false)
            ? humanize(device.effectiveArea)
            : 'No room',
        facet = facetOf(device, device.schema);

  final DeviceState device;
  final String ref;
  final String label;
  final String sub;
  final String room;
  final DeviceFacet facet;
}

/// Open the device picker. Returns the chosen reference, or null if cancelled.
///
/// [current] is the reference the field already holds; it opens pre-selected so
/// "which one is this?" is answered without reading the list.
Future<String?> pickDeviceRef(
  BuildContext context, {
  required RuleRefs refs,
  String? current,
  String kicker = 'Choose a device',
  String title = 'Which device?',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _DeviceChoicePicker(
      refs: refs,
      current: current,
      kicker: kicker,
      title: title,
    ),
  );
}

class _DeviceChoicePicker extends StatefulWidget {
  const _DeviceChoicePicker({
    required this.refs,
    required this.current,
    required this.kicker,
    required this.title,
  });

  final RuleRefs refs;
  final String? current;
  final String kicker;
  final String title;

  @override
  State<_DeviceChoicePicker> createState() => _DeviceChoicePickerState();
}

class _DeviceChoicePickerState extends State<_DeviceChoicePicker> {
  bool _byRoom = false;
  String _cat = 'all';
  String _room = '';
  String _query = '';
  String? _selected;

  late final List<_Row> _rows = [
    for (final d in widget.refs.devices) _Row(d, _refFor(d)),
  ];

  /// The reference to store for a device.
  ///
  /// Keyed on the form the rule already uses: core accepts a raw `device_id`
  /// or a `canonical_name`, and rewriting one into the other on a field the
  /// user did not touch is a silent change to their rule.
  String _refFor(DeviceState d) {
    final c = widget.current;
    if (c != null && (d.id == c || d.canonicalName == c)) return c;
    return widget.refs.refFor(d);
  }

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
    // The current device is pre-SELECTED, but the list is not narrowed to its
    // category. Opening filtered to "Sensors" because the field happens to
    // hold a door sensor hides every light in the house — which is the same
    // "you cannot see what you want" problem the flat dropdown had, just with
    // a different shape. Retargeting across categories is the common reason to
    // open this at all.
    final at = _rows.where((r) => r.ref == widget.current).firstOrNull;
    if (at != null) _room = at.room;
  }

  static String _bucketOf(DeviceFacet f) => switch (f) {
        DeviceFacet.light ||
        DeviceFacet.dimmableLight ||
        DeviceFacet.colorLight =>
          'light',
        DeviceFacet.switch_ || DeviceFacet.outlet || DeviceFacet.siren =>
          'switch',
        DeviceFacet.cover || DeviceFacet.garage => 'cover',
        DeviceFacet.lock => 'lock',
        DeviceFacet.climate => 'climate',
        DeviceFacet.mediaPlayer => 'media',
        DeviceFacet.button => 'button',
        _ => 'sensor',
      };

  static const _cats = [
    PickerCat('all', 'All devices', Icons.list_alt_outlined, 'Quick'),
    PickerCat('light', 'Lights', Icons.lightbulb_outline, 'Controls'),
    PickerCat(
        'switch', 'Switches & Outlets', Icons.toggle_on_outlined, 'Controls'),
    PickerCat('cover', 'Shades & Covers', Icons.blinds_outlined, 'Controls'),
    PickerCat('lock', 'Locks', Icons.lock_outline, 'Controls'),
    PickerCat('climate', 'Climate', Icons.hvac_outlined, 'Controls'),
    PickerCat('media', 'Media players', Icons.speaker_outlined, 'Controls'),
    PickerCat('button', 'Keypads & Remotes', Icons.dialpad_outlined, 'Read'),
    PickerCat('sensor', 'Sensors', Icons.sensors, 'Read'),
  ];

  List<_Row> get _pool {
    var p = _rows.where((r) {
      if (_byRoom) return r.room == _room;
      if (_cat == 'all') return true;
      return _bucketOf(r.facet) == _cat;
    });
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      p = p.where((r) =>
          r.label.toLowerCase().contains(q) || r.sub.toLowerCase().contains(q));
    }
    final out = p.toList();
    out.sort((a, b) {
      if (!_byRoom && a.room != b.room) return a.room.compareTo(b.room);
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return out;
  }

  List<String> get _rooms {
    final rs = _rows.map((r) => r.room).toSet().toList()..sort();
    return rs;
  }

  int _countFor(String cat) =>
      _rows.where((r) => cat == 'all' || _bucketOf(r.facet) == cat).length;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final pool = _pool;

    return PickerPanel(
      // Two panes, so it asks for less than the three-pane default rather
      // than stretching a rail and a list across a desktop's full width.
      width: 880,
      height: 480,
      kicker: widget.kicker,
      title: widget.title,
      seg: pickerSeg(t, byRoom: _byRoom, onChanged: (v) {
        setState(() {
          _byRoom = v;
          if (v && _room.isEmpty) _room = _rooms.isEmpty ? '' : _rooms.first;
        });
      }),
      footerHint: _selected == null
          ? '${_rows.length} devices'
          : widget.refs.labelFor(_selected!),
      primaryLabel: 'Use this device',
      onPrimary: _selected == null
          ? null
          : () => Navigator.pop(context, _selected),
      panes: [
        PickerPane(width: 220, compactLabel: 'Where', child: _rail(t)),
        PickerPane(
          compactLabel: 'Device',
          child: PickerDeviceList(
            onQuery: (q) => setState(() => _query = q),
            rows: _list(t, pool),
            empty: pool.isEmpty,
          ),
        ),
      ],
    );
  }

  Widget _rail(HcTokens t) {
    if (_byRoom) {
      return PickerRail(
        note: 'Rooms come from each device’s canonical name.',
        children: [
          pickerGroupLabel(t, 'Rooms'),
          for (final r in _rooms)
            pickerRailRow(
              t,
              label: r,
              icon: Icons.meeting_room_outlined,
              count: _rows.where((x) => x.room == r).length,
              selected: _room == r,
              onTap: () => setState(() => _room = r),
            ),
        ],
      );
    }
    final groups = <String, List<PickerCat>>{};
    for (final c in _cats) {
      groups.putIfAbsent(c.group, () => []).add(c);
    }
    return PickerRail(
      children: [
        for (final entry in groups.entries) ...[
          pickerGroupLabel(t, entry.key),
          for (final c in entry.value)
            pickerRailRow(
              t,
              label: c.label,
              icon: c.icon,
              count: _countFor(c.key),
              selected: _cat == c.key,
              onTap: () => setState(() => _cat = c.key),
            ),
        ],
      ],
    );
  }

  List<Widget> _list(HcTokens t, List<_Row> pool) {
    final out = <Widget>[];
    String? room;
    for (final r in pool) {
      // Room headers only where the list is not already one room deep.
      if (!_byRoom && r.room != room) {
        room = r.room;
        out.add(pickerGroupLabel(t, room));
      }
      final (chip, tone) = deviceLiveChip(r.device);
      out.add(pickerDeviceRow(
        t,
        icon: r.facet.icon,
        label: r.label,
        sub: r.sub,
        chip: r.device.available ? chip : 'offline',
        chipTone: r.device.available ? tone : null,
        selected: _selected == r.ref,
        onTap: () => setState(() => _selected = r.ref),
      ));
    }
    return out;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
