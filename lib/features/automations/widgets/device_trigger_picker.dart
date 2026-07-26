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

/// The multi-pane "When…" picker for a rule's trigger — the WHEN-clause twin of
/// the action / condition pickers, on the same [PickerPanel] shell.
///
/// Pick a device (any device — sensors especially — can be a trigger) and how
/// it should fire, or a non-device trigger (a time of day, a solar event, a
/// mode change, a webhook, by hand). Returns the built trigger `HcNode`, which
/// replaces the rule's single trigger.
class DeviceTriggerPicker extends StatefulWidget {
  const DeviceTriggerPicker({super.key, required this.refs});

  final RuleRefs refs;

  @override
  State<DeviceTriggerPicker> createState() => _DeviceTriggerPickerState();
}

enum _Kind { device, template }

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
    this.numericAttrs = const [],
    this.buttons = const [],
    this.hasBattery = false,
    this.isButtonDevice = false,
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
  final String? tag;
  final List<String> attrs;
  final List<String> numericAttrs;

  /// Buttons this device is known to have. A keypad or Pico fires
  /// `ButtonEvent`, and without this the button number is a bare integer box.
  final List<String> buttons;

  /// Whether it reports a battery — the gate for the battery triggers, which
  /// are meaningless on a mains-powered device.
  final bool hasBattery;

  /// Buttons, batteries and thresholds are per-device facts, so the trigger
  /// types on offer differ per device rather than being one fixed list.
  final bool isButtonDevice;
  final DeviceState? device;
  final String? chip;
  final PickerTone? chipTone;
}

const _cats = [
  PickerCat('all', 'All devices', Icons.list_alt_outlined, 'Quick'),
  PickerCat('light', 'Lights', Icons.lightbulb_outline, 'Controls'),
  PickerCat('switch', 'Switches & Outlets', Icons.toggle_on_outlined, 'Controls'),
  PickerCat('cover', 'Shades & Covers', Icons.blinds_outlined, 'Controls'),
  PickerCat('lock', 'Locks', Icons.lock_outline, 'Controls'),
  PickerCat('climate', 'Climate', Icons.hvac_outlined, 'Controls'),
  PickerCat('media', 'Media players', Icons.speaker_outlined, 'Controls'),
  PickerCat('sensor', 'Sensors', Icons.sensors, 'Read'),
  PickerCat('time', 'Time & sun', Icons.schedule_outlined, 'Schedule'),
  PickerCat('hub', 'Modes & variables', Icons.brightness_4_outlined, 'Hub'),
  PickerCat('other', 'Webhook & manual', Icons.bolt_outlined, 'Other'),
  PickerCat('integration', 'Events & MQTT', Icons.hub_outlined, 'Other'),
];

const _templates = <(String bucket, String tag, String label, IconData icon)>[
  ('time', 'TimeOfDay', 'At a time of day', Icons.schedule_outlined),
  ('time', 'SunEvent', 'At a solar event', Icons.wb_twilight_outlined),
  ('hub', 'ModeChanged', 'When a mode turns on / off', Icons.brightness_4_outlined),
  ('other', 'WebhookReceived', 'When a webhook is called', Icons.webhook_outlined),
  ('other', 'ManualTrigger', 'By hand / from another rule', Icons.touch_app_outlined),
  ('time', 'Cron', 'On a cron schedule', Icons.event_repeat_outlined),
  ('time', 'Periodic', 'Every N minutes / hours', Icons.timelapse_outlined),
  ('time', 'CalendarEvent', 'On a calendar event', Icons.event_outlined),
  ('hub', 'HubVariableChanged', 'When a hub variable changes',
      Icons.data_object_outlined),
  ('other', 'SystemStarted', 'When HomeCore starts', Icons.restart_alt_outlined),
  ('integration', 'CustomEvent', 'On a custom event', Icons.bolt_outlined),
  ('integration', 'MqttMessage', 'On an MQTT message', Icons.podcasts_outlined),
];

/// Trigger variants reachable through the template list, and through the
/// device pane. Asserted against `kTriggers` in the tests: the WHEN picker
/// replaced a palette that could reach every variant, and losing one to an
/// oversight is exactly what happened before.
final kTriggerTemplateTags = [for (final t in _templates) t.$2];

