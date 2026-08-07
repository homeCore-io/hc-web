import 'package:flutter/material.dart';

import '../../../core/devices/presentation.dart';
import '../../../core/models/device_state.dart';
import '../../../core/rules/node.dart';
import '../../../core/rules/schema.dart';
import '../../../core/schema/attribute_policy.dart';
import '../../../core/schema/device_schema.dart';
import '../../../core/text/humanize.dart';
import '../../../design/tokens.dart';
import 'device_choice_picker.dart';
import 'device_picker_shell.dart';
import 'editor_style.dart';
import 'rule_refs.dart';

/// The multi-pane "Check a device" picker for conditions — on the same
/// [PickerPanel] shell as the action picker, but covering the whole condition
/// vocabulary, not just devices.
///
/// Rail categories fall into two kinds:
///  * **device** categories (lights … sensors, modes) list real things to pick,
///    then a per-thing form (attribute + comparison, or mode on/off);
///  * **template** categories (Time, Hub, Logic, Script) list condition *types*
///    whose detail pane is a small form (between-times, hub variable, …) or,
///    for the structural ones (All-of / Any-of / expression), a blank node that
///    grows in the tree.
///
/// Returns the built condition `HcNode`.
class DeviceConditionPicker extends StatefulWidget {
  const DeviceConditionPicker({super.key, required this.refs});

  final RuleRefs refs;

  @override
  State<DeviceConditionPicker> createState() => _DeviceConditionPickerState();
}

enum _Kind { device, mode, template }

class _Entry {
  _Entry({
    required this.label,
    required this.ref,
    required this.sub,
    required this.icon,
    required this.bucket,
    required this.room,
    required this.kind,
    this.tag,
    this.attrs = const [],
    this.device,
    this.chip,
    this.chipTone,
  });

  final String label;
  final String ref;
  final String sub;
  final IconData icon;
  final String bucket;
  final String room;
  final _Kind kind;

  /// For template entries: the condition variant tag (`TimeWindow`, `And`, …).
  final String? tag;
  final List<String> attrs;
  final DeviceState? device;
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
  PickerCat('time', 'Time & calendar', Icons.schedule_outlined, 'Rules'),
  PickerCat('mode', 'Modes', Icons.brightness_4_outlined, 'Hub'),
  PickerCat('hub', 'Hub & flags', Icons.data_object_outlined, 'Hub'),
  PickerCat('logic', 'Logic groups', Icons.account_tree_outlined, 'Advanced'),
  PickerCat('script', 'Expression', Icons.code_outlined, 'Advanced'),
];

/// Template entries: condition types with no device to pick.
const _templates = <(String bucket, String tag, String label, IconData icon)>[
  ('time', 'TimeWindow', 'Between two times', Icons.schedule_outlined),
  ('time', 'CalendarActive', 'Calendar event active', Icons.event_outlined),
  ('hub', 'HubVariable', 'Hub variable is', Icons.data_object_outlined),
  ('hub', 'PrivateBooleanIs', 'Private flag is', Icons.flag_outlined),
  ('logic', 'And', 'All of these (AND)', Icons.account_tree_outlined),
  ('logic', 'Or', 'Any of these (OR)', Icons.account_tree_outlined),
  ('logic', 'Xor', 'Exactly one of these', Icons.account_tree_outlined),
  ('logic', 'Not', 'Not this', Icons.block_outlined),
  ('script', 'ScriptExpression', 'Rhai expression', Icons.code_outlined),
  // Device-scoped, but they read as a question about time rather than about
  // the device's current value, so they live with the other time conditions.
  (
    'time',
    'TimeElapsed',
    'Unchanged for a while',
    Icons.hourglass_bottom_outlined
  ),
  ('time', 'DeviceLastChange', 'Last changed by…', Icons.history_outlined),
];

/// Condition variants reachable through the template list and the device /
/// mode panes. Asserted against `kConditions` in the tests — dropping the
/// old palette made two variants unauthorable, and only a test prevents that
/// happening again.
final kConditionTemplateTags = [for (final t in _templates) t.$2];

const kConditionDeviceTags = ['DeviceState', 'ModeIs'];

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
      _ => 'sensor',
    };

class _DeviceConditionPickerState extends State<DeviceConditionPicker> {
  bool _byRoom = false;
  String _cat = 'all';
  String _room = '';
  String _query = '';

  _Entry? _sel;

