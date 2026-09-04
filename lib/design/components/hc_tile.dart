import 'package:flutter/material.dart';

import '../../core/devices/battery.dart';
import '../../core/devices/presentation.dart';
import '../../core/schema/attribute_policy.dart';
import '../../core/models/device_state.dart';
import '../hc_icons.dart';
import '../tokens.dart';
import 'hc_surface.dart';

/// A live device, as a card.
///
/// The tile is the control **and** the readout. It replaces a `ListTile` whose
/// only expression of "this lamp is on" was a switch in the trailing slot.
///
/// Three things earn their keep:
///
/// * **A lit device bleeds light.** The halo scales with level, so a dimmer at
///   18% barely glows while one at 100% blooms — you read the room from across
///   the room.
/// * **The icon carries state in its weight.** Off is the outline glyph, on is
///   the solid. Colour reinforces it rather than doing all the work.
/// * **Offline is a fault, not a state.** Dashed border, its own colour, and its
///   subtitle is replaced — so a stale reading can never masquerade as live, and
///   a dead device never reads as merely "off".
class HcTile extends StatelessWidget {
  const HcTile({
    super.key,
    required this.device,
    this.onTap,
    this.onToggle,
    this.onLevel,
    this.pulse = 0,
    this.label,
    this.selected = false,
  });

  final DeviceState device;

  /// What to call it, when that is not its full name.
  ///
  /// A room page hands over the name with the room's own name taken off the
  /// front: every device in the Living Room is called "Living Room something",
  /// and in a tile this narrow the prefix is the half that survives.
  final String? label;

  /// Whether this is the tile the page's controls are currently aimed at.
  ///
  /// Said with a ring rather than with the lit treatment a device already uses
  /// for being *on*: a lamp that is off can be the one you are adjusting, and
  /// two meanings sharing one colour would make both unreadable.
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;

  /// Called while dragging the inline dimmer, with 0–1.
  final ValueChanged<double>? onLevel;

  /// Bump when a change arrives from *outside* this client, to flash the tile.
  final int pulse;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    final facet = facetOf(device, device.schema);
    final offline = !device.available;
    final on = !offline && isOn(device);
    final level = levelOf(device);

    // A colour light lit its real colour, so a Hue bulb showing deep amber
    // glows amber and a cool-white one glows white — the point of a colour
    // light, thrown away when every tile is the same house accent.
    final tint = on ? lightColorOf(device) : null;
    final active = tint ?? t.accent.active;

    // A sensor has no switch and no dimmer, however many writable attributes
    // happen to drift in. Offering one would invite the user to "turn off" a
    // motion sensor.
    final actuator = facet.isActuator;
    final dimmable = actuator && level != null && onLevel != null;

    final fg = offline
        ? t.accent.offline
        : on
            ? active
            : t.surface.onBaseMuted;

    return _Pulse(
      pulse: pulse,
      child: HcSurface(
        onTap: onTap,
        selected: selected,
        glowColor: active,
        // The halo is the level. Not a fixed "on" glow — a dim lamp must look
        // dim, or the wall panel lies about the room.
        glowIntensity: on ? (level ?? 1.0) : 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _Bulb(
                    iconFacet: deviceIconOverride(device) ?? facet,
                    on: on,
                    offline: offline,
                    colour: fg,
                    accent: active),
                SizedBox(width: t.space.md),
                Expanded(child: _title(context, t, offline)),
                if (actuator && !offline && onToggle != null)
                  _Toggle(on: on, onChanged: (_) => onToggle!()),
              ],
            ),
            if (dimmable) ...[
              SizedBox(height: t.space.sm + 2),
              _Dimmer(level: level, onChanged: onLevel!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _title(BuildContext context, HcTokens t, bool offline) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label ?? device.displayName,
            // Two lines. "Bathroom Occupancy" and "Dining Room Door Sensor" are
            // ordinary names in this house and were being cut to "Bathroom
            // Occupan…" — a device you cannot read is a device you cannot use.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.text.bodyStyle.copyWith(
              // Tighter than the ramp, per the two-line note above: 1.4 puts
              // too much air between the halves of a wrapped name.
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              color: offline ? t.surface.onBaseMuted : t.surface.onBase,
            ),
          ),
          SizedBox(height: t.space.xs - 1),
          Text(
            // Offline replaces the reading outright. A stale value shown plainly
            // is worse than no value: it looks live.
            offline ? 'Offline' : summarise(device),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.text.captionStyle.copyWith(
              height: 1.2,
              color: offline ? t.accent.offline : t.surface.onBaseMuted,
              fontFeatures: t.numericFontFeatures,
            ),
          ),
        ],
      );
}

