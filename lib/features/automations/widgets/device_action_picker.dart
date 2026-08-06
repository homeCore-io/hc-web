import 'package:flutter/material.dart';

import '../../../core/devices/presentation.dart';
import '../../../core/models/device_state.dart';
import '../../../core/rules/node.dart';
import '../../../core/rules/schema.dart';
import '../../../core/text/humanize.dart';
import '../../../design/tokens.dart';
import '../device_commands.dart';
import 'device_picker_shell.dart';
import 'editor_style.dart';
import 'rule_refs.dart';

/// The multi-pane "Add action" picker — the single entry point to a rule's THEN
/// clause, covering the whole action vocabulary.
///
/// Rail categories fall into two kinds, exactly as in the condition picker:
///  * **device** categories (lights … timers, scenes, modes) list real things to
///    control, then a per-device command grid with a typed control;
///  * **template** categories (Flow, Wait, Notify, Variables, Rules, Device
///    extras, Integration) list action *types* whose detail pane is either a
///    small form (wait for N, notify with this message, …) or — for the
///    structural and rarely-used ones — a blank node the tree grows in place.
///
/// It returns a fully-built `HcNode`, so the caller drops it straight into the
/// rule. Sensors never appear: they report state, so they belong in conditions.
///
/// Shown with `showDialog<HcNode>`; the device command payloads come from
/// [commandsFor] (see `device_commands.dart`).
class DeviceActionPicker extends StatefulWidget {
  const DeviceActionPicker({super.key, required this.refs, this.initial});

  final RuleRefs refs;

  /// An existing device-control action to edit. When set, the picker opens with
  /// its device, command and value pre-selected, so editing a colour / favourite
  /// / grouping action reuses the typed builder instead of a raw-JSON chip.
  final HcNode? initial;

  @override
  State<DeviceActionPicker> createState() => _DeviceActionPickerState();
}

enum _Kind { device, template }