  // Shared detail state (reused across kinds where the control is the same).
  String _attr = '';
  String _op = 'Eq';
  String _valueText = 'true';
  bool _boolOn = true;
  String _name = ''; // hub variable / private flag name
  String _start = '09:00:00';
  String _end = '17:00:00';
  String _calId = '';
  String _titleContains = '';
  String _deviceRef = '';
  String _elapsedAttr = '';
  int _elapsedSecs = 300;
  String _changeKind = 'physical';

  late final List<_Entry> _entries = _buildEntries();

  // -- entries -------------------------------------------------------------

  List<_Entry> _buildEntries() {
    final out = <_Entry>[];
    for (final d in widget.refs.devices) {
      final facet = facetOf(d, d.schema);
      if (facet == DeviceFacet.scene) continue;
      final attrs = _comparableAttrs(d);
      if (attrs.isEmpty) continue;
      final (chip, tone) = _deviceChip(d);
      out.add(_Entry(
        label: d.displayName,
        ref: d.ruleReference,
        sub: d.canonicalName ?? d.id,
        icon: facet.icon,
        bucket: _bucketOf(facet),
        room: (d.effectiveArea?.isNotEmpty ?? false)
            ? humanize(d.effectiveArea)
            : 'No room',
        kind: _Kind.device,
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
        kind: _Kind.mode,
      ));
    }
    for (final (bucket, tag, label, icon) in _templates) {
      out.add(_Entry(
        label: label,
        ref: tag,
        sub: '',
        icon: icon,
        bucket: bucket,
        room: '', // flat — no room header for templates
        kind: _Kind.template,
        tag: tag,
      ));
    }
    return out;
  }

  List<String> _comparableAttrs(DeviceState d) {
    final out = <String>[];
    for (final e in d.state.entries) {
      final v = e.value;
      if (v is bool || v is num || v is String) out.add(e.key);
    }
    out.sort();
    return out;
  }

  /// What a device is doing right now.
  ///
  /// Delegates rather than hard-coding a convention: this used to read
  /// `contact == true` as "closed", which is the usual meaning of a contact
  /// circuit and the opposite of what hc-yolink and hc-isy publish — both set
  /// `contact` equal to `open`, so true means the door is OPEN.
  (String?, PickerTone?) _deviceChip(DeviceState d) => deviceLiveChip(d);

  // -- filtering -----------------------------------------------------------