/// The disc behind the icon, which fills with light as the device brightens.
class _Bulb extends StatelessWidget {
  const _Bulb({
    required this.iconFacet,
    required this.on,
    required this.offline,
    required this.colour,
    required this.accent,
  });

  /// Which glyph to draw — the device's `status_icon` override when it has
  /// one, else its real facet. Deliberately separate from the facet that
  /// decides the *controls*: an icon override changes the picture and must not
  /// change what the tile lets you do.
  final DeviceFacet iconFacet;
  final bool on;
  final bool offline;
  final Color colour;

  /// The active colour — the light's own when it has one, else the house accent.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final size = (t.density.controlHeight * 0.78).clamp(30.0, 42.0);

    // **The glyph, not a block with a glyph in it.**
    //
    // A filled disc behind every icon put a second shape inside a tile that is
    // already a shape, and a row of them reads as a row of blocks rather than
    // as a row of lights. John: *"The block icons in lights and switches could
    // be done differently I don't like blocks."*
    //
    // What the disc was carrying is kept where it belongs: a lit device gets a
    // soft halo of its own colour — the light, not a container for it — and an
    // unreachable one keeps its ring, because offline is a state that has to be
    // visible and a dimmed glyph alone is not enough.
    return AnimatedContainer(
      duration: t.motion.d(t.motion.base),
      curve: t.motion.curve,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: offline
            ? Border.all(color: t.accent.offline.withValues(alpha: 0.5))
            : null,
        // Through the skin's own glow, not a hand-picked shadow: Control Room
        // says *near-black, hairlines, no bloom* by setting strength to 0, and
        // a widget with its own BoxShadow overrides that silently.
        boxShadow: on
            ? t.glow.halo(accent,
                blur: size * 0.5, alpha: 0.45, spread: -size * 0.14)
            : null,
      ),
      // The glyph itself changes weight with state — see HcIcons.
      child: Icon(
        HcIcons.forFacet(iconFacet, on: on),
        size: size * 0.62,
        color: colour,
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final h = (t.density.controlHeight * 0.48).clamp(20.0, 26.0);
    final w = h * 1.72;

    return Semantics(
      toggled: on,
      child: GestureDetector(
        onTap: () => onChanged(!on),
        child: AnimatedContainer(
          duration: t.motion.d(t.motion.fast),
          curve: t.motion.curve,
          width: w,
          height: h,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: on ? t.accent.active : t.accent.inactive,
            borderRadius: t.radius.pillR,
          ),
          child: AnimatedAlign(
            duration: t.motion.d(t.motion.fast),
            // **A switch knob does not overshoot.** `emphasized` is
            // `easeOutBack` on three of the four skins, so the knob sprang past
            // the end of its track and settled back — at this size it reads as
            // a glitch rather than as physics, and in a list of twenty rows it
            // is twenty of them. John: *"the 'bouncing' effect in the list
            // views in everything else and even the home page. I don't like
            // it."*
            curve: t.motion.curve,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: h - 6,
              height: h - 6,
              decoration: BoxDecoration(
                color: t.surface.raised,
                shape: BoxShape.circle,
                boxShadow: t.elevation.card,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The inline level. Deliberately not a Material `Slider`: at this size it is a
/// readout you can also drag, so it has no thumb and no chrome — a warm bar that
/// *is* the brightness.
class _Dimmer extends StatelessWidget {
  const _Dimmer({required this.level, required this.onChanged});

  final double level;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return LayoutBuilder(
      builder: (context, box) {
        void setFrom(Offset local) =>
            onChanged((local.dx / box.maxWidth).clamp(0.0, 1.0));

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => setFrom(d.localPosition),
          onHorizontalDragUpdate: (d) => setFrom(d.localPosition),
          child: SizedBox(
            height: 12,
            child: Center(
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color: t.surface.sunken,
                  borderRadius: t.radius.pillR,
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: level.clamp(0.0, 1.0),
                  child: AnimatedContainer(
                    duration: t.motion.d(t.motion.base),
                    curve: t.motion.curve,
                    decoration: BoxDecoration(
                      borderRadius: t.radius.pillR,
                      gradient: LinearGradient(
                        colors: [
                          t.accent.active.withValues(alpha: 0.45),
                          t.accent.active,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Flashes the tile when a change arrives from outside this client.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child, required this.pulse});

  final Widget child;
  final int pulse;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void didUpdateWidget(covariant _Pulse old) {
    super.didUpdateWidget(old);
    if (widget.pulse != old.pulse) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    if (!t.motion.enabled) return widget.child;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          borderRadius: t.radius.mdR,
          border: Border.all(
            color: t.accent.primary
                .withValues(alpha: _c.value == 0 ? 0 : (1 - _c.value) * 0.9),
            width: 2,
          ),
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// One line that says what a device is doing, in its own terms.
///
/// A light says "100% · 2890K"; a door says "closed"; a sensor says "21.4°".
/// Generic key/value dumping is what made the old list unreadable.
String summarise(DeviceState d) {
  final s = d.state;

  String? pct(Object? v, {double max = 100}) =>
      v is num ? '${(v.toDouble() / max * 100).round()}%' : null;

  final bits = <String>[];

  if (s['on'] == true) {
    final b = pct(s['brightness_pct']) ??
        pct(s['brightness'], max: 255) ??
        (s['on'] == true ? 'on' : null);
    if (b != null) bits.add(b);
    if (s['color_temp_mirek'] case final num m when m > 0) {
      bits.add('${(1000000 / m).round()}K'); // mirek → kelvin
    } else if (s['color_temp'] case final num k) {
      bits.add('${k.round()}K');
    }
  } else if (s.containsKey('on')) {
    bits.add('off');
  }

  final facet = facetOf(d, d.schema);

  if (s['locked'] case final bool l) bits.add(l ? 'locked' : 'unlocked');
  if (s['open'] case final bool o) bits.add(o ? 'open' : 'closed');

  // Every sensor kind on the real install publishes its own vocabulary, and a
  // reading we cannot name renders as "—" — which is exactly as useless as no
  // tile at all. Occupancy sensors say `occupancy`/`occupied`; leak sensors say
  // `leak`/`water_detected`. A motion/occupancy sensor that hasn't reported yet
  // (Lutron only pushes a GROUP transition, never an initial state) reads
  // "clear" rather than "—" — the same default the old UI used.
  if (s['motion'] case final bool m) {
    bits.add(m ? 'motion' : 'clear');
  } else if (facet == DeviceFacet.motion) {
    bits.add('clear');
  }
  if ((s['occupancy'] ?? s['occupied']) case final bool o) {
    bits.add(o ? 'occupied' : 'clear');
  } else if (facet == DeviceFacet.occupancy) {
    bits.add('clear');
  }
  if ((s['leak'] ?? s['water_detected']) case final bool w) {
    bits.add(w ? 'WATER' : 'dry');
  }
  if (s['smoke'] case final bool sm) bits.add(sm ? 'SMOKE' : 'clear');
  // `contact` is deliberately NOT read. Every YoLink door sensor publishes it
  // alongside `open`, and under the electrical convention the two disagree —
  // this line used to append "open" to a door that had just been described as
  // "closed", on the same chip. `open` above is unambiguous and covers it. See
  // device_readings.dart for the full evidence.
  if (s['vibration'] case final bool v) bits.add(v ? 'vibration' : 'still');

  if (s['state'] case final String st when d.isMediaPlayer) bits.add(st);
  if (s['volume'] case final num v when d.isMediaPlayer) bits.add('vol $v');

  if (s['temperature'] case final num tmp) {
    // The unit is published; a bare degree sign next to 75.0 is ambiguous enough
    // to matter in a house.
    final unit = switch (s['temperature_unit']) {
      final String u when u.isNotEmpty => u.toUpperCase().replaceAll('°', ''),
      _ => '',
    };
    bits.add('${tmp.toStringAsFixed(1)}°$unit');
  }
  // Both spellings. YoLink publishes `humidity_pct` and declares it in its
  // schema; reading only `humidity` dropped the reading from every one of
  // them, so a sensor that plainly reports humidity showed none. John: *"The
  // yolink temperature sensors report humidity but I don't see a humidity
  // device listed."*
  if ((s['humidity'] ?? s['humidity_pct']) case final num h) {
    bits.add('${h.round()}%');
  }
  if (s['position'] case final num p) bits.add('${p.round()}% open');

  // A fan's speed is the reading. `speed_pct` is deliberately not shown: it is
  // the same fact in the units the wire protocol happens to use.
  if (s['speed'] case final String sp when sp.isNotEmpty && sp != 'off') {
    bits.add(fanSpeedLabel(sp));
  }

  // Battery is only worth a mention when it's a problem — and whether it is one
  // depends on how the device counts. A binary sensor's healthy `0` used to
  // land here as "0% batt" on every tile.
  if (batteryOf(d) case final batt? when batt.low) {
    bits.add('${batt.label} batt');
  }

  return bits.isEmpty ? '—' : bits.join(' · ');
}
