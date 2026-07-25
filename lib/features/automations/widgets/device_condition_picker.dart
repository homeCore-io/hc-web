import 'package:flutter/material.dart';

import '../../../core/devices/presentation.dart';
import '../../../core/models/device_state.dart';
import '../../../core/rules/node.dart';
import '../../../design/tokens.dart';
import 'device_picker_shell.dart';
import 'editor_style.dart';
import 'rule_refs.dart';

/// The multi-pane "Check a device" picker for conditions — the condition-side
/// twin of `DeviceActionPicker`, on the same [PickerPanel] shell.
///
/// You pick a device (sensors **included** here — a condition is where they
/// belong) or a mode, then an attribute + comparison + value. Returns a
/// `DeviceState` / `ModeIs` condition node.
class DeviceConditionPicker extends StatefulWidget {
  const DeviceConditionPicker({super.key, required this.refs});

  final RuleRefs refs;

  @override
  State<DeviceConditionPicker> createState() => _DeviceConditionPickerState();
}

class _Entry {
  _Entry({
    required this.label,
    required this.ref,
    required this.sub,
    required this.icon,
    required this.bucket,
    required this.room,
    required this.attrs,
    this.device,
    this.isMode = false,
    this.chip,
    this.chipTone,
  });

  final String label;
  final String ref;
  final String sub;
  final IconData icon;
  final String bucket;
  final String room;
  final List<String> attrs; // comparable attribute names
  final DeviceState? device;
  final bool isMode;
  final String? chip;
  final PickerTone? chipTone;
}

const _cats = [
  PickerCat('all', 'All devices', Icons.list_alt_outlined, 'Quick'),
  PickerCat('light', 'Lights', Icons.lightbulb_outline, 'Controls'),
  PickerCat(
      'switch', 'Switches & Outlets', Icons.toggle_on_outlined, 'Controls'),
  PickerCat('cover', 'Shades & Covers', Icons.blinds_outlined, 'Controls'),
  PickerCat('lock', 'Locks', Icons.lock_outline, 'Controls'),
  PickerCat('climate', 'Climate', Icons.hvac_outlined, 'Controls'),
  PickerCat('media', 'Media players', Icons.speaker_outlined, 'Controls'),
  PickerCat('sensor', 'Sensors', Icons.sensors, 'Read'),
  PickerCat('mode', 'Modes', Icons.brightness_4_outlined, 'Hub'),
];

/// The comparison operators, in menu order, with the words the phrasing uses.
const _ops = [
  ('Eq', 'is'),
  ('Ne', 'is not'),
  ('Gt', 'is above'),
  ('Gte', 'is at least'),
  ('Lt', 'is below'),
  ('Lte', 'is at most'),
];

String _bucketOf(DeviceFacet f) => switch (f) {
      DeviceFacet.light ||
      DeviceFacet.dimmableLight ||
      DeviceFacet.colorLight =>
        'light',
      DeviceFacet.switch_ ||
      DeviceFacet.outlet ||
      DeviceFacet.siren =>
        'switch',
      DeviceFacet.cover || DeviceFacet.garage => 'cover',
      DeviceFacet.lock => 'lock',
      DeviceFacet.climate => 'climate',
      DeviceFacet.mediaPlayer => 'media',
      // Everything that mainly reports — doors, motion, leak, temp, humidity… —
      // is a sensor here, which is exactly what a condition wants.
      _ => 'sensor',
    };

class _DeviceConditionPickerState extends State<DeviceConditionPicker> {
  bool _byRoom = false;
  String _cat = 'all';
  String _room = '';
  String _query = '';

  _Entry? _sel;

  // Detail state.
  String _attr = '';
  String _op = 'Eq';
  String _valueText = 'true';
  bool _modeOn = true;

  late final List<_Entry> _entries = _buildEntries();

  // -- entries -------------------------------------------------------------

  List<_Entry> _buildEntries() {
    final out = <_Entry>[];
    for (final d in widget.refs.devices) {
      final facet = facetOf(d, d.schema);
      if (facet == DeviceFacet.scene) continue; // a scene has nothing to read
      final attrs = _comparableAttrs(d);
      if (attrs.isEmpty) continue;
      final (chip, tone) = _deviceChip(d);
      out.add(_Entry(
        label: d.displayName,
        ref: d.ruleReference,
        sub: d.canonicalName ?? d.id,
        icon: facet.icon,
        bucket: _bucketOf(facet),
        room: d.effectiveArea ?? 'No room',
        attrs: attrs,
        device: d,
        chip: chip,
        chipTone: tone,
      ));
    }
    for (final m in widget.refs.modes) {
      out.add(_Entry(
        label: m.name,
        ref: m.id,
        sub: m.id,
        icon: Icons.brightness_4_outlined,
        bucket: 'mode',
        room: 'Modes',
        attrs: const [],
        isMode: true,
      ));
    }
    return out;
  }