/// One selectable thing: a device / scene / mode (carrying the commands it can
/// perform, already resolved), or an action *template* (carrying its variant
/// tag).
class _Entry {
  _Entry({
    required this.label,
    required this.ref,
    required this.sub,
    required this.icon,
    required this.bucket,
    required this.room,
    required this.order,
    this.kind = _Kind.device,
    this.commands = const [],
    this.tag,
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

  /// Declaration order — templates keep the order they are listed in rather
  /// than being alphabetised, because that order is editorial (the common ones
  /// first).
  final int order;

  final List<DeviceCommand> commands;

  /// Template entries only: the action variant tag (`Delay`, `Notify`, …).
  final String? tag;

  final DeviceState? device;
  final String? chip;
  final PickerTone? chipTone;
}

const _cats = [
  PickerCat('all', 'All controllable', Icons.list_alt_outlined, 'Quick'),
  PickerCat('light', 'Lights', Icons.lightbulb_outline, 'Controls'),
  PickerCat(
      'switch', 'Switches & Outlets', Icons.toggle_on_outlined, 'Controls'),
  PickerCat('cover', 'Shades & Covers', Icons.blinds_outlined, 'Controls'),
  PickerCat('lock', 'Locks', Icons.lock_outline, 'Controls'),
  PickerCat('climate', 'Climate', Icons.hvac_outlined, 'Controls'),
  PickerCat('media', 'Media players', Icons.speaker_outlined, 'Controls'),
  PickerCat('scene', 'Scenes', Icons.auto_awesome_outlined, 'Run'),
  PickerCat('timer', 'Timers', Icons.timer_outlined, 'Run'),
  PickerCat('mode', 'Modes', Icons.brightness_4_outlined, 'Run'),
  PickerCat('flow', 'Flow & branching', Icons.alt_route_outlined, 'Logic'),
  PickerCat('wait', 'Waiting', Icons.hourglass_empty_outlined, 'Logic'),
  PickerCat('notify', 'Notify & log', Icons.notifications_outlined, 'Tell'),
  PickerCat('vars', 'Variables & script', Icons.data_object_outlined, 'Data'),
  PickerCat('rules', 'Other rules', Icons.playlist_play_outlined, 'Data'),
  PickerCat('extras', 'Device extras', Icons.tune_outlined, 'Advanced'),
  PickerCat('integration', 'Integrations', Icons.hub_outlined, 'Advanced'),
];

/// Template entries: action types with no device to pick. The order here is the
/// order they appear in the list — commonest first inside each category.
///
/// Every action variant that the device panes cannot produce must appear here,
/// or it becomes unreachable from the editor (`kActionTemplateTags` is asserted
/// against `kActions` in the tests).
const _templates = <(String bucket, String tag, String label, IconData icon)>[
  ('flow', 'Conditional', 'If / else', Icons.alt_route_outlined),
  ('flow', 'Parallel', 'Run steps at the same time', Icons.call_split_outlined),
  ('flow', 'RepeatCount', 'Repeat a number of times', Icons.repeat_outlined),
  ('flow', 'RepeatWhile', 'Repeat while…', Icons.loop_outlined),
  ('flow', 'RepeatUntil', 'Repeat until…', Icons.loop_outlined),
  ('flow', 'StopRuleChain', 'Stop the rule chain', Icons.stop_circle_outlined),
  ('flow', 'ExitRule', 'Exit this rule', Icons.logout_outlined),
  ('wait', 'Delay', 'Wait a while', Icons.hourglass_empty_outlined),
  ('wait', 'WaitForEvent', 'Wait for an event', Icons.hourglass_top_outlined),
  ('wait', 'WaitForExpression', 'Wait for an expression', Icons.code_outlined),
  ('wait', 'DelayPerMode', 'Wait, per mode', Icons.brightness_4_outlined),
  ('wait', 'CancelDelays', 'Cancel pending waits', Icons.cancel_outlined),
  (
    'wait',
    'CancelRuleTimers',
    "Cancel a rule's timers",
    Icons.timer_off_outlined
  ),
  ('notify', 'Notify', 'Send a notification', Icons.notifications_outlined),
  ('notify', 'LogMessage', 'Write to the log', Icons.article_outlined),
  ('notify', 'Comment', 'Leave a comment', Icons.sticky_note_2_outlined),
  ('vars', 'SetVariable', 'Set a rule variable', Icons.data_object_outlined),
  ('vars', 'SetHubVariable', 'Set a hub variable', Icons.storage_outlined),
  ('vars', 'SetPrivateBoolean', 'Set a private flag', Icons.flag_outlined),
  ('vars', 'RunScript', 'Run a Rhai script', Icons.code_outlined),
  (
    'rules',
    'RunRuleActions',
    "Run another rule's actions",
    Icons.playlist_play_outlined
  ),
  ('rules', 'PauseRule', 'Pause a rule', Icons.pause_circle_outline),
  ('rules', 'ResumeRule', 'Resume a rule', Icons.play_circle_outline),
  ('extras', 'FadeDevice', 'Fade a light over time', Icons.gradient_outlined),
  (
    'extras',
    'SetDeviceStatePerMode',
    'Set device state, per mode',
    Icons.tune_outlined
  ),
  (
    'extras',
    'CaptureDeviceState',
    'Capture device state',
    Icons.bookmark_add_outlined
  ),
  (
    'extras',
    'RestoreDeviceState',
    'Restore device state',
    Icons.restore_outlined
  ),
  (
    'extras',
    'ActivateScenePerMode',
    'Activate a scene, per mode',
    Icons.auto_awesome_outlined
  ),
  ('integration', 'PublishMqtt', 'Publish MQTT', Icons.podcasts_outlined),
  ('integration', 'CallService', 'Call an HTTP service', Icons.http_outlined),
  ('integration', 'FireEvent', 'Fire a custom event', Icons.bolt_outlined),
  ('integration', 'PingHost', 'Ping a host', Icons.network_check_outlined),
];

/// The action variants reachable through the picker's template list. The device
/// panes cover the rest (`SetDeviceState` and `SetMode`).
final kActionTemplateTags = [for (final t in _templates) t.$2];

/// Variants the device / scene / mode panes build directly.
const kActionDeviceTags = ['SetDeviceState', 'SetMode'];

/// facet → category bucket. Null buckets (sensors) never build an entry.
String? _bucketOf(DeviceFacet f) => switch (f) {
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
      DeviceFacet.scene => 'scene',
      DeviceFacet.timer => 'timer',
      _ => null,
    };

const _swatches = <(String, Color)>[
  ('Red', Color(0xFFFF5C5C)),
  ('Coral', Color(0xFFFF7E67)),
  ('Amber', Color(0xFFFFB661)),
  ('Gold', Color(0xFFFFD479)),
  ('Lime', Color(0xFFC6E86B)),
  ('Green', Color(0xFF6FD1A6)),
  ('Teal', Color(0xFF4FD1C5)),
  ('Cyan', Color(0xFF5BE0E6)),
  ('Sky', Color(0xFF7CC4FF)),
  ('Blue', Color(0xFF6C8CFF)),
  ('Indigo', Color(0xFF8A7CFF)),
  ('Violet', Color(0xFFB69CFF)),
  ('Magenta', Color(0xFFE86BC6)),
  ('Pink', Color(0xFFFF8FB3)),
  ('Warm White', Color(0xFFFFE8C7)),
  ('Cool White', Color(0xFFE8F1FF)),
];

const _durations = <(String, int)>[
  ('1 min', 60),
  ('5 min', 300),
  ('10 min', 600),
  ('30 min', 1800),
  ('1 hour', 3600),
];

class _DeviceActionPickerState extends State<DeviceActionPicker> {
  bool _byRoom = false;
  String _cat = 'all';
  String _room = '';
  String _query = '';

  _Entry? _sel;
  DeviceCommand? _cmd;

  /// Chosen values, keyed by the payload key each control fills. A
  /// hand-written command has at most one entry; a declared action has one
  /// per parameter — "press {key} {count} times" needs both or it silently
  /// drops the count.
  final Map<String, Object?> _values = {};

  // Template detail state, shared where the control is the same.
  int _secs = 300;
  int _repeatCount = 2;
  String _message = '';
  String _title = '';
  String _channel = 'all';
  String _level = 'Info';
  String _name = '';
  String _varValue = '';
  String _varOp = 'Set';
  bool _boolOn = true;
  final _secsCtl = TextEditingController(text: '300');

  late final List<_Entry> _entries = _buildEntries();
  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _prefill(widget.initial!);
  }

  @override
  void dispose() {
    _secsCtl.dispose();
    super.dispose();
  }

  /// Reverse of the command builders: from an existing node, pre-select the
  /// device, the command it performs, and that command's current value.
  void _prefill(HcNode node) {
    final ref = (node.tag == 'SetMode' ? node['mode_id'] : node['device_id'])
        as String?;
    if (ref == null) return;
    final entry = _firstOrNull(_entries, (e) => e.ref == ref);
    if (entry == null) return;
    _sel = entry;

    // A declared action round-trips exactly: its id names the command and its
    // payload keys are the parameter names, so nothing has to be reverse
    // engineered the way the hand-written payloads do below.
    final state = (node['state'] as Map?)?.cast<String, Object?>() ?? const {};
    if (state['action'] case final String id) {
      final declared = _firstOrNull(entry.commands, (c) => c.key == 'act:$id');
      if (declared != null) {
        _cmd = declared;
        _resetValues();
        for (final pr in declared.params) {
          final v = state[pr.name];
          if (v != null) {
            _values[pr.name] = pr.kind == CmdParamKind.select ? '$v' : v;
          }
        }
        return;
      }
    }

    final (cmd, value) = _matchCommand(entry, node);
    _cmd = cmd ?? entry.commands.first;
    _resetValues();
    if (value != null && _cmd!.params.isNotEmpty) {
      _values[_cmd!.param.name] = value;
    }
    for (final pr in _cmd!.params) {
      if (pr.kind == CmdParamKind.color && _values[pr.name] is! Color) {
        _values[pr.name] = _swatches[2].$2;
      }
    }
  }

  (DeviceCommand?, Object?) _matchCommand(_Entry e, HcNode node) {
    DeviceCommand? byKey(String k) =>
        _firstOrNull(e.commands, (c) => c.key == k);
    if (node.tag == 'SetMode') return (byKey('on'), null);

    final s = (node['state'] as Map?)?.cast<String, Object?>() ?? const {};
    if (s['action'] is String) {
      switch (s['action'] as String) {
        case 'play':
          return (byKey('play'), null);
        case 'pause':
          return (byKey('pause'), null);
        case 'next':
          return (byKey('next'), null);
        case 'previous':
          return (byKey('previous'), null);
        case 'set_volume':
          return (byKey('set_volume'), s['volume']);
        case 'play_favorite':
          return (byKey('play_favorite'), s['favorite']);
        case 'play_playlist':
          return (byKey('play_playlist'), s['playlist']);
        case 'set_shuffle':
          return (byKey('set_shuffle'), s['shuffle'] == true ? 'on' : 'off');
        case 'set_setpoint':
          return (byKey('set_temp'), s['value']);
        case 'set_mode':
          return (byKey('set_mode'), s['value']);
        case 'join':
          final peer =
              _firstOrNull(_entries, (x) => x.device?.id == s['coordinator']);
          return (byKey('group'), peer?.label);
      }
    }
    if (s.containsKey('brightness_pct')) {
      return (byKey('brightness'), s['brightness_pct']);
    }
    if (s.containsKey('color_xy')) return (byKey('color'), null);
    if (s.containsKey('color_temp')) return (byKey('white'), s['color_temp']);
    if (s.containsKey('locked')) {
      return (s['locked'] == true ? byKey('lock') : byKey('unlock'), null);
    }
    if (s.containsKey('raise')) return (byKey('open'), null);
    if (s.containsKey('lower')) return (byKey('close'), null);
    if (s.containsKey('stop')) return (byKey('stop'), null);
    if (s.containsKey('position')) return (byKey('position'), s['position']);
    if (s.containsKey('activate')) return (byKey('activate'), null);
    if (s.containsKey('command')) {
      final c = s['command'];
      if (c == 'start') return (byKey('start'), s['duration_secs']);
      if (c == 'restart') return (byKey('restart'), s['duration_secs']);
      return (byKey('stop'), null);
    }
    if (s.containsKey('on')) {
      return (s['on'] == true ? byKey('on') : byKey('off'), null);
    }

    // A schema-derived command: one attribute, one value. Match on what each
    // command declares it writes rather than on a hand-listed key, so editing
    // keeps working as plugins add attributes.
    if (s.length == 1) {
      final attr = s.keys.first;
      final value = s.values.first;
      final matches = e.commands.where((c) => c.writes == attr).toList();
      if (matches.length == 1) return (matches.first, value);
      // A bool attribute contributes two commands; the value picks which.
      final exact = _firstOrNull(matches, (c) => c.key == 'attr:$attr:$value');
      if (exact != null) return (exact, null);
    }
    return (null, null);
  }

  // -- entry construction --------------------------------------------------

  List<_Entry> _buildEntries() {
    final out = <_Entry>[];
    final seen = <String>{};
    var order = 0;

    final speakers = widget.refs.devices
        .where((x) => facetOf(x, x.schema) == DeviceFacet.mediaPlayer)
        .toList();

    for (final d in widget.refs.devices) {
      final facet = facetOf(d, d.schema);
      final peers = facet == DeviceFacet.mediaPlayer
          ? speakers.where((x) => x.id != d.id).toList()
          : const <DeviceState>[];
      final cmds = commandsFor(d, mediaPeers: peers);
      if (cmds.isEmpty) continue; // sensors and non-actuators
      final bucket = _bucketOf(facet) ?? 'switch';
      seen.add(d.ruleReference);
      final (chip, tone) = _deviceChip(d);
      out.add(_Entry(
        label: d.displayName,
        ref: d.ruleReference,
        sub: d.canonicalName ?? d.id,
        icon: facetOf(d, d.schema).icon,
        bucket: bucket,
        room: (d.effectiveArea?.isNotEmpty ?? false)
            ? humanize(d.effectiveArea)
            : 'No room',
        order: order++,
        commands: cmds,
        device: d,
        chip: chip,
        chipTone: tone,
      ));
    }

    // Native scenes (the scenes list) that aren't already devices.
    for (final s in widget.refs.scenes) {
      if (seen.contains(s.id)) continue;
      out.add(_Entry(
        label: s.name,
        ref: s.id,
        sub: s.id,
        icon: Icons.auto_awesome_outlined,
        bucket: 'scene',
        room: 'Scenes',
        order: order++,
        commands: [
          DeviceCommand(
            key: 'activate',
            label: 'Activate scene',
            icon: Icons.play_arrow_outlined,
            param: const CmdParam.none(),
            build: (_) => activateSceneNode(s.id),
          ),
        ],
      ));
    }

    // Modes.
    for (final m in widget.refs.modes) {
      out.add(_Entry(
        label: m.name,
        ref: m.id,
        sub: m.id,
        icon: Icons.brightness_4_outlined,
        bucket: 'mode',
        room: 'Modes',
        order: order++,
        commands: [
          DeviceCommand(
            key: 'on',
            label: 'Switch to this mode',
            icon: Icons.brightness_4_outlined,
            param: const CmdParam.none(),
            build: (_) => setModeNode(m.id),
          ),
        ],
      ));
    }

    // Everything the device panes cannot express: flow, waiting, notifications,
    // variables, other rules, the device extras and the integrations.
    for (final (bucket, tag, label, icon) in _templates) {
      out.add(_Entry(
        label: label,
        ref: tag,
        sub: '',
        icon: icon,
        bucket: bucket,
        room: '', // flat — the rail already names the category
        order: order++,
        kind: _Kind.template,
        tag: tag,
      ));
    }
    return out;
  }

  (String?, PickerTone?) _deviceChip(DeviceState d) {
    if (d.isMediaPlayer) {
      return d.playbackState == 'playing'
          ? ('playing', PickerTone.play)
          : (d.playbackState, PickerTone.off);
    }
    final s = d.state;
    if (s['locked'] == true) return ('locked', PickerTone.ok);
    if (s['locked'] == false) return ('unlocked', PickerTone.off);
    if (s['on'] == true) {
      final b = s['brightness_pct'];
      return (b is num ? 'on · ${b.round()}%' : 'on', PickerTone.on);
    }
    if (s['on'] == false) return ('off', PickerTone.off);
    final pos = s['position'];
    if (pos is num) {
      return (
        pos <= 0 ? 'closed' : 'open · ${pos.round()}%',
        pos <= 0 ? PickerTone.off : PickerTone.on
      );
    }
    return (null, null);
  }

  // -- filtering -----------------------------------------------------------

  List<_Entry> get _pool {
    var p = _entries.where((e) {
      if (_byRoom) return e.room == _room;
      if (_cat == 'all') return e.device != null; // devices only under "all"
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
    // Templates are editorially ordered — commonest first — so they are never
    // alphabetised.
    if (a.kind == _Kind.template || b.kind == _Kind.template) {
      return a.order.compareTo(b.order);
    }
    if (!_byRoom && a.room != b.room) return a.room.compareTo(b.room);
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  }

  List<String> get _rooms {
    final rs = _entries
        .where((e) => e.device != null)
        .map((e) => e.room)
        .toSet()
        .toList()
      ..sort();
    return [...rs, 'Scenes', 'Modes'];
  }

  int _count(String cat) => cat == 'all'
      ? _entries.where((e) => e.device != null).length
      : _entries.where((e) => e.bucket == cat).length;

  // -- selection -----------------------------------------------------------

  void _select(_Entry e) {
    setState(() {
      _sel = e;
      if (e.kind == _Kind.template) {
        _cmd = null;
        _resetTemplate();
        return;
      }
      _cmd = e.commands.first;
      _resetValues();
    });
  }

  void _resetTemplate() {
    _secs = 300;
    _secsCtl.text = '300';
    _repeatCount = 2;
    _message = '';
    _title = '';
    _channel = 'all';
    _level = 'Info';
    _name = '';
    _varValue = '';
    _varOp = 'Set';
    _boolOn = true;
  }

  /// The node the footer button would add. Null while nothing usable is chosen —
  /// which is what disables the button.
  HcNode? _result() {
    final e = _sel;
    if (e == null) return null;
    if (e.kind == _Kind.device) {
      final c = _cmd;
      if (c == null) return null;
      // A required parameter with nothing in it disables the button rather
      // than letting a command through that the plugin would reject.
      if (c.missingRequirement(_values) != null) return null;
      return c.buildWith(_values);
    }
    return _templateNode(e.tag!);
  }

  HcNode? _templateNode(String tag) {
    switch (tag) {
      case 'Delay':
        return HcNode('Delay', {'duration_secs': _secs, 'cancelable': false});
      case 'RepeatCount':
        return HcNode(
            'RepeatCount', {'count': _repeatCount, 'actions': <HcNode>[]});
      case 'Notify':
        if (_message.trim().isEmpty) return null;
        return HcNode('Notify', {
          'channel': _channel.trim().isEmpty ? 'all' : _channel.trim(),
          'message': _message.trim(),
          if (_title.trim().isNotEmpty) 'title': _title.trim(),
        });
      case 'LogMessage':
        if (_message.trim().isEmpty) return null;
        return HcNode(
            'LogMessage', {'message': _message.trim(), 'level': _level});
      case 'Comment':
        if (_message.trim().isEmpty) return null;
        return HcNode('Comment', {'text': _message.trim()});
      case 'SetVariable':
      case 'SetHubVariable':
        if (_name.trim().isEmpty) return null;
        return HcNode(tag, {
          'name': _name.trim(),
          'value': _parseValue(_varValue),
          'op': _varOp,
        });
      case 'SetPrivateBoolean':
        if (_name.trim().isEmpty) return null;
        return HcNode('SetPrivateBoolean', {
          'name': _name.trim(),
          'value': _boolOn,
        });
      default:
        // Everything structural or rarely-touched: a blank node the tree grows
        // in place with its own fields.
        final v = kActions[tag];
        return v == null ? null : HcNode.blank(v);
    }
  }

  Object _parseValue(String s) {
    final v = s.trim();
    if (v == 'true') return true;
    if (v == 'false') return false;
    return num.tryParse(v) ?? v;
  }

  void _pickCommand(DeviceCommand c) {
    setState(() {
      _cmd = c;
      _resetValues();
    });
  }

  /// Seed every control with its declared default, so a command with sensible
  /// defaults is addable the moment it is chosen.
  void _resetValues() {
    _values.clear();
    for (final pr in _cmd?.params ?? const <CmdParam>[]) {
      _values[pr.name] =
          pr.kind == CmdParamKind.color ? _swatches[2].$2 : pr.defaultValue;
    }
  }

  // -- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final result = _result();
    return PickerPanel(
      kicker: _editing ? 'EDIT ACTION' : 'ADD ACTION · WHAT SHOULD HAPPEN',
      title: 'What should this rule do?',
      seg: pickerSeg(HcTokens.of(context),
          byRoom: _byRoom,
          onChanged: (v) => setState(() {
                _byRoom = v;
                if (v) _room = _rooms.first;
              })),
      panes: [
        PickerPane(width: 202, compactLabel: 'Where', child: _rail(context)),
        PickerPane(flex: 3, compactLabel: 'What', child: _list(context)),
        PickerPane(flex: 3, compactLabel: 'Details', child: _detail(context)),
      ],
      footerHint: _footHint(),
      primaryLabel: _editing ? 'Save action' : 'Add action',
      onPrimary: result == null ? null : () => Navigator.pop(context, result),
    );
  }

  String _footHint() {
    final devs = _entries.where((e) => e.device != null).length;
    final scenes = _entries.where((e) => e.bucket == 'scene').length;
    final modes = _entries.where((e) => e.bucket == 'mode').length;
    return '$devs controllable devices · $scenes scenes · $modes modes · '
        'flow · waits · notifications · sensors hidden';
  }

  // -- pane 1: rail --------------------------------------------------------

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
    return PickerRail(
      note: 'Sensors are hidden — they belong in conditions, not actions.',
      children: items,
    );
  }

  // -- pane 2: device list -------------------------------------------------

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

  // -- pane 3: action builder ----------------------------------------------

  Widget _detail(BuildContext context) {
    final t = HcTokens.of(context);
    final e = _sel;
    if (e == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(t.space.lg),
          child: Text(
            'Pick what should happen. Devices, scenes and modes are at the top '
            'of the rail; flow, waits, notifications, variables and '
            'integrations are further down.',
            textAlign: TextAlign.center,
            style: t.text.bodySmallStyle
                .copyWith(height: 1.5, color: t.surface.onBaseMuted),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.label,
                    style: t.text.subtitleStyle.copyWith(
                        fontWeight: FontWeight.w600, color: t.surface.onBase)),
                Text(
                    e.kind == _Kind.template
                        ? 'action'
                        : (e.device?.mediaSubtitle ?? e.sub),
                    overflow: TextOverflow.ellipsis,
                    style: t.text.captionStyle
                        .copyWith(color: t.surface.onBaseMuted)),
              ],
            ),
          ),
        ]),
        SizedBox(height: t.space.md),
        if (e.kind == _Kind.template)
          ..._templateControls(t, e.tag!)
        else ...[
          const RailLabel('Command'),
          SizedBox(height: t.space.sm),
          _commandGrid(t, e),
          SizedBox(height: t.space.md),
          if (_cmd!.params.isEmpty)
            _panel(
                t,
                Text(_effectNote(_cmd!),
                    style: t.text.bodySmallStyle
                        .copyWith(height: 1.5, color: t.surface.onBaseMuted)))
          else
            for (final pr in _cmd!.params) ...[
              RailLabel(_paramLabel(_cmd!, pr)),
              SizedBox(height: t.space.sm),
              _paramControl(t, pr),
              if (pr != _cmd!.params.last) SizedBox(height: t.space.md),
            ],
        ],
        SizedBox(height: t.space.md),
        _preview(t, e),
      ],
    );
  }

  // -- template forms ------------------------------------------------------

  List<Widget> _templateControls(HcTokens t, String tag) {
    switch (tag) {
      case 'Delay':
        return [
          const RailLabel('Wait for'),
          SizedBox(height: t.space.sm),
          _panel(
              t,
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(
                  spacing: t.space.xs,
                  runSpacing: t.space.xs,
                  children: [
                    for (final (label, s) in _durations)
                      _Toggle(
                        label: label,
                        selected: _secs == s,
                        onTap: () => setState(() {
                          _secs = s;
                          _secsCtl.text = '$s';
                        }),
                      ),
                  ],
                ),
                SizedBox(height: t.space.sm),
                // A controller, not `initialValue`: the presets above write into
                // this field, and a re-keyed TextFormField would drop the caret
                // on every keystroke.
                TextField(
                  controller: _secsCtl,
                  keyboardType: TextInputType.number,
                  decoration: fieldDecoration(t, hint: 'Seconds'),
                  onChanged: (v) =>
                      setState(() => _secs = int.tryParse(v.trim()) ?? _secs),
                ),
              ])),
        ];
      case 'RepeatCount':
        return [
          const RailLabel('How many times'),
          SizedBox(height: t.space.sm),
          _panel(t, _countStepper(t)),
          SizedBox(height: t.space.md),
          _note(t, 'The steps to repeat go inside the block once it is added.'),
        ];
      case 'Notify':
        return [
          const RailLabel('Message'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: _message,
            decoration:
                fieldDecoration(t, hint: 'e.g. The garage is still open'),
            onChanged: (v) => setState(() => _message = v),
          ),
          SizedBox(height: t.space.md),
          const RailLabel('Title (optional)'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: _title,
            decoration: fieldDecoration(t, hint: 'e.g. Garage'),
            onChanged: (v) => setState(() => _title = v),
          ),
          SizedBox(height: t.space.md),
          const RailLabel('Channel'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: _channel,
            decoration: fieldDecoration(t, hint: '"all" fans out everywhere'),
            onChanged: (v) => setState(() => _channel = v),
          ),
        ];
      case 'LogMessage':
        return [
          const RailLabel('Message'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: _message,
            decoration: fieldDecoration(t, hint: 'What to write to the log'),
            onChanged: (v) => setState(() => _message = v),
          ),
          SizedBox(height: t.space.md),
          const RailLabel('Level'),
          SizedBox(height: t.space.sm),
          _dropdown(t, _level, logLevelValues,
              (v) => setState(() => _level = v ?? _level)),
        ];
      case 'Comment':
        return [
          const RailLabel('Comment'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: _message,
            maxLines: 3,
            decoration:
                fieldDecoration(t, hint: 'A note for whoever reads this rule'),
            onChanged: (v) => setState(() => _message = v),
          ),
        ];
      case 'SetVariable':
      case 'SetHubVariable':
        return [
          const RailLabel('Variable name'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: _name,
            decoration: fieldDecoration(t, hint: 'e.g. guests_home'),
            onChanged: (v) => setState(() => _name = v),
          ),
          SizedBox(height: t.space.md),
          const RailLabel('Operation'),
          SizedBox(height: t.space.sm),
          _dropdown(t, _varOp, variableOpValues,
              (v) => setState(() => _varOp = v ?? _varOp)),
          SizedBox(height: t.space.md),
          const RailLabel('Value'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: _varValue,
            decoration:
                fieldDecoration(t, hint: 'true, false, a number, or text'),
            onChanged: (v) => setState(() => _varValue = v),
          ),
        ];
      case 'SetPrivateBoolean':
        return [
          const RailLabel('Flag name'),
          SizedBox(height: t.space.sm),
          TextFormField(
            initialValue: _name,
            decoration: fieldDecoration(t, hint: 'e.g. vacation'),
            onChanged: (v) => setState(() => _name = v),
          ),
          SizedBox(height: t.space.md),
          const RailLabel('Set it to'),
          SizedBox(height: t.space.sm),
          Row(children: [
            _toggleBtn(t, 'Set', _boolOn, () => setState(() => _boolOn = true)),
            SizedBox(width: t.space.xs),
            _toggleBtn(
                t, 'Clear', !_boolOn, () => setState(() => _boolOn = false)),
          ]),
        ];
      default:
        return [_note(t, _templateNote(tag))];
    }
  }

  /// What a blank-node template does once it lands in the rule. These are the
  /// structural and rarely-touched actions, whose fields are edited in the tree
  /// where there is room for them.
  String _templateNote(String tag) => switch (tag) {
        'Conditional' =>
          'Adds an IF / ELSE block. Write the test, then drop the steps for each '
              'branch inside it.',
        'Parallel' =>
          'Adds a block whose steps all start together instead of one after the '
              'other.',
        'RepeatWhile' =>
          'Adds a loop checked before each pass — the steps inside may never run.',
        'RepeatUntil' =>
          'Adds a loop checked after each pass — the steps inside always run at '
              'least once.',
        'StopRuleChain' =>
          'Stops this rule and any rules it would have gone on to trigger.',
        'ExitRule' => 'Stops this rule here. Later steps are skipped.',
        'WaitForEvent' =>
          'Pauses until a device or event you name arrives, with an optional '
              'timeout.',
        'WaitForExpression' =>
          'Pauses until a Rhai expression becomes true, polled on an interval.',
        'DelayPerMode' =>
          'Waits a different length of time depending on the hub mode.',
        'CancelDelays' =>
          'Cancels waits this rule has pending. Name a key to cancel just one.',
        'CancelRuleTimers' => "Cancels another rule's pending waits.",
        'RunScript' =>
          'Runs a Rhai script — for anything the other actions cannot express.',
        'RunRuleActions' =>
          "Runs another rule's actions without checking that rule's own trigger "
              'or conditions.',
        'PauseRule' => 'Stops a rule from firing until it is resumed.',
        'ResumeRule' => 'Lets a paused rule fire again.',
        'FadeDevice' =>
          'Ramps a light to a level over a duration instead of jumping to it.',
        'SetDeviceStatePerMode' =>
          'Sets a different device state depending on the hub mode.',
        'CaptureDeviceState' =>
          'Remembers what some devices are doing now, under a key you choose.',
        'RestoreDeviceState' =>
          'Puts the devices back the way a matching capture found them.',
        'ActivateScenePerMode' =>
          'Activates a different native scene depending on the hub mode.',
        'PublishMqtt' => 'Publishes a payload to an MQTT topic.',
        'CallService' => 'Sends an HTTP request and optionally fires the reply '
            'back as an event.',
        'FireEvent' => 'Emits a custom event other rules can trigger on.',
        'PingHost' =>
          'Pings a host and branches on whether it answered — steps for '
              'reachable and unreachable go inside.',
        _ => 'Added with its defaults; its fields are edited in the rule.',
      };

  Widget _note(HcTokens t, String text) => _panel(
      t,
      Text(text,
          style: t.text.bodySmallStyle
              .copyWith(height: 1.5, color: t.surface.onBaseMuted)));

  Widget _countStepper(HcTokens t) {
    Widget btn(IconData i, VoidCallback f) => InkWell(
          onTap: f,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: t.surface.raised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.stroke.hairline),
            ),
            child: Icon(i, size: 18, color: t.surface.onBase),
          ),
        );
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      btn(Icons.remove,
          () => setState(() => _repeatCount = (_repeatCount - 1).clamp(1, 99))),
      SizedBox(width: t.space.md),
      Text('$_repeatCount',
          style: t.text.displayStyle
              .copyWith(fontWeight: FontWeight.w700, color: t.accent.active)),
      SizedBox(width: t.space.md),
      btn(Icons.add,
          () => setState(() => _repeatCount = (_repeatCount + 1).clamp(1, 99))),
    ]);
  }

  Widget _dropdown(HcTokens t, String value, List<String> opts,
      ValueChanged<String?> onChanged) {
    final safe = opts.contains(value) ? value : opts.first;
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
          style: t.text.bodyStyle.copyWith(color: t.surface.onBase),
          items: [
            for (final o in opts) DropdownMenuItem(value: o, child: Text(o)),
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
                style: t.text.bodyStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: on ? ac : t.surface.onBaseMuted)),
          ),
        ),
      ),
    );
  }

  Widget _commandGrid(HcTokens t, _Entry e) {
    // A uniform 2-column grid, not a Wrap: every command reads as an equal
    // choice, and the buttons line up regardless of label length.
    final cmds = e.commands;
    final rows = <Widget>[];
    for (var i = 0; i < cmds.length; i += 2) {
      final a = cmds[i];
      final b = i + 1 < cmds.length ? cmds[i + 1] : null;
      rows.add(Padding(
        padding: EdgeInsets.only(bottom: t.space.xs),
        child: Row(children: [
          Expanded(child: _cmdChip(t, a)),
          SizedBox(width: t.space.xs),
          Expanded(child: b == null ? const SizedBox() : _cmdChip(t, b)),
        ]),
      ));
    }
    return Column(children: rows);
  }

  Widget _cmdChip(HcTokens t, DeviceCommand c) => _CommandChip(
        command: c,
        selected: _cmd?.key == c.key,
        onTap: () => _pickCommand(c),
      );

  String _paramLabel(DeviceCommand c, CmdParam p) {
    // A declared parameter names itself; the hand-written commands never did,
    // so they keep deriving one from the command's label.
    if (p.label != null) return p.label!;
    return _derivedParamLabel(c, p);
  }

  String _derivedParamLabel(DeviceCommand c, CmdParam p) => switch (p.kind) {
        CmdParamKind.slider => c.key == 'vol' || c.key == 'set_volume'
            ? 'Volume'
            : c.label.replaceFirst('Set ', ''),
        CmdParamKind.stepper => 'Target temperature',
        CmdParamKind.select =>
          c.label.replaceFirst(RegExp('^(Set|Play|Select) '), ''),
        CmdParamKind.color => 'Color',
        CmdParamKind.duration => 'Duration',
        CmdParamKind.text => c.label.replaceFirst('Set ', ''),
        _ => 'Value',
      };

  Widget _paramControl(HcTokens t, CmdParam p) {
    switch (p.kind) {
      case CmdParamKind.none:
        return const SizedBox.shrink();
      case CmdParamKind.slider:
        return _panel(t, _slider(t, p));
      case CmdParamKind.stepper:
        return _panel(t, _stepper(t, p));
      case CmdParamKind.select:
        return _panel(t, _selectControl(t, p));
      case CmdParamKind.duration:
        return _panel(t, _duration(t, p));
      case CmdParamKind.color:
        return _panel(t, _color(t, p));
      case CmdParamKind.text:
        return _panel(t, _textControl(t, p));
      case CmdParamKind.multi:
        return _panel(t, const SizedBox.shrink());
    }
  }

  Widget _panel(HcTokens t, Widget child) => Container(
        width: double.infinity,
        padding: EdgeInsets.all(t.space.md),
        decoration: BoxDecoration(
          color: t.surface.sunken,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.stroke.hairline),
        ),
        child: child,
      );

  String _effectNote(DeviceCommand c) => switch (c.key) {
        'on' => 'Switches the device on.',
        'off' => 'Switches the device off.',
        'open' => 'Raises the shade fully.',
        'close' => 'Lowers the shade fully.',
        'stop' => 'Stops movement / cancels the timer.',
        'lock' => 'Engages the deadbolt.',
        'unlock' => 'Releases the deadbolt.',
        'activate' => 'Runs the scene — sets every device it contains.',
        'play' => 'Resumes playback.',
        'pause' => 'Pauses playback.',
        'next' => 'Skips to the next track.',
        'previous' => 'Skips to the previous track.',
        _ => 'No parameters.',
      };

  Widget _slider(HcTokens t, CmdParam p) {
    final min = (p.min ?? 0).toDouble();
    final max = (p.max ?? 100).toDouble();
    final v = ((_values[p.name] as num?) ?? min).toDouble().clamp(min, max);
    return Row(children: [
      Expanded(
        child: SliderTheme(
          data: SliderThemeData(
            activeTrackColor: t.accent.primary,
            inactiveTrackColor: t.stroke.hairline,
            thumbColor: t.accent.primary,
            overlayColor: t.accent.primary.withValues(alpha: 0.15),
          ),
          child: Slider(
            min: min,
            max: max,
            value: v,
            onChanged: (nv) =>
                setState(() => _values[p.name] = nv.roundToDouble()),
          ),
        ),
      ),
      SizedBox(
        width: 52,
        child: Text('${v.round()}${p.unit ?? ''}',
            textAlign: TextAlign.right,
            style: t.text.subtitleStyle.copyWith(
                fontWeight: FontWeight.w700, color: t.accent.primary)),
      ),
    ]);
  }

  Widget _stepper(HcTokens t, CmdParam p) {
    final step = (p.step ?? 1).toDouble();
    final v =
        ((_values[p.name] as num?) ?? p.defaultValue as num? ?? 21).toDouble();
    Widget btn(IconData i, VoidCallback f) => InkWell(
          onTap: f,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: t.surface.raised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.stroke.hairline),
            ),
            child: Icon(i, size: 18, color: t.surface.onBase),
          ),
        );
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      btn(Icons.remove,
          () => setState(() => _values[p.name] = (v - step).clamp(5.0, 40.0))),
      SizedBox(width: t.space.md),
      Text('${v % 1 == 0 ? v.toInt() : v}${p.unit ?? ''}',
          style: t.text.displayStyle
              .copyWith(fontWeight: FontWeight.w700, color: t.accent.active)),
      SizedBox(width: t.space.md),
      btn(Icons.add,
          () => setState(() => _values[p.name] = (v + step).clamp(5.0, 40.0))),
    ]);
  }

  /// A free-text value — a writable string attribute whose plugin publishes no
  /// catalogue to pick from (Roku's `tv_channel` before the lineup arrives).
  Widget _textControl(HcTokens t, CmdParam p) => TextFormField(
        key: ValueKey('text:${_sel?.ref}:${_cmd?.key}:${p.name}'),
        initialValue: '${_values[p.name] ?? ''}',
        decoration: fieldDecoration(t, hint: p.label ?? p.name),
        onChanged: (v) => setState(() => _values[p.name] = v),
      );

  Widget _selectControl(HcTokens t, CmdParam p) {
    final opts = p.options ?? const <String>[];
    final v =
        (_values[p.name] as String?) ?? (opts.isEmpty ? null : opts.first);
    if (opts.isEmpty) {
      return Text('None available on this device.',
          style: t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted));
    }
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: v,
        isExpanded: true,
        dropdownColor: t.surface.overlay,
        style: t.text.bodyStyle.copyWith(color: t.surface.onBase),
        items: [
          for (final o in opts)
            DropdownMenuItem(value: o, child: Text(p.labelFor(o))),
        ],
        onChanged: (nv) => setState(() => _values[p.name] = nv),
      ),
    );
  }

  Widget _duration(HcTokens t, CmdParam p) {
    final secs = (_values[p.name] as num?)?.toInt() ?? 300;
    return Wrap(
      spacing: t.space.xs,
      runSpacing: t.space.xs,
      children: [
        for (final (label, s) in _durations)
          _Toggle(
            label: label,
            selected: secs == s,
            onTap: () => setState(() => _values[p.name] = s),
          ),
      ],
    );
  }

  Widget _color(HcTokens t, CmdParam p) {
    final sel =
        _values[p.name] is Color ? _values[p.name] as Color : _swatches[2].$2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            for (final (_, col) in _swatches)
              InkWell(
                onTap: () => setState(() => _values[p.name] = col),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: col,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: sel == col ? t.surface.onBase : Colors.white24,
                      width: sel == col ? 2 : 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: t.space.sm),
        Text(
            _swatches
                .firstWhere((s) => s.$2 == sel, orElse: () => _swatches[2])
                .$1,
            style: t.text.bodyStyle.copyWith(
                fontWeight: FontWeight.w600, color: t.surface.onBase)),
      ],
    );
  }

  // -- live sentence preview ----------------------------------------------

  Widget _preview(HcTokens t, _Entry e) {
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
            children: _sentence(t, e),
          ),
        ],
      ),
    );
  }

  List<Widget> _sentence(HcTokens t, _Entry e) {
    Widget word(String s) =>
        Text(s, style: t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted));
    Widget tok(String s, Color c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: c.withValues(alpha: 0.32)),
          ),
          child: Text(s,
              style: t.text.bodyStyle
                  .copyWith(fontWeight: FontWeight.w600, color: c)),
        );
    if (e.kind == _Kind.template) return _templateSentence(t, e, word, tok);
    final dev = tok(e.label, t.accent.primary);
    final c = _cmd!;
    final val = _valueLabel(c);

    // A command that carries its own phrasing uses it. Everything derived from
    // a device schema does, because the per-key switch below only knows the
    // hand-written commands and would otherwise read "set source Office TV".
    if (c.sentence != null) {
      final parts = <Widget>[];
      for (final piece in _splitTemplate(c.sentence!)) {
        switch (piece) {
          case '{device}':
            parts.add(dev);
          case '{value}':
            parts.add(tok(val.isEmpty ? '…' : val, t.accent.active));
          default:
            final named =
                RegExp(r'^\{([a-z_]+)\}$').firstMatch(piece)?.group(1);
            if (named != null) {
              final p = _firstOrNull(c.params, (x) => x.name == named);
              final text = p == null ? '' : _paramValueLabel(p);
              parts.add(tok(text.isEmpty ? '…' : text, t.accent.active));
            } else if (piece.trim().isNotEmpty) {
              parts.add(word(piece.trim()));
            }
        }
      }
      return parts;
    }
    switch (c.key) {
      case 'on':
      case 'lock':
      case 'unlock':
      case 'open':
      case 'close':
      case 'play':
      case 'pause':
      case 'activate':
        return [tok(c.label.toLowerCase(), t.accent.active), dev];
      case 'off':
        return [tok('turn off', t.accent.active), dev];
      case 'stop':
        return [
          tok(e.bucket == 'timer' ? 'cancel' : 'stop', t.accent.active),
          dev
        ];
      case 'brightness':
        return [
          tok('set the brightness of', t.accent.active),
          dev,
          word('to'),
          tok(val, t.accent.active)
        ];
      case 'color':
        return [
          tok('set', t.accent.active),
          dev,
          word('to'),
          tok(val, t.accent.active)
        ];
      case 'white':
        return [
          tok('set', t.accent.active),
          dev,
          word('to'),
          tok('$val white', t.accent.active)
        ];
      case 'position':
        return [
          tok('set', t.accent.active),
          dev,
          word('to'),
          tok('$val open', t.accent.active)
        ];
      case 'set_temp':
        return [
          tok('set', t.accent.active),
          dev,
          word('to'),
          tok(val, t.accent.active)
        ];
      case 'set_mode':
        return [
          tok('set', t.accent.active),
          dev,
          word('mode to'),
          tok(val, t.accent.active)
        ];
      case 'start':
        return [
          tok('start', t.accent.active),
          dev,
          word('for'),
          tok(val, t.accent.active)
        ];
      case 'restart':
        return [
          tok('restart', t.accent.active),
          dev,
          word('for'),
          tok(val, t.accent.active)
        ];
      case 'set_volume':
        return [
          tok('set the volume to', t.accent.active),
          tok(val, t.accent.active),
          word('on'),
          dev
        ];
      case 'play_favorite':
        return [
          tok('play the favorite', t.accent.active),
          tok(val, t.accent.active),
          word('on'),
          dev
        ];
      case 'play_playlist':
        return [
          tok('play the playlist', t.accent.active),
          tok(val, t.accent.active),
          word('on'),
          dev
        ];
      case 'set_shuffle':
        return [
          tok('turn shuffle', t.accent.active),
          tok(val, t.accent.active),
          word('on'),
          dev
        ];
      case 'group':
        return [
          tok('group', t.accent.active),
          dev,
          word('with'),
          tok(val, t.accent.active)
        ];
      case 'next':
        return [
          tok('skip to the next track', t.accent.active),
          word('on'),
          dev
        ];
      case 'previous':
        return [
          tok('skip to the previous track', t.accent.active),
          word('on'),
          dev
        ];
      default:
        return [tok(c.label.toLowerCase(), t.accent.active), dev];
    }
  }

  /// The template half of "reads as" — the same tokenised phrasing the sentence
  /// editor will show once the node is in the rule.
  List<Widget> _templateSentence(HcTokens t, _Entry e,
      Widget Function(String) word, Widget Function(String, Color) tok) {
    final a = t.accent.active;
    final b = t.accent.primary;
    String orDots(String s) => s.trim().isEmpty ? '…' : s.trim();
    switch (e.tag) {
      case 'Delay':
        return [tok('wait', a), tok(_secsLabel(_secs), a)];
      case 'RepeatCount':
        return [
          tok('repeat the steps inside', a),
          tok('$_repeatCount time${_repeatCount == 1 ? '' : 's'}', a),
        ];
      case 'Notify':
        return [
          tok('notify', a),
          tok(orDots(_channel.isEmpty ? 'all' : _channel), b),
          word('with'),
          tok(orDots(_message), a),
        ];
      case 'LogMessage':
        return [
          tok('log', a),
          tok(_level.toLowerCase(), b),
          tok(orDots(_message), a),
        ];
      case 'Comment':
        return [word('note:'), tok(orDots(_message), a)];
      case 'SetVariable':
      case 'SetHubVariable':
        final scope = e.tag == 'SetHubVariable' ? 'hub variable' : 'variable';
        return [
          tok(_varOp.toLowerCase(), a),
          word('the $scope'),
          tok(orDots(_name), b),
          if (_varOp != 'Toggle') ...[word('to'), tok(orDots(_varValue), a)],
        ];
      case 'SetPrivateBoolean':
        return [
          tok('set the flag', a),
          tok(orDots(_name), b),
          word('to'),
          tok(_boolOn ? 'set' : 'clear', a),
        ];
      default:
        return [tok(e.label.toLowerCase(), a)];
    }
  }

  String _secsLabel(int secs) => _durations
      .firstWhere((d) => d.$2 == secs,
          orElse: () => ('$secs second${secs == 1 ? '' : 's'}', secs))
      .$1;

  /// Splits `"set the source of {device} to {value}"` into literal runs and
  /// placeholders, keeping the placeholders as their own pieces.
  static List<String> _splitTemplate(String template) {
    final out = <String>[];
    var i = 0;
    // `{device}` and `{value}` are reserved; everything else names a parameter
    // of the declared action — "press {key} {count} time(s)".
    for (final m in RegExp(r'\{([a-z_]+)\}').allMatches(template)) {
      if (m.start > i) out.add(template.substring(i, m.start));
      out.add(m[0]!);
      i = m.end;
    }
    if (i < template.length) out.add(template.substring(i));
    return out;
  }

  /// The primary control's value, for the hand-written sentences that say
  /// "{value}" without naming a parameter.
  String _valueLabel(DeviceCommand c) =>
      c.params.isEmpty ? '' : _paramValueLabel(c.param);

  /// How one parameter's current value reads in the preview.
  String _paramValueLabel(CmdParam p) {
    final v = _values[p.name];
    switch (p.kind) {
      case CmdParamKind.slider:
        return '${((v as num?) ?? p.min ?? 0).round()}${p.unit ?? ''}';
      case CmdParamKind.stepper:
        final n = (v as num?) ?? 21;
        return '${n % 1 == 0 ? n.toInt() : n}${p.unit ?? ''}C';
      case CmdParamKind.duration:
        final secs = (v as num?)?.toInt() ?? 300;
        return _durations
            .firstWhere((d) => d.$2 == secs, orElse: () => ('$secs sec', secs))
            .$1;
      case CmdParamKind.color:
        final col = v is Color ? v : _swatches[2].$2;
        return _swatches
            .firstWhere((s) => s.$2 == col, orElse: () => _swatches[2])
            .$1;
      case CmdParamKind.select:
        // Show what the user sees, not the id we send: a Roku channel is
        // chosen by id and named "Netflix".
        final chosen = (v as String?) ??
            (p.options?.isNotEmpty == true ? p.options!.first : '');
        return p.labelFor(chosen);
      default:
        return '${v ?? ''}';
    }
  }
}