  List<_Entry> get _pool {
    var p = _entries.where((e) {
      if (_byRoom) return e.kind == _Kind.device && e.room == _room;
      if (_cat == 'all') return e.kind == _Kind.device;
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
        .where((e) => e.kind == _Kind.device)
        .map((e) => e.room)
        .toSet()
        .toList()
      ..sort();
    return rs;
  }

  int _count(String cat) => cat == 'all'
      ? _entries.where((e) => e.kind == _Kind.device).length
      : _entries.where((e) => e.bucket == cat).length;

  void _select(_Entry e) {
    setState(() {
      _sel = e;
      switch (e.kind) {
        case _Kind.mode:
          _boolOn = true;
        case _Kind.device:
          _attr = _defaultAttr(e);
          _op = 'Eq';
          _valueText = '${e.device!.state[_attr] ?? 'true'}';
        case _Kind.template:
          _op = 'Eq';
          _valueText = 'true';
          _boolOn = true;
          _name = '';
          _start = '09:00:00';
          _end = '17:00:00';
          _calId = '';
          _titleContains = '';
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
    switch (e.kind) {
      case _Kind.mode:
        return HcNode('ModeIs', {'mode_id': e.ref, 'on': _boolOn});
      case _Kind.device:
        if (_attr.isEmpty) return null;
        return HcNode('DeviceState', {
          'device_id': e.ref,
          'attribute': _attr,
          'op': _op,
          'value': _parseValue(_valueText),
        });
      case _Kind.template:
        return _templateNode(e.tag!);
    }
  }

  HcNode? _templateNode(String tag) {
    switch (tag) {
      case 'TimeWindow':
        return HcNode('TimeWindow', {'start': _start, 'end': _end});
      case 'CalendarActive':
        return HcNode('CalendarActive', {
          if (_calId.trim().isNotEmpty) 'calendar_id': _calId.trim(),
          if (_titleContains.trim().isNotEmpty)
            'title_contains': _titleContains.trim(),
        });
      case 'HubVariable':
        if (_name.trim().isEmpty) return null;
        return HcNode('HubVariable', {
          'name': _name.trim(),
          'op': _op,
          'value': _parseValue(_valueText),
        });
      case 'PrivateBooleanIs':
        if (_name.trim().isEmpty) return null;
        return HcNode(
            'PrivateBooleanIs', {'name': _name.trim(), 'value': _boolOn});
      case 'TimeElapsed':
        if (_deviceRef.isEmpty || _elapsedAttr.isEmpty) return null;
        return HcNode('TimeElapsed', {
          'device_id': _deviceRef,
          'attribute': _elapsedAttr,
          'duration_secs': _elapsedSecs,
        });
      case 'DeviceLastChange':
        if (_deviceRef.isEmpty) return null;
        return HcNode('DeviceLastChange', {
          'device_id': _deviceRef,
          'kind': _changeKind,
        });
      default:
        // And / Or / Xor / Not / ScriptExpression — a blank node that the tree
        // grows in place.
        final v = kConditions[tag];
        return v == null ? null : HcNode.blank(v);
    }
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
      kicker: 'ADD CONDITION · WHAT TO CHECK',
      title: 'What has to be true?',
      seg: pickerSeg(HcTokens.of(context),
          byRoom: _byRoom,
          onChanged: (v) => setState(() {
                _byRoom = v;
                if (v) _room = _rooms.isEmpty ? '' : _rooms.first;
              })),
      panes: [
        PickerPane(width: 202, compactLabel: 'Where', child: _rail(context)),
        PickerPane(flex: 3, compactLabel: 'What', child: _list(context)),
        PickerPane(flex: 4, compactLabel: 'Details', child: _detail(context)),
      ],
      footerHint: '${_entries.where((e) => e.kind == _Kind.device).length} '
          'devices · time · hub · logic · expressions',
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
      if (!_byRoom && e.room.isNotEmpty && e.room != lastRoom) {
        rows.add(pickerGroupLabel(t, e.room));
        lastRoom = e.room;
      }
      rows.add(pickerDeviceRow(t,
          icon: e.icon,
          label: e.label,
          sub: e.sub,
          chip: e.chip,
          chipTone: e.chipTone,
          selected: _sel?.ref == e.ref && _sel?.bucket == e.bucket,
          onTap: () => _select(e)));
    }
    return PickerDeviceList(
      onQuery: (v) => setState(() => _query = v),
      rows: rows,
      empty: pool.isEmpty,
    );
  }

  // -- pane 3: the condition builder ---------------------------------------

  Widget _detail(BuildContext context) {
    final t = HcTokens.of(context);
    final e = _sel;
    if (e == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(t.space.lg),
          child: Text(
            'Pick something to check. Devices and sensors are on the left; Time, '
            'Hub, Logic and Expression conditions are further down.',
            textAlign: TextAlign.center,
            style: t.text.bodySmallStyle
                .copyWith(height: 1.5, color: t.surface.onBaseMuted),
          ),
        ),
      );
    }
    final title = e.kind == _Kind.template ? e.label : e.label;
    final sub = switch (e.kind) {
      _Kind.device => 'currently ${e.device!.state[_attr]}',
      _Kind.mode => 'hub mode',
      _Kind.template => 'condition',
    };
    return ListView(
      padding: EdgeInsets.all(t.space.md),
      children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: t.accent.active.withValues(alpha: 0.14),
              borderRadius: t.radius.smR,
              border: Border.all(color: t.accent.active.withValues(alpha: 0.3)),
            ),
            child: Icon(e.icon, size: 21, color: t.accent.active),
          ),
          SizedBox(width: t.space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: t.text.subtitleStyle.copyWith(
                        fontWeight: FontWeight.w600, color: t.surface.onBase)),
                Text(sub,
                    overflow: TextOverflow.ellipsis,
                    style: t.text.captionStyle
                        .copyWith(color: t.surface.onBaseMuted)),
              ],
            ),
          ),
        ]),
        SizedBox(height: t.space.md),
        ..._controls(context, t, e),
        SizedBox(height: t.space.md),
        _preview(t, e),
      ],
    );
  }

  List<Widget> _controls(BuildContext context, HcTokens t, _Entry e) {
    switch (e.kind) {
      case _Kind.mode:
        return _onOff(t);
      case _Kind.device:
        return _deviceControls(t, e);
      case _Kind.template:
        return _templateControls(context, t, e.tag!);
    }
  }

  List<Widget> _onOff(HcTokens t) => [
        const RailLabel('State'),
        SizedBox(height: t.space.sm),
        Row(children: [
          _toggleBtn(t, 'Is on', _boolOn, () => setState(() => _boolOn = true)),
          SizedBox(width: t.space.xs),
          _toggleBtn(
              t, 'Is off', !_boolOn, () => setState(() => _boolOn = false)),
        ]),
      ];

  List<Widget> _deviceControls(HcTokens t, _Entry e) {
    final states = _boolStatesOf(e, _attr);
    return [
      const RailLabel('Attribute'),
      SizedBox(height: t.space.sm),
      _dropdown(t, _attr, e.attrs, (v) {
        setState(() {
          _attr = v!;
          _valueText = '${e.device!.state[_attr] ?? 'true'}';
        });
      }),
      SizedBox(height: t.space.md),
      // A boolean has exactly two states, and both deserve a name. The
      // comparison dropdown is dead weight here — "not equal to true" is a long
      // way round to "is closed" — so a named pair replaces the whole
      // comparison-and-value pair of controls.
      if (states != null) ...[
        const RailLabel('Is'),
        SizedBox(height: t.space.sm),
        Row(children: [
          _toggleBtn(
              t,
              _sentenceCase(states[true].label),
              _valueText == 'true',
              () => setState(() {
                    _op = '==';
                    _valueText = 'true';
                  })),
          SizedBox(width: t.space.xs),
          _toggleBtn(
              t,
              _sentenceCase(states[false].label),
              _valueText == 'false',
              () => setState(() {
                    _op = '==';
                    _valueText = 'false';
                  })),
        ]),
      ] else
        ..._compareAndValue(t),
    ];
  }

  /// The names of a boolean attribute's two states, or null when the attribute
  /// is not boolean and a comparison is the honest control.
  BoolStates? _boolStatesOf(_Entry e, String attr) {
    if (attr.isEmpty) return null;
    final schema = e.device?.schema?[attr];
    if (schema?.kind != AttributeKind.bool_ && e.device?.state[attr] is! bool) {
      return null;
    }
    // Never null for a boolean: the lexicon covers the common names and the
    // mechanical fallback covers the rest, so there are always two rows.
    return boolStatesFor(attr, schema) ??
        BoolStates(
          StateLabel(attr.replaceAll('_', ' ')),
          StateLabel('not ${attr.replaceAll('_', ' ')}'),
        );
  }

  static String _sentenceCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  List<Widget> _compareAndValue(HcTokens t) => [
        const RailLabel('Comparison'),
        SizedBox(height: t.space.sm),
        _dropdown(t, _op, [for (final o in _ops) o.$1],
            (v) => setState(() => _op = v!),
            labelFor: (k) => _ops.firstWhere((o) => o.$1 == k).$2),
        SizedBox(height: t.space.md),
        const RailLabel('Value'),
        SizedBox(height: t.space.sm),
        TextFormField(
          key: ValueKey('value:${_sel?.ref}:$_attr'),
          initialValue: _valueText,
          decoration:
              fieldDecoration(t, hint: 'true, false, a number, or text'),
          onChanged: (v) => setState(() => _valueText = v),
        ),
      ];

  List<Widget> _templateControls(BuildContext context, HcTokens t, String tag) {
    switch (tag) {
      case 'TimeWindow':
        return [
          const RailLabel('Between'),
          SizedBox(height: t.space.sm),
          Row(children: [
            Expanded(
                child: _timeBtn(context, t, 'From', _start,
                    (v) => setState(() => _start = v))),
            SizedBox(width: t.space.sm),
            Expanded(
                child: _timeBtn(context, t, 'Until', _end,
                    (v) => setState(() => _end = v))),
          ]),
          SizedBox(height: t.space.sm),
          Text(
            'An overnight window is fine — set From later than Until (e.g. 22:00 to 06:00).',
            style: t.text.captionStyle
                .copyWith(height: 1.4, color: t.surface.onBaseMuted),
          ),
        ];
      case 'CalendarActive':
        return [
          const RailLabel('Calendar'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: _calId,
            decoration: fieldDecoration(t, hint: 'Calendar id (blank = any)'),
            onChanged: (v) => setState(() => _calId = v),
          ),
          SizedBox(height: t.space.md),
          const RailLabel('Event title contains'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: _titleContains,
            decoration: fieldDecoration(t, hint: 'e.g. Trash (blank = any)'),
            onChanged: (v) => setState(() => _titleContains = v),
          ),
        ];
      case 'HubVariable':
        return [
          const RailLabel('Variable name'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: _name,
            decoration: fieldDecoration(t, hint: 'e.g. guests_home'),
            onChanged: (v) => setState(() => _name = v),
          ),
          SizedBox(height: t.space.md),
          ..._compareAndValue(t),
        ];
      case 'PrivateBooleanIs':
        return [
          const RailLabel('Flag name'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: _name,
            decoration: fieldDecoration(t, hint: 'e.g. vacation'),
            onChanged: (v) => setState(() => _name = v),
          ),
          SizedBox(height: t.space.md),
          ..._onOff(t),
        ];
      case 'TimeElapsed':
      case 'DeviceLastChange':
        // These name a device, so the form has to pick one — the device panes
        // are for conditions *about* a device's value, and these are not.
        final devices = widget.refs.devices;
        final refs = [for (final d in devices) d.ruleReference];
        final names = {
          for (final d in devices) d.ruleReference: d.displayName,
        };
        if (_deviceRef.isEmpty && refs.isNotEmpty) _deviceRef = refs.first;
        final attrs = widget.refs.attributesOf(_deviceRef);
        if (_elapsedAttr.isEmpty && attrs.isNotEmpty) {
          _elapsedAttr = attrs.first;
        }
        return [
          const RailLabel('Device'),
          SizedBox(height: t.space.sm),
          _dropdown(t, _deviceRef, refs, (v) {
            setState(() {
              _deviceRef = v!;
              _elapsedAttr = '';
            });
          }, labelFor: (r) => names[r] ?? r),
          SizedBox(height: t.space.md),
          if (tag == 'TimeElapsed') ...[
            const RailLabel('Attribute'),
            SizedBox(height: t.space.sm),
            _dropdown(t, _elapsedAttr, attrs,
                (v) => setState(() => _elapsedAttr = v!)),
            SizedBox(height: t.space.md),
            const RailLabel('Unchanged for (seconds)'),
            SizedBox(height: t.space.sm),
            TextFormField(
              key: ValueKey('elapsed:$_deviceRef'),
              initialValue: '$_elapsedSecs',
              keyboardType: TextInputType.number,
              decoration: fieldDecoration(t, hint: 'e.g. 300'),
              onChanged: (v) => setState(
                  () => _elapsedSecs = int.tryParse(v.trim()) ?? _elapsedSecs),
            ),
          ] else ...[
            const RailLabel('Last change came from'),
            SizedBox(height: t.space.sm),
            _dropdown(t, _changeKind, changeKindValues,
                (v) => setState(() => _changeKind = v!)),
            SizedBox(height: t.space.sm),
            Text(
              'Distinguishes a change HomeCore made from one someone made at '
              'the wall — the usual way to stop a rule reacting to itself.',
              style: t.text.captionStyle
                  .copyWith(height: 1.4, color: t.surface.onBaseMuted),
            ),
          ],
        ];
      default:
        // And / Or / Xor / Not / ScriptExpression.
        final note = switch (tag) {
          'And' =>
            'Adds an ALL-of group. Drop the conditions that must all hold inside it.',
          'Or' =>
            'Adds an ANY-of group. It passes when at least one inside holds.',
          'Xor' =>
            'Adds an exactly-one group — passes when precisely one inside holds.',
          'Not' =>
            'Adds a NOT — it inverts the single condition you place inside.',
          _ =>
            'Adds a Rhai expression you write in the editor, for anything the forms cannot express.',
        };
        return [
          Container(
            padding: EdgeInsets.all(t.space.md),
            decoration: BoxDecoration(
              color: t.surface.sunken,
              borderRadius: t.radius.smR,
              border: Border.all(color: t.stroke.hairline),
            ),
            child: Text(note,
                style: t.text.bodySmallStyle
                    .copyWith(height: 1.5, color: t.surface.onBaseMuted)),
          ),
        ];
    }
  }

  // -- small controls ------------------------------------------------------

  Widget _timeBtn(BuildContext context, HcTokens t, String label, String value,
      ValueChanged<String> onPick) {
    final parts = value.split(':');
    final h = int.tryParse(parts.elementAtOrNull(0) ?? '') ?? 0;
    final m = int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0;
    final hhmm =
        '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    return Material(
      color: t.surface.sunken,
      borderRadius: t.radius.smR,
      child: InkWell(
        borderRadius: t.radius.smR,
        onTap: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: h, minute: m),
          );
          if (picked != null) {
            onPick('${picked.hour.toString().padLeft(2, '0')}:'
                '${picked.minute.toString().padLeft(2, '0')}:00');
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: t.radius.smR,
            border: Border.all(color: t.stroke.hairline),
          ),
          child: Row(children: [
            Text(label.toUpperCase(),
                style: t.text.overlineStyle.copyWith(
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w800,
                    color: t.surface.onBaseMuted)),
            const Spacer(),
            Text(hhmm,
                style: t.text.resolve(t.text.subtitle, mono: true).copyWith(
                    fontWeight: FontWeight.w600, color: t.accent.active)),
          ]),
        ),
      ),
    );
  }

  Widget _dropdown(HcTokens t, String value, List<String> opts,
      ValueChanged<String?> onChanged,
      {String Function(String)? labelFor}) {
    final safe =
        opts.contains(value) ? value : (opts.isEmpty ? null : opts.first);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: t.radius.smR,
        border: Border.all(color: t.stroke.hairline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safe,
          isExpanded: true,
          dropdownColor: t.surface.overlay,
          style: t.text.bodyStyle.copyWith(color: t.surface.onBase),
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
        borderRadius: t.radius.smR,
        child: InkWell(
          onTap: onTap,
          borderRadius: t.radius.smR,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: t.radius.smR,
              border: Border.all(
                  color: on ? ac.withValues(alpha: 0.4) : t.stroke.hairline),
            ),
            child: Text(label,
                style: t.text.bodyStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: on ? ac : t.surface.onBaseMuted)),
          ),
        ),
      ),
    );
  }

  // -- live preview --------------------------------------------------------

  Widget _preview(HcTokens t, _Entry e) {
    Widget word(String s) =>
        Text(s, style: t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted));
    Widget tok(String s, Color c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.14),
            borderRadius: t.radius.xsR,
            border: Border.all(color: c.withValues(alpha: 0.32)),
          ),
          child: Text(s,
              style: t.text.bodyStyle
                  .copyWith(fontWeight: FontWeight.w600, color: c)),
        );
    final a = t.accent.active;
    final b = t.accent.primary;
    String hhmm(String v) => v.split(':').take(2).join(':');
    final verb = _ops.firstWhere((o) => o.$1 == _op).$2;

    List<Widget> parts() {
      switch (e.kind) {
        case _Kind.mode:
          return [tok(e.label, b), word('is'), tok(_boolOn ? 'on' : 'off', a)];
        case _Kind.device:
          return [
            word('the'),
            tok(_attr.replaceAll('_', ' '), a),
            word('of'),
            tok(e.label, b),
            tok(verb, a),
            tok(_valueText.isEmpty ? '…' : _valueText, a),
          ];
        case _Kind.template:
          switch (e.tag) {
            case 'TimeWindow':
              return [
                word('the time is between'),
                tok(hhmm(_start), a),
                word('and'),
                tok(hhmm(_end), a),
              ];
            case 'CalendarActive':
              return [
                word('a calendar event is active'),
                if (_titleContains.trim().isNotEmpty) ...[
                  word('matching'),
                  tok(_titleContains.trim(), a)
                ],
              ];
            case 'HubVariable':
              return [
                word('the hub variable'),
                tok(_name.isEmpty ? '…' : _name, b),
                tok(verb, a),
                tok(_valueText.isEmpty ? '…' : _valueText, a),
              ];
            case 'PrivateBooleanIs':
              return [
                word('the flag'),
                tok(_name.isEmpty ? '…' : _name, b),
                word('is'),
                tok(_boolOn ? 'set' : 'clear', a),
              ];
            case 'TimeElapsed':
              return [
                word('the'),
                tok(_elapsedAttr.replaceAll('_', ' '), a),
                word('of'),
                tok(_deviceRef.isEmpty ? '…' : _deviceRef, b),
                word("hasn't changed for"),
                tok('$_elapsedSecs seconds', a),
              ];
            case 'DeviceLastChange':
              return [
                word("the last change to"),
                tok(_deviceRef.isEmpty ? '…' : _deviceRef, b),
                word('came from'),
                tok(_changeKind, a),
              ];
            default:
              return [tok(e.label, a)];
          }
      }
    }

    return Container(
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: t.radius.smR,
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
              children: parts()),
        ],
      ),
    );
  }
}