  /// Attribute names you can actually compare: scalar-valued only (a list like
  /// `available_favorites` or a map is not a comparison target).
  List<String> _comparableAttrs(DeviceState d) {
    final out = <String>[];
    for (final e in d.state.entries) {
      final v = e.value;
      if (v is bool || v is num || v is String) out.add(e.key);
    }
    out.sort();
    return out;
  }

  (String?, PickerTone?) _deviceChip(DeviceState d) {
    final s = d.state;
    if (s['contact'] == true) return ('closed', PickerTone.ok);
    if (s['contact'] == false) return ('open', PickerTone.on);
    if (s['motion'] == true) return ('motion', PickerTone.on);
    if (s['occupancy'] == true || s['occupied'] == true) {
      return ('occupied', PickerTone.on);
    }
    if (s['locked'] == true) return ('locked', PickerTone.ok);
    if (s['on'] == true) return ('on', PickerTone.on);
    if (s['on'] == false) return ('off', PickerTone.off);
    return (null, null);
  }

  // -- filtering -----------------------------------------------------------

  List<_Entry> get _pool {
    var p = _entries.where((e) {
      if (_byRoom) return e.room == _room;
      if (_cat == 'all') return !e.isMode;
      return e.bucket == _cat;
    });
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      p = p
          .where((e) => e.label.toLowerCase().contains(q) || e.sub.contains(q));
    }
    return p.toList()..sort(_byName);
  }

  int _byName(_Entry a, _Entry b) {
    if (!_byRoom && a.room != b.room) return a.room.compareTo(b.room);
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  }

  List<String> get _rooms {
    final rs = _entries
        .where((e) => !e.isMode)
        .map((e) => e.room)
        .toSet()
        .toList()
      ..sort();
    return [...rs, 'Modes'];
  }

  int _count(String cat) => cat == 'all'
      ? _entries.where((e) => !e.isMode).length
      : _entries.where((e) => e.bucket == cat).length;

  void _select(_Entry e) {
    setState(() {
      _sel = e;
      if (e.isMode) {
        _modeOn = true;
      } else {
        _attr = _defaultAttr(e);
        _op = 'Eq';
        _valueText = '${e.device!.state[_attr] ?? 'true'}';
      }
    });
  }

  String _defaultAttr(_Entry e) {
    for (final k in const [
      'on',
      'contact',
      'motion',
      'occupancy',
      'open',
      'locked',
      'state'
    ]) {
      if (e.attrs.contains(k)) return k;
    }
    return e.attrs.isEmpty ? '' : e.attrs.first;
  }

  HcNode? _result() {
    final e = _sel;
    if (e == null) return null;
    if (e.isMode) {
      return HcNode('ModeIs', {'mode_id': e.ref, 'on': _modeOn});
    }
    if (_attr.isEmpty) return null;
    return HcNode('DeviceState', {
      'device_id': e.ref,
      'attribute': _attr,
      'op': _op,
      'value': _parseValue(_valueText),
    });
  }

  Object _parseValue(String s) {
    final v = s.trim();
    if (v == 'true') return true;
    if (v == 'false') return false;
    return num.tryParse(v) ?? v;
  }

  // -- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final result = _result();
    return PickerPanel(
      kicker: 'ADD CONDITION · CHOOSE WHAT TO CHECK',
      title: 'What has to be true?',
      seg: pickerSeg(HcTokens.of(context),
          byRoom: _byRoom,
          onChanged: (v) => setState(() {
                _byRoom = v;
                if (v) _room = _rooms.first;
              })),
      rail: _rail(context),
      list: _list(context),
      detail: _detail(HcTokens.of(context)),
      footerHint: '${_entries.where((e) => !e.isMode).length} devices · '
          '${_entries.where((e) => e.isMode).length} modes',
      primaryLabel: 'Add condition',
      onPrimary: result == null ? null : () => Navigator.pop(context, result),
    );
  }

  Widget _rail(BuildContext context) {
    final t = HcTokens.of(context);
    final items = <Widget>[];
    if (_byRoom) {
      for (final r in _rooms) {
        items.add(pickerRailRow(t,
            label: r,
            icon: Icons.meeting_room_outlined,
            count: _entries.where((e) => e.room == r).length,
            selected: _room == r,
            onTap: () => setState(() => _room = r)));
      }
    } else {
      var lastGroup = '';
      for (final c in _cats) {
        if (c.group != lastGroup) {
          items.add(pickerGroupLabel(t, c.group));
          lastGroup = c.group;
        }
        items.add(pickerRailRow(t,
            label: c.label,
            icon: c.icon,
            count: _count(c.key),
            selected: _cat == c.key,
            onTap: () => setState(() => _cat = c.key)));
      }
    }
    return PickerRail(children: items);
  }

  Widget _list(BuildContext context) {
    final t = HcTokens.of(context);
    final pool = _pool;
    final rows = <Widget>[];
    var lastRoom = '';
    for (final e in pool) {
      if (!_byRoom && e.room != lastRoom) {
        rows.add(pickerGroupLabel(t, e.room));
        lastRoom = e.room;
      }
      rows.add(pickerDeviceRow(t,
          icon: e.icon,
          label: e.label,
          sub: e.sub,
          chip: e.chip,
          chipTone: e.chipTone,
          selected: _sel?.ref == e.ref,
          onTap: () => _select(e)));
    }
    return PickerDeviceList(
      onQuery: (v) => setState(() => _query = v),
      rows: rows,
      empty: pool.isEmpty,
    );
  }

  // -- pane 3: the condition builder ---------------------------------------

  Widget _detail(HcTokens t) {
    final e = _sel;
    if (e == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(t.space.lg),
          child: Text(
            'Pick a device or mode to check. Sensors live here — a condition is what reads their state.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5, height: 1.5, color: t.surface.onBaseMuted),
          ),
        ),
      );
    }
    final current = e.isMode ? null : e.device!.state[_attr];
    return ListView(
      padding: EdgeInsets.all(t.space.md),
      children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: t.accent.active.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.accent.active.withValues(alpha: 0.3)),
            ),
            child: Icon(e.icon, size: 21, color: t.accent.active),
          ),
          SizedBox(width: t.space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.label,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.surface.onBase)),
                Text(current == null ? e.sub : 'currently $current',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: t.surface.onBaseMuted)),
              ],
            ),
          ),
        ]),
        SizedBox(height: t.space.md),
        if (e.isMode) ..._modeControls(t) else ..._deviceControls(t, e),
        SizedBox(height: t.space.md),
        _preview(t, e),
      ],
    );
  }

  List<Widget> _modeControls(HcTokens t) => [
        const RailLabel('State'),
        SizedBox(height: t.space.sm),
        Row(children: [
          _toggleBtn(t, 'Is on', _modeOn, () => setState(() => _modeOn = true)),
          SizedBox(width: t.space.xs),
          _toggleBtn(
              t, 'Is off', !_modeOn, () => setState(() => _modeOn = false)),
        ]),
      ];

  List<Widget> _deviceControls(HcTokens t, _Entry e) => [
        const RailLabel('Attribute'),
        SizedBox(height: t.space.sm),
        _dropdown(t, _attr, e.attrs, (v) {
          setState(() {
            _attr = v!;
            _valueText = '${e.device!.state[_attr] ?? 'true'}';
          });
        }),
        SizedBox(height: t.space.md),
        const RailLabel('Comparison'),
        SizedBox(height: t.space.sm),
        _dropdown(t, _op, [for (final o in _ops) o.$1], (v) {
          setState(() => _op = v!);
        }, labelFor: (k) => _ops.firstWhere((o) => o.$1 == k).$2),
        SizedBox(height: t.space.md),
        const RailLabel('Value'),
        SizedBox(height: t.space.sm),
        TextFormField(
          initialValue: _valueText,
          key: ValueKey('${e.ref}:$_attr'),
          decoration:
              fieldDecoration(t, hint: 'true, false, a number, or text'),
          onChanged: (v) => setState(() => _valueText = v),
        ),
      ];

  Widget _dropdown(HcTokens t, String value, List<String> opts,
      ValueChanged<String?> onChanged,
      {String Function(String)? labelFor}) {
    final safe =
        opts.contains(value) ? value : (opts.isEmpty ? null : opts.first);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: t.stroke.hairline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safe,
          isExpanded: true,
          dropdownColor: t.surface.overlay,
          style: TextStyle(fontSize: 13.5, color: t.surface.onBase),
          items: [
            for (final o in opts)
              DropdownMenuItem(value: o, child: Text(labelFor?.call(o) ?? o)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _toggleBtn(HcTokens t, String label, bool on, VoidCallback onTap) {
    final ac = t.accent.active;
    return Expanded(
      child: Material(
        color: on ? ac.withValues(alpha: 0.14) : t.surface.raised,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                  color: on ? ac.withValues(alpha: 0.4) : t.stroke.hairline),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: on ? ac : t.surface.onBaseMuted)),
          ),
        ),
      ),
    );
  }

  Widget _preview(HcTokens t, _Entry e) {
    Widget word(String s) =>
        Text(s, style: TextStyle(fontSize: 13.5, color: t.surface.onBaseMuted));
    Widget tok(String s, Color c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: c.withValues(alpha: 0.32)),
          ),
          child: Text(s,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: c)),
        );
    final dev = tok(e.label, t.accent.primary);
    final List<Widget> parts;
    if (e.isMode) {
      parts = [dev, word('is'), tok(_modeOn ? 'on' : 'off', t.accent.active)];
    } else {
      final verb = _ops.firstWhere((o) => o.$1 == _op).$2;
      parts = [
        word('the'),
        tok(_attr.replaceAll('_', ' '), t.accent.active),
        word('of'),
        dev,
        tok(verb, t.accent.active),
        tok(_valueText.isEmpty ? '…' : _valueText, t.accent.active),
      ];
    }
    return Container(
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RailLabel('Reads as'),
          SizedBox(height: t.space.sm),
          Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: parts),
        ],
      ),
    );
  }
}