/// A command button in the builder's grid.
class _CommandChip extends StatelessWidget {
  const _CommandChip(
      {required this.command, required this.selected, required this.onTap});

  final DeviceCommand command;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final ac = t.accent.active;
    return Material(
      color: selected ? ac.withValues(alpha: 0.14) : t.surface.sunken,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color:
                    selected ? ac.withValues(alpha: 0.4) : t.stroke.hairline),
          ),
          child: Row(children: [
            Icon(command.icon,
                size: 15, color: selected ? ac : t.surface.onBaseMuted),
            SizedBox(width: t.space.xs),
            Expanded(
              child: Text(command.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.bodySmallStyle.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                      color: selected ? ac : t.surface.onBaseMuted)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A pill toggle (duration presets).
class _Toggle extends StatelessWidget {
  const _Toggle(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final ac = t.accent.active;
    return Material(
      color: selected ? ac.withValues(alpha: 0.14) : t.surface.raised,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color:
                    selected ? ac.withValues(alpha: 0.4) : t.stroke.hairline),
          ),
          child: Text(label,
              style: t.text.bodySmallStyle.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? ac : t.surface.onBaseMuted)),
        ),
      ),
    );
  }
}

/// The first element matching [test], or null — avoids a `package:collection`
/// import for one call site.
T? _firstOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final e in items) {
    if (test(e)) return e;
  }
  return null;
}
