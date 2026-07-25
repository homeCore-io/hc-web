import 'package:flutter/material.dart';

import '../../../core/devices/presentation.dart';
import '../../../core/models/device_state.dart';
import '../../../core/rules/node.dart';
import '../../../design/tokens.dart';
import '../device_commands.dart';
import 'device_picker_shell.dart';
import 'editor_style.dart';
import 'rule_refs.dart';

/// The multi-pane "Add action" picker: choose a device by type or room, then
/// configure the one command that makes sense for it.
///
/// Replaces the flat device list + raw-JSON `state` field. It returns a
/// fully-built `HcNode` (a `SetDeviceState` / `SetMode`), so the caller drops it
/// straight into the rule — no second editing step. Sensors never appear: they
/// report state, so they belong in conditions, not actions.
///
/// Shown with `showDialog<HcNode>`; the command payloads come from
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

/// One selectable thing: a device, a native scene, or a mode. Each carries the
/// commands it can perform, already resolved.
class _Entry {
  _Entry({
    required this.label,
    required this.ref,
    required this.sub,
    required this.icon,
    required this.bucket,
    required this.room,
    required this.commands,
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
  final List<DeviceCommand> commands;
  final DeviceState? device;
  final String? chip;
  final PickerTone? chipTone;
}

class _Cat {
  const _Cat(this.key, this.label, this.icon, this.group);
  final String key;
  final String label;
  final IconData icon;
  final String group;
}

const _cats = [
  _Cat('all', 'All controllable', Icons.list_alt_outlined, 'Quick'),
  _Cat('light', 'Lights', Icons.lightbulb_outline, 'Controls'),
  _Cat('switch', 'Switches & Outlets', Icons.toggle_on_outlined, 'Controls'),
  _Cat('cover', 'Shades & Covers', Icons.blinds_outlined, 'Controls'),
  _Cat('lock', 'Locks', Icons.lock_outline, 'Controls'),
  _Cat('climate', 'Climate', Icons.hvac_outlined, 'Controls'),
  _Cat('media', 'Media players', Icons.speaker_outlined, 'Controls'),
  _Cat('scene', 'Scenes', Icons.auto_awesome_outlined, 'Run'),
  _Cat('timer', 'Timers', Icons.timer_outlined, 'Run'),
  _Cat('mode', 'Modes', Icons.brightness_4_outlined, 'Run'),
];

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
  Object? _value;

  late final List<_Entry> _entries = _buildEntries();
  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _prefill(widget.initial!);
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
    final (cmd, value) = _matchCommand(entry, node);
    _cmd = cmd ?? entry.commands.first;
    _value = value ?? _cmd!.param.defaultValue;
    if (_cmd!.param.kind == CmdParamKind.color && _value is! Color) {
      _value = _swatches[2].$2;
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
    return (null, null);
  }

  // -- entry construction --------------------------------------------------

  List<_Entry> _buildEntries() {
    final out = <_Entry>[];
    final seen = <String>{};

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
        room: d.effectiveArea ?? 'No room',
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
      _cmd = e.commands.first;
      _value = _cmd!.param.defaultValue;
    });
  }

  void _pickCommand(DeviceCommand c) {
    setState(() {
      _cmd = c;
      _value = c.param.kind == CmdParamKind.color
          ? _swatches[2].$2
          : c.param.defaultValue;
    });
  }

  // -- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PickerPanel(
      kicker: _editing ? 'EDIT ACTION' : 'ADD ACTION · CHOOSE A DEVICE',
      title: 'What should this rule control?',
      seg: pickerSeg(HcTokens.of(context),
          byRoom: _byRoom,
          onChanged: (v) => setState(() {
                _byRoom = v;
                if (v) _room = _rooms.first;
              })),
      panes: [
        PickerPane(width: 202, child: _rail(context)),
        PickerPane(flex: 3, child: _list(context)),
        PickerPane(flex: 3, child: _detail(HcTokens.of(context))),
      ],
      footerHint: _footHint(),
      primaryLabel: _editing ? 'Save action' : 'Add action',
      onPrimary: _cmd == null
          ? null
          : () => Navigator.pop(context, _cmd!.build(_value)),
    );
  }

  String _footHint() {
    final devs = _entries.where((e) => e.device != null).length;
    final scenes = _entries.where((e) => e.bucket == 'scene').length;
    final modes = _entries.where((e) => e.bucket == 'mode').length;
    return '$devs controllable devices · $scenes scenes · $modes modes · sensors hidden';
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

  // -- pane 3: action builder ----------------------------------------------

  Widget _detail(HcTokens t) {
    final e = _sel;
    if (e == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(t.space.lg),
          child: Text(
            'Pick a device to configure the action. Each type shows only the controls that make sense for it.',
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.label,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.surface.onBase)),
                Text(e.device?.mediaSubtitle ?? e.sub,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: t.surface.onBaseMuted)),
              ],
            ),
          ),
        ]),
        SizedBox(height: t.space.md),
        const RailLabel('Command'),
        SizedBox(height: t.space.sm),
        _commandGrid(t, e),
        SizedBox(height: t.space.md),
        if (_cmd!.param.kind != CmdParamKind.none) ...[
          RailLabel(_paramLabel(_cmd!)),
          SizedBox(height: t.space.sm),
        ],
        _paramControl(t, _cmd!),
        SizedBox(height: t.space.md),
        _preview(t, e),
      ],
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

  String _paramLabel(DeviceCommand c) => switch (c.param.kind) {
        CmdParamKind.slider => c.key == 'vol' || c.key == 'set_volume'
            ? 'Volume'
            : c.label.replaceFirst('Set ', ''),
        CmdParamKind.stepper => 'Target temperature',
        CmdParamKind.select =>
          c.label.replaceFirst(RegExp('^(Set|Play|Select) '), ''),
        CmdParamKind.color => 'Color',
        CmdParamKind.duration => 'Duration',
        _ => 'Value',
      };

  Widget _paramControl(HcTokens t, DeviceCommand c) {
    switch (c.param.kind) {
      case CmdParamKind.none:
        return _panel(
            t,
            Text(_effectNote(c),
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: t.surface.onBaseMuted)));
      case CmdParamKind.slider:
        return _panel(t, _slider(t, c));
      case CmdParamKind.stepper:
        return _panel(t, _stepper(t, c));
      case CmdParamKind.select:
        return _panel(t, _selectControl(t, c));
      case CmdParamKind.duration:
        return _panel(t, _duration(t, c));
      case CmdParamKind.color:
        return _panel(t, _color(t));
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

  Widget _slider(HcTokens t, DeviceCommand c) {
    final min = (c.param.min ?? 0).toDouble();
    final max = (c.param.max ?? 100).toDouble();
    final v = ((_value as num?) ?? min).toDouble().clamp(min, max);
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
            onChanged: (nv) => setState(() => _value = nv.roundToDouble()),
          ),
        ),
      ),
      SizedBox(
        width: 52,
        child: Text('${v.round()}${c.param.unit ?? ''}',
            textAlign: TextAlign.right,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: t.accent.primary)),
      ),
    ]);
  }

  Widget _stepper(HcTokens t, DeviceCommand c) {
    final step = (c.param.step ?? 1).toDouble();
    final v =
        ((_value as num?) ?? c.param.defaultValue as num? ?? 21).toDouble();
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
          () => setState(() => _value = (v - step).clamp(5.0, 40.0))),
      SizedBox(width: t.space.md),
      Text('${v % 1 == 0 ? v.toInt() : v}${c.param.unit ?? ''}',
          style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: t.accent.active)),
      SizedBox(width: t.space.md),
      btn(Icons.add,
          () => setState(() => _value = (v + step).clamp(5.0, 40.0))),
    ]);
  }

  Widget _selectControl(HcTokens t, DeviceCommand c) {
    final opts = c.param.options ?? const <String>[];
    final v = (_value as String?) ?? (opts.isEmpty ? null : opts.first);
    if (opts.isEmpty) {
      return Text('None available on this device.',
          style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted));
    }
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: v,
        isExpanded: true,
        dropdownColor: t.surface.overlay,
        style: TextStyle(fontSize: 13.5, color: t.surface.onBase),
        items: [
          for (final o in opts) DropdownMenuItem(value: o, child: Text(o)),
        ],
        onChanged: (nv) => setState(() => _value = nv),
      ),
    );
  }

  Widget _duration(HcTokens t, DeviceCommand c) {
    final secs = (_value as num?)?.toInt() ?? 300;
    return Wrap(
      spacing: t.space.xs,
      runSpacing: t.space.xs,
      children: [
        for (final (label, s) in _durations)
          _Toggle(
            label: label,
            selected: secs == s,
            onTap: () => setState(() => _value = s),
          ),
      ],
    );
  }

  Widget _color(HcTokens t) {
    final sel = _value is Color ? _value as Color : _swatches[2].$2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            for (final (_, col) in _swatches)
              InkWell(
                onTap: () => setState(() => _value = col),
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
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: t.surface.onBase)),
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
    final c = _cmd!;
    final val = _valueLabel(c);
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

  String _valueLabel(DeviceCommand c) {
    switch (c.param.kind) {
      case CmdParamKind.slider:
        return '${((_value as num?) ?? 0).round()}${c.param.unit ?? ''}';
      case CmdParamKind.stepper:
        final v = (_value as num?) ?? 21;
        return '${v % 1 == 0 ? v.toInt() : v}${c.param.unit ?? ''}C';
      case CmdParamKind.duration:
        final secs = (_value as num?)?.toInt() ?? 300;
        return _durations
            .firstWhere((d) => d.$2 == secs, orElse: () => ('$secs sec', secs))
            .$1;
      case CmdParamKind.color:
        final col = _value is Color ? _value as Color : _swatches[2].$2;
        return _swatches
            .firstWhere((s) => s.$2 == col, orElse: () => _swatches[2])
            .$1;
      case CmdParamKind.select:
        return '${_value ?? (c.param.options?.isNotEmpty == true ? c.param.options!.first : '')}';
      default:
        return '${_value ?? ''}';
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
                  style: TextStyle(
                      fontSize: 12.5,
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
              style: TextStyle(
                  fontSize: 12,
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
