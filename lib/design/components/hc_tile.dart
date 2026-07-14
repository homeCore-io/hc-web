import 'package:flutter/material.dart';

import '../../core/devices/presentation.dart';
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
  });

  final DeviceState device;
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

    // A sensor has no switch and no dimmer, however many writable attributes
    // happen to drift in. Offering one would invite the user to "turn off" a
    // motion sensor.
    final actuator = facet.isActuator;
    final dimmable = actuator && level != null && onLevel != null;

    final fg = offline
        ? t.accent.offline
        : on
            ? t.accent.active
            : t.surface.onBaseMuted;

    return _Pulse(
      pulse: pulse,
      child: HcSurface(
        onTap: onTap,
        glowColor: t.accent.active,
        // The halo is the level. Not a fixed "on" glow — a dim lamp must look
        // dim, or the wall panel lies about the room.
        glowIntensity: on ? (level ?? 1.0) : 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _Bulb(facet: facet, on: on, offline: offline, colour: fg),
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
            device.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
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
            style: TextStyle(
              fontSize: 11.5,
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
    required this.facet,
    required this.on,
    required this.offline,
    required this.colour,
  });

  final DeviceFacet facet;
  final bool on;
  final bool offline;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final size = (t.density.controlHeight * 0.78).clamp(30.0, 42.0);

    return AnimatedContainer(
      duration: t.motion.d(t.motion.base),
      curve: t.motion.curve,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? t.accent.active.withValues(alpha: 0.22) : t.surface.sunken,
        border: offline
            ? Border.all(color: t.accent.offline.withValues(alpha: 0.5))
            : null,
      ),
      // The glyph itself changes weight with state — see HcIcons.
      child: Icon(
        HcIcons.forFacet(facet, on: on),
        size: size * 0.5,
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
            borderRadius: BorderRadius.circular(t.radius.pill),
          ),
          child: AnimatedAlign(
            duration: t.motion.d(t.motion.fast),
            curve: t.motion.emphasized,
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
                  borderRadius: BorderRadius.circular(t.radius.pill),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: level.clamp(0.0, 1.0),
                  child: AnimatedContainer(
                    duration: t.motion.d(t.motion.base),
                    curve: t.motion.curve,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(t.radius.pill),
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

  if (s['locked'] case final bool l) bits.add(l ? 'locked' : 'unlocked');
  if (s['open'] case final bool o) bits.add(o ? 'open' : 'closed');
  if (s['motion'] case final bool m) bits.add(m ? 'motion' : 'clear');
  if (s['state'] case final String st when d.isMediaPlayer) bits.add(st);
  if (s['volume'] case final num v when d.isMediaPlayer) bits.add('vol $v');

  if (s['temperature'] case final num tmp) {
    bits.add('${tmp.toStringAsFixed(1)}°');
  }
  if (s['humidity'] case final num h) bits.add('${h.round()}%');
  if (s['position'] case final num p) bits.add('${p.round()}% open');

  // Battery is only worth a mention when it's a problem.
  if (s['battery'] case final num b when b <= 25) {
    bits.add('${b.round()}% batt');
  }

  return bits.isEmpty ? '—' : bits.join(' · ');
}