const kTriggerDeviceTags = [
  'DeviceStateChanged',
  'DeviceAvailabilityChanged',
  'NumericThreshold',
  'ButtonEvent',
  'DeviceBatteryLow',
  'DeviceBatteryRecovered',
];

const _sunEvents = ['Sunrise', 'Sunset', 'SolarNoon', 'CivilDawn', 'CivilDusk'];
const _thresholdOps = [
  ('CrossesAbove', 'rises above'),
  ('CrossesBelow', 'drops below'),
  ('Above', 'is above'),
  ('Below', 'is below'),
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _bucketOf(DeviceFacet f) => switch (f) {
      DeviceFacet.light ||
      DeviceFacet.dimmableLight ||
      DeviceFacet.colorLight =>
        'light',
      DeviceFacet.switch_ || DeviceFacet.outlet || DeviceFacet.siren => 'switch',
      DeviceFacet.cover || DeviceFacet.garage => 'cover',
      DeviceFacet.lock => 'lock',
      DeviceFacet.climate => 'climate',
      DeviceFacet.mediaPlayer => 'media',
      _ => 'sensor',
    };

class _DeviceTriggerPickerState extends State<DeviceTriggerPicker> {
  bool _byRoom = false;
  String _cat = 'all';
  String _room = '';
  String _query = '';

  _Entry? _sel;

  // device trigger detail
  String _ttype = 'changes'; // changes | changes_to | avail | threshold
  String _attr = ''; // '' == any attribute
  String _valueText = '';
  bool _availOn = true;
  String _thOp = 'CrossesAbove';

  // template detail
  String _time = '07:00:00';
  final Set<String> _days = {..._weekdays};
  String _sun = 'Sunset';
  int _offset = 0;
  String _modeId = '';
  bool _modeOn = true;
  String _path = '';
  String _cron = '0 0 7 * * *';
  int _everyN = 30;
  String _unit = 'Minutes';
  String _calId = '';
  String _titleContains = '';
  int _offsetMin = 0;
  String _varName = '';
  String _eventType = '';
  String _topic = '';
  String _button = '';
  String _buttonEvent = 'Pushed';

  late final List<_Entry> _entries = _buildEntries();

  // -- entries -------------------------------------------------------------

  List<_Entry> _buildEntries() {
    final out = <_Entry>[];
    for (final d in widget.refs.devices) {
      final facet = facetOf(d, d.schema);
      if (facet == DeviceFacet.scene) continue;
      final attrs = <String>[];
      final numeric = <String>[];
      for (final e in d.state.entries) {
        if (e.value is bool || e.value is num || e.value is String) {
          attrs.add(e.key);
        }
        if (e.value is num) numeric.add(e.key);
      }
      // A Pico that has never been pressed reports nothing at all, and it is
      // still a perfectly good trigger.
      if (attrs.isEmpty && facet != DeviceFacet.button) continue;
      attrs.sort();
      numeric.sort();
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
        numericAttrs: numeric,
        buttons: _buttonsOf(d),
        hasBattery: d.state.containsKey('battery'),
        isButtonDevice: facet == DeviceFacet.button,
        device: d,
        chip: chip,
        chipTone: tone,
      ));
    }
    for (final (bucket, tag, label, icon) in _templates) {
      out.add(_Entry(
        label: label,
        ref: tag,
        sub: '',
        icon: icon,
        bucket: bucket,
        room: '',
        kind: _Kind.template,
        tag: tag,
      ));
    }
    if (widget.refs.modes.isNotEmpty) _modeId = widget.refs.modes.first.id;
    return out;
  }

  /// The buttons a device is known to have.
  ///
  /// `available_buttons` first — the catalogue convention the action
  /// descriptor established, so this becomes a real list the moment a plugin
  /// publishes one. Failing that, the `button_N` attributes it has actually
  /// reported: hc-lutron only publishes a button once it has been pressed, so
  /// this is partial by nature and the form still allows any number.
  List<String> _buttonsOf(DeviceState d) {
    final published = d.state['available_buttons'];
    if (published is List && published.isNotEmpty) {
      return [for (final b in published) '$b'];
    }
    final seen = <int>{};
    for (final k in d.state.keys) {
      final m = RegExp(r'^button_(\d+)\$').firstMatch(k);
      if (m != null) seen.add(int.parse(m.group(1)!));
    }
    final out = seen.toList()..sort();
    return [for (final n in out) '$n'];
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

  List<String> get _rooms => (_entries
      .where((e) => e.kind == _Kind.device)
      .map((e) => e.room)
      .toSet()
      .toList()
    ..sort());

  int _count(String cat) => cat == 'all'
      ? _entries.where((e) => e.kind == _Kind.device).length
      : _entries.where((e) => e.bucket == cat).length;

  void _select(_Entry e) {
    setState(() {
      _sel = e;
      if (e.kind == _Kind.device) {
        _ttype = e.isButtonDevice ? 'button' : 'changes';
        _attr = '';
        _valueText = '';
        _availOn = true;
        _thOp = 'CrossesAbove';
      }
    });
  }

  HcNode? _result() {
    final e = _sel;
    if (e == null) return null;
    if (e.kind == _Kind.device) return _deviceTrigger(e);
    return _templateTrigger(e.tag!);
  }

  HcNode? _deviceTrigger(_Entry e) {
    switch (_ttype) {
      case 'changes':
        return HcNode('DeviceStateChanged', {
          'device_id': e.ref,
          if (_attr.isNotEmpty) 'attribute': _attr,
        });
      case 'changes_to':
        if (_attr.isEmpty) return null;
        // An empty value used to store `to: ""`, which is a trigger that can
        // never fire — and it looked complete, because the panel let you add it.
        if (_valueText.trim().isEmpty) return null;
        return HcNode('DeviceStateChanged', {
          'device_id': e.ref,
          'attribute': _attr,
          'to': _parseValue(_valueText),
        });
      case 'avail':
        return HcNode(
            'DeviceAvailabilityChanged', {'device_id': e.ref, 'to': _availOn});
      case 'threshold':
        if (_attr.isEmpty) return null;
        return HcNode('NumericThreshold', {
          'device_id': e.ref,
          'attribute': _attr,
          'op': _thOp,
          'value': num.tryParse(_valueText.trim()) ?? 0,
        });
      case 'button':
        final n = int.tryParse(_button.trim());
        return HcNode('ButtonEvent', {
          'device_id': e.ref,
          if (n != null) 'button_number': n,
          'event': _buttonEvent,
        });
      case 'battery_low':
        return HcNode('DeviceBatteryLow', {'device_id': e.ref});
      case 'battery_ok':
        return HcNode('DeviceBatteryRecovered', {'device_id': e.ref});
    }
    return null;
  }

  HcNode? _templateTrigger(String tag) {
    switch (tag) {
      case 'TimeOfDay':
        return HcNode('TimeOfDay', {'time': _time, 'days': _days.toList()});
      case 'SunEvent':
        return HcNode('SunEvent', {'event': _sun, 'offset_minutes': _offset});
      case 'ModeChanged':
        return HcNode('ModeChanged', {
          if (_modeId.isNotEmpty) 'mode_id': _modeId,
          'to': _modeOn,
        });
      case 'WebhookReceived':
        if (_path.trim().isEmpty) return null;
        return HcNode('WebhookReceived', {'path': _path.trim()});
      case 'ManualTrigger':
        return HcNode('ManualTrigger');
      case 'SystemStarted':
        return HcNode('SystemStarted');
      case 'Cron':
        if (_cron.trim().isEmpty) return null;
        return HcNode('Cron', {'expression': _cron.trim()});
      case 'Periodic':
        return HcNode('Periodic', {'every_n': _everyN, 'unit': _unit});
      case 'CalendarEvent':
        return HcNode('CalendarEvent', {
          if (_calId.trim().isNotEmpty) 'calendar_id': _calId.trim(),
          if (_titleContains.trim().isNotEmpty)
            'title_contains': _titleContains.trim(),
          if (_offsetMin != 0) 'offset_minutes': _offsetMin,
        });
      case 'HubVariableChanged':
        return HcNode('HubVariableChanged', {
          if (_varName.trim().isNotEmpty) 'name': _varName.trim(),
        });
      case 'CustomEvent':
        if (_eventType.trim().isEmpty) return null;
        return HcNode('CustomEvent', {'event_type': _eventType.trim()});
      case 'MqttMessage':
        if (_topic.trim().isEmpty) return null;
        return HcNode('MqttMessage', {'topic_pattern': _topic.trim()});
    }
    return null;
  }

  /// The two rows a boolean attribute is owed, or null when the attribute is
  /// not boolean and a free value is the honest control.
  ///
  /// The schema is asked first and the live reading second: an attribute the
  /// plugin declared `bool` is boolean even on a device that has not reported
  /// it yet, which is exactly the case a picker built from observed state alone
  /// gets wrong.
  List<({bool value, StateLabel state})>? _boolTransitions(
      _Entry e, String attr) {
    if (attr.isEmpty) return null;
    final schema = e.device?.schema?[attr];
    if (schema?.kind != AttributeKind.bool_ && e.device?.state[attr] is! bool) {
      return null;
    }
    return boolTransitionsFor(attr, schema);
  }

  /// A hint made of what this device actually reports, rather than a lecture on
  /// JSON. "true, false, a number, or text" told the user about the parser.
  String _valueHint(_Entry e, String attr) {
    final seen = e.device?.state[attr];
    final options = e.device?.schema?[attr]?.options;
    if (options != null && options.isNotEmpty) {
      return 'e.g. ${options.take(3).join(', ')}';
    }
    return seen == null ? 'the value to match' : 'e.g. $seen';
  }

  static String _sentenceCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

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
      kicker: 'CHANGE TRIGGER · WHEN SHOULD IT RUN',
      title: 'What sets this rule off?',
      seg: pickerSeg(HcTokens.of(context),
          byRoom: _byRoom,
          onChanged: (v) => setState(() {
                _byRoom = v;
                if (v) _room = _rooms.isEmpty ? '' : _rooms.first;
              })),
      panes: [
        PickerPane(
            width: 202, compactLabel: 'Where', child: _rail(context)),
        PickerPane(flex: 3, compactLabel: 'What', child: _list(context)),
        PickerPane(
            flex: 4, compactLabel: 'Details', child: _detail(context)),
      ],
      footerHint: '${_entries.where((e) => e.kind == _Kind.device).length} '
          'devices · time · sun · modes · webhook',
      primaryLabel: 'Set trigger',
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

  // -- pane 3 --------------------------------------------------------------

  Widget _detail(BuildContext context) {
    final t = HcTokens.of(context);
    final e = _sel;
    if (e == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(t.space.lg),
          child: Text(
            'Pick a device to fire on its changes, or choose a time, a solar '
            'event, a mode change, a webhook, or run it by hand.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5, height: 1.5, color: t.surface.onBaseMuted),
          ),
        ),
      );
    }
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
            child: Text(e.label,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.surface.onBase)),
          ),
        ]),
        SizedBox(height: t.space.md),
        if (e.kind == _Kind.device)
          ..._deviceControls(t, e)
        else
          ..._templateControls(context, t, e.tag!),
        SizedBox(height: t.space.md),
        _preview(t, e),
      ],
    );
  }

  List<Widget> _deviceControls(HcTokens t, _Entry e) {
    final types = <(String, String, IconData)>[
      ('changes', 'Changes', Icons.change_circle_outlined),
      ('changes_to', 'Changes to…', Icons.rule_outlined),
      ('avail', 'Comes online / offline', Icons.wifi_tethering),
      if (e.numericAttrs.isNotEmpty)
        ('threshold', 'Crosses a threshold', Icons.show_chart_outlined),
      // Offered per device rather than always: a button trigger on a lamp and
      // a battery trigger on a mains-powered switch are controls that can
      // never fire.
      if (e.isButtonDevice)
        ('button', 'A button is pressed', Icons.radio_button_checked),
      if (e.hasBattery) ...[
        ('battery_low', 'Battery runs low', Icons.battery_alert_outlined),
        ('battery_ok', 'Battery recovers', Icons.battery_full_outlined),
      ],
    ];
    return [
      const RailLabel('When it…'),
      SizedBox(height: t.space.sm),
      Column(
        children: [
          for (var i = 0; i < types.length; i += 2)
            Padding(
              padding: EdgeInsets.only(bottom: t.space.xs),
              child: Row(children: [
                Expanded(child: _typeChip(t, types[i])),
                SizedBox(width: t.space.xs),
                Expanded(
                    child: i + 1 < types.length
                        ? _typeChip(t, types[i + 1])
                        : const SizedBox()),
              ]),
            ),
        ],
      ),
      SizedBox(height: t.space.md),
      ..._typeParams(t, e),
    ];
  }

  Widget _typeChip(HcTokens t, (String, String, IconData) ty) {
    final on = _ttype == ty.$1;
    final ac = t.accent.active;
    return Material(
      color: on ? ac.withValues(alpha: 0.14) : t.surface.sunken,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: () => setState(() => _ttype = ty.$1),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color: on ? ac.withValues(alpha: 0.4) : t.stroke.hairline),
          ),
          child: Row(children: [
            Icon(ty.$3, size: 15, color: on ? ac : t.surface.onBaseMuted),
            SizedBox(width: t.space.xs),
            Expanded(
              child: Text(ty.$2,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                      color: on ? ac : t.surface.onBaseMuted)),
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _typeParams(HcTokens t, _Entry e) {
    switch (_ttype) {
      case 'button':
        return [
          const RailLabel('Button'),
          SizedBox(height: t.space.sm),
          if (e.buttons.isEmpty)
            TextFormField(
              key: ValueKey('btn:${e.ref}'),
              initialValue: _button,
              keyboardType: TextInputType.number,
              decoration: fieldDecoration(t,
                  hint: 'Button number — blank means any button'),
              onChanged: (v) => setState(() => _button = v),
            )
          else
            _dropdown(t, _button.isEmpty ? '· any ·' : _button,
                ['· any ·', ...e.buttons],
                (v) => setState(() => _button = v == '· any ·' ? '' : v!)),
          SizedBox(height: t.space.xs),
          Text(
            e.buttons.isEmpty
                ? 'This device has not reported its buttons, so they cannot be '
                    'listed — enter the number, or leave it blank for any.'
                : 'Only buttons this device has reported are listed.',
            style: TextStyle(
                fontSize: 11, height: 1.4, color: t.surface.onBaseMuted),
          ),
          SizedBox(height: t.space.md),
          const RailLabel('Press type'),
          SizedBox(height: t.space.sm),
          _dropdown(t, _buttonEvent, buttonEventValues,
              (v) => setState(() => _buttonEvent = v!)),
        ];
      case 'battery_low':
      case 'battery_ok':
        return [
          _note(
              t,
              _ttype == 'battery_low'
                  ? 'Fires once when this device reports its battery has fallen '
                      'below the alert threshold.'
                  : 'Fires when the battery reads healthy again after being low.'),
        ];
      case 'changes':
        return [
          const RailLabel('Attribute'),
          SizedBox(height: t.space.sm),
          _dropdown(t, _attr.isEmpty ? '· any ·' : _attr,
              ['· any ·', ...e.attrs], (v) {
            setState(() => _attr = v == '· any ·' ? '' : v!);
          }),
        ];
      case 'changes_to':
        final attr = _attr.isEmpty ? e.attrs.first : _attr;
        final transitions = _boolTransitions(e, attr);
        return [
          const RailLabel('Attribute'),
          SizedBox(height: t.space.sm),
          _dropdown(t, attr, e.attrs, (v) {
            setState(() {
              _attr = v!;
              // The value belongs to the attribute it was chosen for. Keeping
              // it across a change left `true` sitting in a text attribute's
              // box, producing a trigger that could never fire.
              _valueText = '';
            });
          }),
          SizedBox(height: t.space.md),
          if (transitions != null) ...[
            const RailLabel('Fires when it'),
            SizedBox(height: t.space.sm),
            // A boolean attribute is TWO events, not one. Offering only the
            // attribute and a value box made "the door closes" reachable only
            // by typing `false` or wrapping the trigger in a Not — a logic gate
            // standing in for a word the device already knows. The pair of
            // names comes from the plugin when it declares them, and from the
            // client lexicon when it does not; either way there are two rows.
            Row(children: [
              for (var i = 0; i < transitions.length; i++) ...[
                if (i > 0) SizedBox(width: t.space.xs),
                _toggle(
                  t,
                  _sentenceCase(transitions[i].state.transition),
                  _valueText == '${transitions[i].value}',
                  () => setState(
                      () => _valueText = '${transitions[i].value}'),
                ),
              ],
            ]),
          ] else ...[
            const RailLabel('Changes to'),
            SizedBox(height: t.space.sm),
            TextFormField(
              key: ValueKey('to:${e.ref}:$attr'),
              initialValue: _valueText,
              decoration: fieldDecoration(
                t,
                hint: _valueHint(e, attr),
              ),
              onChanged: (v) => setState(() => _valueText = v),
            ),
          ],
        ];
      case 'avail':
        return [
          const RailLabel('Fires when it'),
          SizedBox(height: t.space.sm),
          Row(children: [
            _toggle(t, 'Comes online', _availOn,
                () => setState(() => _availOn = true)),
            SizedBox(width: t.space.xs),
            _toggle(t, 'Goes offline', !_availOn,
                () => setState(() => _availOn = false)),
          ]),
        ];
      case 'threshold':
        return [
          const RailLabel('Attribute'),
          SizedBox(height: t.space.sm),
          _dropdown(t, _attr.isEmpty ? e.numericAttrs.first : _attr,
              e.numericAttrs, (v) => setState(() => _attr = v!)),
          SizedBox(height: t.space.md),
          const RailLabel('When it'),
          SizedBox(height: t.space.sm),
          _dropdown(t, _thOp, [for (final o in _thresholdOps) o.$1],
              (v) => setState(() => _thOp = v!),
              labelFor: (k) => _thresholdOps.firstWhere((o) => o.$1 == k).$2),
          SizedBox(height: t.space.md),
          const RailLabel('Value'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: _valueText,
            decoration: fieldDecoration(t, hint: 'a number'),
            keyboardType: TextInputType.number,
            onChanged: (v) => setState(() => _valueText = v),
          ),
        ];
    }
    return const [];
  }

  Widget _note(HcTokens t, String text) => Container(
        width: double.infinity,
        padding: EdgeInsets.all(t.space.md),
        decoration: BoxDecoration(
          color: t.surface.sunken,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.stroke.hairline),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 12.5, height: 1.5, color: t.surface.onBaseMuted)),
      );

  List<Widget> _templateControls(BuildContext context, HcTokens t, String tag) {
    switch (tag) {
      case 'SystemStarted':
        return [
          _note(t,
              'Fires once each time HomeCore starts — useful for restoring state '
              'after a restart.'),
        ];
      case 'Cron':
        return [
          const RailLabel('Cron expression'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: _cron,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: fieldDecoration(t, hint: 'sec min hour day month wday'),
            onChanged: (v) => setState(() => _cron = v),
          ),
          SizedBox(height: t.space.sm),
          Text(
            'Six fields, seconds first. "0 0 7 * * *" is 07:00 every day. Use '
            'Every N or At a time of day unless you need a schedule they '
            'cannot express.',
            style: TextStyle(
                fontSize: 11, height: 1.4, color: t.surface.onBaseMuted),
          ),
        ];
      case 'Periodic':
        return [
          const RailLabel('Every'),
          SizedBox(height: t.space.sm),
          Row(children: [
            SizedBox(
              width: 96,
              child: TextFormField(
                key: const ValueKey('every_n'),
                initialValue: '$_everyN',
                keyboardType: TextInputType.number,
                decoration: fieldDecoration(t),
                onChanged: (v) =>
                    setState(() => _everyN = int.tryParse(v.trim()) ?? _everyN),
              ),
            ),
            SizedBox(width: t.space.sm),
            Expanded(
              child: _dropdown(t, _unit, periodicUnitValues,
                  (v) => setState(() => _unit = v!)),
            ),
          ]),
        ];
      case 'CalendarEvent':
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
          SizedBox(height: t.space.md),
          const RailLabel('Offset (minutes)'),
          SizedBox(height: t.space.sm),
          TextFormField(
            key: const ValueKey('cal_offset'),
            initialValue: '$_offsetMin',
            keyboardType: TextInputType.number,
            decoration:
                fieldDecoration(t, hint: 'Negative fires before the event'),
            onChanged: (v) =>
                setState(() => _offsetMin = int.tryParse(v.trim()) ?? 0),
          ),
        ];
      case 'HubVariableChanged':
        return [
          const RailLabel('Variable name'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: _varName,
            decoration:
                fieldDecoration(t, hint: 'e.g. guests_home (blank = any)'),
            onChanged: (v) => setState(() => _varName = v),
          ),
        ];
      case 'CustomEvent':
        return [
          const RailLabel('Event type'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: _eventType,
            decoration: fieldDecoration(t, hint: 'e.g. doorbell_pressed'),
            onChanged: (v) => setState(() => _eventType = v),
          ),
        ];
      case 'MqttMessage':
        return [
          const RailLabel('Topic pattern'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: _topic,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: fieldDecoration(t, hint: 'e.g. shellies/+/relay/0'),
            onChanged: (v) => setState(() => _topic = v),
          ),
          SizedBox(height: t.space.sm),
          Text('MQTT wildcards: + for one level, # for the rest.',
              style: TextStyle(
                  fontSize: 11, height: 1.4, color: t.surface.onBaseMuted)),
        ];
      case 'TimeOfDay':
        return [
          const RailLabel('Time'),
          SizedBox(height: t.space.sm),
          _timeBtn(context, t),
          SizedBox(height: t.space.md),
          const RailLabel('On these days'),
          SizedBox(height: t.space.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in _weekdays)
                _dayChip(t, d, _days.contains(d), () {
                  setState(() =>
                      _days.contains(d) ? _days.remove(d) : _days.add(d));
                }),
            ],
          ),
        ];
      case 'SunEvent':
        return [
          const RailLabel('Event'),
          SizedBox(height: t.space.sm),
          _dropdown(t, _sun, _sunEvents, (v) => setState(() => _sun = v!)),
          SizedBox(height: t.space.md),
          const RailLabel('Offset (minutes, ± around the event)'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: '$_offset',
            decoration: fieldDecoration(t, hint: '0 = exactly at the event'),
            keyboardType: TextInputType.number,
            onChanged: (v) => setState(() => _offset = int.tryParse(v) ?? 0),
          ),
        ];
      case 'ModeChanged':
        return [
          const RailLabel('Mode'),
          SizedBox(height: t.space.sm),
          if (widget.refs.modes.isEmpty)
            Text('No modes defined.',
                style: TextStyle(color: t.surface.onBaseMuted, fontSize: 12.5))
          else
            _dropdown(
                t,
                _modeId,
                [for (final m in widget.refs.modes) m.id],
                (v) => setState(() => _modeId = v!),
                labelFor: (id) => widget.refs.modes
                    .firstWhere((m) => m.id == id,
                        orElse: () => (id: id, name: id))
                    .name),
          SizedBox(height: t.space.md),
          const RailLabel('Fires when it turns'),
          SizedBox(height: t.space.sm),
          Row(children: [
            _toggle(t, 'On', _modeOn, () => setState(() => _modeOn = true)),
            SizedBox(width: t.space.xs),
            _toggle(t, 'Off', !_modeOn, () => setState(() => _modeOn = false)),
          ]),
        ];
      case 'WebhookReceived':
        return [
          const RailLabel('Webhook path'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: _path,
            decoration: fieldDecoration(t, hint: 'e.g. front-door'),
            onChanged: (v) => setState(() => _path = v),
          ),
        ];
      default: // ManualTrigger
        return [
          Container(
            padding: EdgeInsets.all(t.space.md),
            decoration: BoxDecoration(
              color: t.surface.sunken,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.stroke.hairline),
            ),
            child: Text(
                'Runs only when you press Run, or when another rule calls it. '
                'No parameters.',
                style: TextStyle(
                    fontSize: 12.5, height: 1.5, color: t.surface.onBaseMuted)),
          ),
        ];
    }
  }

  // -- small controls ------------------------------------------------------

  Widget _timeBtn(BuildContext context, HcTokens t) {
    final parts = _time.split(':');
    final h = int.tryParse(parts.elementAtOrNull(0) ?? '') ?? 0;
    final m = int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0;
    final hhmm =
        '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    return Material(
      color: t.surface.sunken,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () async {
          final picked = await showTimePicker(
              context: context, initialTime: TimeOfDay(hour: h, minute: m));
          if (picked != null) {
            setState(() => _time = '${picked.hour.toString().padLeft(2, '0')}:'
                '${picked.minute.toString().padLeft(2, '0')}:00');
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: t.stroke.hairline),
          ),
          child: Row(children: [
            Icon(Icons.schedule_outlined, size: 16, color: t.surface.onBaseMuted),
            const Spacer(),
            Text(hhmm,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: t.accent.active)),
          ]),
        ),
      ),
    );
  }

  Widget _dayChip(HcTokens t, String day, bool on, VoidCallback onTap) {
    final ac = t.accent.active;
    return Material(
      color: on ? ac.withValues(alpha: 0.14) : t.surface.raised,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: on ? ac.withValues(alpha: 0.4) : t.stroke.hairline),
          ),
          child: Text(day,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: on ? ac : t.surface.onBaseMuted)),
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

  Widget _toggle(HcTokens t, String label, bool on, VoidCallback onTap) {
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
    Widget word(String s) => Text(s,
        style: TextStyle(fontSize: 13.5, color: t.surface.onBaseMuted));
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
    final a = t.accent.active;
    final b = t.accent.primary;
    String hhmm(String v) => v.split(':').take(2).join(':');

    List<Widget> parts() {
      if (e.kind == _Kind.device) {
        final dev = tok(e.label, b);
        switch (_ttype) {
          case 'changes':
            return [
              word('when'),
              dev,
              _attr.isEmpty
                  ? word('changes')
                  : tok('${_attr.replaceAll('_', ' ')} changes', a),
            ];
          case 'changes_to':
            return [
              word('when'),
              dev,
              tok(_attr.replaceAll('_', ' '), a),
              word('changes to'),
              tok(_valueText.isEmpty ? '…' : _valueText, a),
            ];
          case 'avail':
            return [
              word('when'),
              dev,
              tok(_availOn ? 'comes online' : 'goes offline', a),
            ];
          case 'button':
            return [
              word('when'),
              tok(_button.isEmpty ? 'any button' : 'button $_button', a),
              word('on'),
              dev,
              tok(
                  switch (_buttonEvent) {
                    'Pushed' => 'is pushed',
                    'Held' => 'is held',
                    'DoubleTapped' => 'is double-tapped',
                    _ => 'is released',
                  },
                  a),
            ];
          case 'battery_low':
            return [word("when"), dev, tok('runs low on battery', a)];
          case 'battery_ok':
            return [word("when"), dev, tok('recovers its battery', a)];
          case 'threshold':
            final verb = _thresholdOps.firstWhere((o) => o.$1 == _thOp).$2;
            return [
              word('when'),
              dev,
              word("'s"),
              tok(_attr.replaceAll('_', ' '), a),
              tok(verb, a),
              tok(_valueText.isEmpty ? '…' : _valueText, a),
            ];
        }
        return [dev];
      }
      switch (e.tag) {
        case 'TimeOfDay':
          return [
            word('at'),
            tok(hhmm(_time), a),
            word(_days.length == 7 ? 'every day' : _days.join(', ')),
          ];
        case 'SunEvent':
          return [
            word('at'),
            tok(_sun.toLowerCase(), a),
            if (_offset != 0)
              tok('${_offset > 0 ? '+' : ''}$_offset min', a),
          ];
        case 'ModeChanged':
          final name = widget.refs.modes
              .firstWhere((m) => m.id == _modeId,
                  orElse: () => (id: _modeId, name: 'a mode'))
              .name;
          return [
            word('when'),
            tok(name, b),
            word('turns'),
            tok(_modeOn ? 'on' : 'off', a),
          ];
        case 'WebhookReceived':
          return [
            word('when the webhook'),
            tok(_path.isEmpty ? '…' : _path, a),
            word('is called'),
          ];
        case 'Cron':
          return [word('on the schedule'), tok(_cron.trim().isEmpty ? '…' : _cron.trim(), a)];
        case 'Periodic':
          return [
            word('every'),
            tok('$_everyN ${_unit.toLowerCase()}', a),
          ];
        case 'CalendarEvent':
          return [
            word('on a calendar event'),
            if (_titleContains.trim().isNotEmpty) ...[
              word('matching'),
              tok(_titleContains.trim(), a)
            ],
            if (_offsetMin != 0)
              tok('${_offsetMin > 0 ? '+' : ''}$_offsetMin min', a),
          ];
        case 'HubVariableChanged':
          return [
            word('when the hub variable'),
            tok(_varName.trim().isEmpty ? 'any' : _varName.trim(), b),
            word('changes'),
          ];
        case 'SystemStarted':
          return [word('when HomeCore starts')];
        case 'CustomEvent':
          return [
            word('on the event'),
            tok(_eventType.trim().isEmpty ? '…' : _eventType.trim(), a),
          ];
        case 'MqttMessage':
          return [
            word('on an MQTT message to'),
            tok(_topic.trim().isEmpty ? '…' : _topic.trim(), a),
          ];
        default:
          return [word('run by hand, or from another rule')];
      }
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
              children: parts()),
        ],
      ),
    );
  }
}
