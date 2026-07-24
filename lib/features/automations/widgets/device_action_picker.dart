import 'package:flutter/material.dart';

import '../../../core/devices/presentation.dart';
import '../../../core/models/device_state.dart';
import '../../../design/components/hc_dialog.dart';
import '../../../design/tokens.dart';
import '../device_commands.dart';
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
  const DeviceActionPicker({super.key, required this.refs});

  final RuleRefs refs;

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
  final SectionTone? chipTone;
}

enum SectionTone { on, play, ok, off }

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

  (String?, SectionTone?) _deviceChip(DeviceState d) {
    if (d.isMediaPlayer) {
      return d.playbackState == 'playing'
          ? ('playing', SectionTone.play)
          : (d.playbackState, SectionTone.off);
    }
    final s = d.state;
    if (s['locked'] == true) return ('locked', SectionTone.ok);
    if (s['locked'] == false) return ('unlocked', SectionTone.off);
    if (s['on'] == true) {
      final b = s['brightness_pct'];
      return (b is num ? 'on · ${b.round()}%' : 'on', SectionTone.on);
    }
    if (s['on'] == false) return ('off', SectionTone.off);
    final pos = s['position'];
    if (pos is num) {
      return (
        pos <= 0 ? 'closed' : 'open · ${pos.round()}%',
        pos <= 0 ? SectionTone.off : SectionTone.on
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
    final t = HcTokens.of(context);
    // A custom panel rather than HcDialog: the panes are full-bleed under a
    // padded header, each on its own surface tone, which is where the depth
    // comes from — a flat single-surface dialog reads as one grey slab.
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.all(t.space.lg),
      child: Container(
        width: 960,
        decoration: BoxDecoration(
          color: t.surface.overlay,
          borderRadius: BorderRadius.circular(t.radius.lg),
          border: Border.all(color: t.stroke.hairline, width: t.stroke.width),
          boxShadow: t.elevation.overlay,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(t),
            _hline(t),
            SizedBox(
              height: 470,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 202, child: _rail(t)),
                  _hline(t, vertical: true),
                  Expanded(flex: 3, child: _list(t)),
                  _hline(t, vertical: true),
                  Expanded(flex: 3, child: _detail(t)),
                ],
              ),
            ),
            _hline(t),
            _footer(t),
          ],
        ),
      ),
    );
  }

  Widget _hline(HcTokens t, {bool vertical = false}) => Container(
        width: vertical ? 1 : null,
        height: vertical ? null : 1,
        color: t.stroke.hairline,
      );

  Widget _header(HcTokens t) => Padding(
        padding:
            EdgeInsets.fromLTRB(t.space.lg, t.space.md, t.space.md, t.space.md),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ADD ACTION · CHOOSE A DEVICE',
                    style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                        color: t.accent.active)),
                const SizedBox(height: 3),
                Text('What should this rule control?',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: t.surface.onBase)),
              ],
            ),
          ),
          _seg(t),
        ]),
      );

  Widget _seg(HcTokens t) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: t.surface.sunken,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.stroke.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _segBtn(
              t, 'By type', !_byRoom, () => setState(() => _byRoom = false)),
          _segBtn(t, 'By room', _byRoom, () {
            setState(() {
              _byRoom = true;
              _room = _rooms.first;
            });
          }),
        ]),
      );

  Widget _footer(HcTokens t) => Padding(
        padding: EdgeInsets.symmetric(
            horizontal: t.space.lg, vertical: t.space.sm + 2),
        child: Row(children: [
          Text(_footHint(),
              style: TextStyle(fontSize: 11.5, color: t.surface.onBaseMuted)),
          const Spacer(),
          HcButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
          SizedBox(width: t.space.sm),
          HcButton(
            label: 'Add action',
            kind: HcButtonKind.primary,
            onPressed: _cmd == null
                ? null
                : () => Navigator.pop(context, _cmd!.build(_value)),
          ),
        ]),
      );

  String _footHint() {
    final devs = _entries.where((e) => e.device != null).length;
    final scenes = _entries.where((e) => e.bucket == 'scene').length;
    final modes = _entries.where((e) => e.bucket == 'mode').length;
    return '$devs controllable devices · $scenes scenes · $modes modes · sensors hidden';
  }

  // -- pane 1: rail --------------------------------------------------------

  Widget _rail(HcTokens t) {
    final List<Widget> items = [];
    if (_byRoom) {
      for (final r in _rooms) {
        items.add(_railRow(
            t,
            r,
            Icons.meeting_room_outlined,
            _entries.where((e) => e.room == r).length,
            _room == r,
            () => setState(() => _room = r)));
      }
    } else {
      var lastGroup = '';
      for (final c in _cats) {
        if (c.group != lastGroup) {
          items.add(Padding(
            padding: EdgeInsets.fromLTRB(t.space.sm, t.space.md, 0, t.space.xs),
            child: RailLabel(c.group),
          ));
          lastGroup = c.group;
        }
        items.add(_railRow(t, c.label, c.icon, _count(c.key), _cat == c.key,
            () => setState(() => _cat = c.key)));
      }
    }

    return Container(
      color: t.surface.sunken,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: t.space.xs),
          Expanded(child: ListView(padding: EdgeInsets.zero, children: items)),
          _hline(t),
          Padding(
            padding: EdgeInsets.all(t.space.sm),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 13, color: t.surface.onBaseMuted),
              SizedBox(width: t.space.xs),
              Expanded(
                child: Text(
                  'Sensors are hidden — they belong in conditions, not actions.',
                  style: TextStyle(
                      fontSize: 10.5,
                      height: 1.4,
                      color: t.surface.onBaseMuted),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _segBtn(HcTokens t, String label, bool on, VoidCallback onTap) =>
      Material(
        color: on ? t.surface.raised : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
            child: Text(label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: on ? t.surface.onBase : t.surface.onBaseMuted,
                )),
          ),
        ),
      );

  Widget _railRow(HcTokens t, String label, IconData icon, int count, bool on,
      VoidCallback onTap) {
    return Material(
      color: on ? t.accent.active.withValues(alpha: 0.12) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: t.space.sm, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: on ? t.accent.active : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Row(children: [
            Icon(icon,
                size: 17, color: on ? t.surface.onBase : t.surface.onBaseMuted),
            SizedBox(width: t.space.sm),
            Expanded(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: on ? t.surface.onBase : t.surface.onBaseMuted,
                  )),
            ),
            Text('$count',
                style: TextStyle(
                    fontSize: 11.5,
                    color: on ? t.accent.active : t.surface.onBaseMuted)),
          ]),
        ),
      ),
    );
  }

  // -- pane 2: device list -------------------------------------------------

  Widget _list(HcTokens t) {
    final pool = _pool;
    final rows = <Widget>[];
    var lastRoom = '';
    for (final e in pool) {
      if (!_byRoom && e.room != lastRoom) {
        rows.add(Padding(
          padding: EdgeInsets.fromLTRB(t.space.sm, t.space.md, 0, t.space.xs),
          child: RailLabel(e.room),
        ));
        lastRoom = e.room;
      }
      rows.add(_deviceRow(t, e));
    }
    return DecoratedBox(
      // A touch darker than the detail pane (which sits on the panel's overlay),
      // so the list reads as sunk into the shell and the detail as raised out.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(t.surface.sunken, t.surface.base, 0.5)!,
            t.surface.sunken,
          ],
        ),
      ),
      child: Column(children: [
        Padding(
          padding: EdgeInsets.all(t.space.sm),
          child: TextField(
            decoration: fieldDecoration(t, hint: 'Search devices…'),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: pool.isEmpty
              ? Center(
                  child: Text('No devices match.',
                      style: TextStyle(color: t.surface.onBaseMuted)))
              : ListView(
                  padding: EdgeInsets.symmetric(horizontal: t.space.xs),
                  children: rows),
        ),
      ]),
    );
  }

  Widget _deviceRow(HcTokens t, _Entry e) {
    final on = _sel?.ref == e.ref;
    final tone = switch (e.chipTone) {
      SectionTone.on => t.accent.active,
      SectionTone.play => t.accent.primary,
      SectionTone.ok => t.accent.success,
      _ => t.surface.onBaseMuted,
    };
    return Material(
      color: on ? t.accent.active.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: t.radius.smR,
      child: InkWell(
        onTap: () => _select(e),
        borderRadius: t.radius.smR,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space.sm, vertical: 8),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: t.surface.raised,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.stroke.hairline),
              ),
              child: Icon(e.icon,
                  size: 17,
                  color: on ? t.accent.active : t.surface.onBaseMuted),
            ),
            SizedBox(width: t.space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.label,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 13.5, color: t.surface.onBase)),
                  Text(e.sub,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: t.surface.onBaseMuted)),
                ],
              ),
            ),
            if (e.chip != null) ...[
              SizedBox(width: t.space.xs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tone.withValues(alpha: 0.28)),
                ),
                child: Text(e.chip!,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: tone)),
              ),
            ],
          ]),
        ),
      ),
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
