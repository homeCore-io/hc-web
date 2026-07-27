import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/devices/metrics.dart';
import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/schema/attribute_policy.dart';
import '../../core/text/humanize.dart';
import '../../design/components/hc_now_playing.dart';
import '../../design/tokens.dart';

/// The one thing a device is *for*, given the room to be it.
///
/// The old panel opened on a tab bar and a list of `name → value` rows, which
/// treats a colour bulb, a weather station and a Sonos as the same kind of
/// object. They are not, and the panel's first screenful is where that should
/// show. A facet with nothing worth enlarging renders nothing at all — the
/// header toggle is already enough for a plain switch.
class DeviceHero extends ConsumerWidget {
  const DeviceHero({super.key, required this.device});

  final DeviceState device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facet = facetOf(device, device.schema);
    final notifier = ref.read(devicesProvider.notifier);

    return switch (facet) {
      DeviceFacet.light ||
      DeviceFacet.dimmableLight ||
      DeviceFacet.colorLight =>
        _LightHero(device: device, dimmable: facet != DeviceFacet.light),
      DeviceFacet.fan => _FanHero(device: device),
      DeviceFacet.lock => _LockHero(device: device),
      // A TV showing an HDMI input has no title, no artwork and no duration —
      // `query/media-player` never sees an input or the tuner, which is exactly
      // why hc-roku reports `state: "playing"` for both. Handing that to the
      // now-playing card gets the idle-speaker row, which is not wrong so much
      // as beside the point: the answer is *what is on screen*.
      DeviceFacet.mediaPlayer
          when (device.cleanTitle ?? '').isEmpty && _screenOf(device) != null =>
        _ScreenHero(device: device),
      DeviceFacet.mediaPlayer => HcNowPlaying(
          device: device,
          onPlayPause: () => notifier.command(device.id, {
            'action': device.playbackState == 'playing' ? 'pause' : 'play',
          }),
          onNext: () => notifier.command(device.id, {'action': 'next'}),
          onPrevious: () => notifier.command(device.id, {'action': 'previous'}),
          // The id is the card's, not ours: it renders a row per group member,
          // and each one's slider sets its own volume.
          onVolume: (id, v) => notifier
              .command(id, {'action': 'set_volume', 'value': v.round()}),
        ),
      // Sensors: the reading, at the size of the thing you opened the panel to
      // read. Everything else it reports stays below in Readings.
      _ when !facet.isActuator => _SensorHero(device: device),
      _ => const SizedBox.shrink(),
    };
  }
}

// ── Light ────────────────────────────────────────────────────────────────────

/// Brightness as a surface you drag, tinted by the colour the bulb is actually
/// rendering. A lamp showing a deep amber sunset and one on cool white are the
/// same row of numbers today; here they are visibly different objects.
class _LightHero extends ConsumerStatefulWidget {
  const _LightHero({required this.device, required this.dimmable});

  final DeviceState device;
  final bool dimmable;

  @override
  ConsumerState<_LightHero> createState() => _LightHeroState();
}

class _LightHeroState extends ConsumerState<_LightHero> {
  /// While a drag is in flight the local value leads and the device follows;
  /// otherwise the reported state wins. Without this the bar snaps back to the
  /// old value on every frame until the round-trip lands.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final d = widget.device;
    final on = d.available && isOn(d);
    final colour = lightColorOf(d) ?? t.accent.active;
    final pct = _dragging ?? ((levelOf(d) ?? 1.0) * 100);

    void commit(double v) {
      ref
          .read(devicesProvider.notifier)
          .command(d.id, {'on': true, 'brightness_pct': v.round()});
    }

    return LayoutBuilder(
      builder: (context, box) {
        void update(Offset local, {bool commitNow = false}) {
          if (!widget.dimmable || !d.available) return;
          final v = (local.dx / box.maxWidth * 100).clamp(1.0, 100.0);
          setState(() => _dragging = v);
          if (commitNow) {
            commit(v);
            setState(() => _dragging = null);
          }
        }

        return GestureDetector(
          onHorizontalDragUpdate: (e) => update(e.localPosition),
          onHorizontalDragEnd: (_) {
            final v = _dragging;
            if (v != null) {
              commit(v);
              setState(() => _dragging = null);
            }
          },
          onTapUp: (e) => update(e.localPosition, commitNow: true),
          child: MouseRegion(
            cursor: widget.dimmable
                ? SystemMouseCursors.resizeLeftRight
                : MouseCursor.defer,
            child: Container(
              height: 96,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: t.surface.sunken,
                borderRadius: t.radius.mdR,
                border: Border.all(color: t.stroke.hairline),
              ),
              child: Stack(
                children: [
                  // The fill is the brightness. At 10% it is a sliver; at 100%
                  // it floods — the same information the number carries, in a
                  // form you can read without reading.
                  AnimatedContainer(
                    duration: t.motion.d(t.motion.fast),
                    width: box.maxWidth * (pct / 100),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colour.withValues(alpha: on ? 0.30 : 0.05),
                          colour.withValues(alpha: on ? 0.62 : 0.08),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(t.space.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (widget.dimmable)
                              Text(
                                '${pct.round()}',
                                style: TextStyle(
                                  fontSize: 38,
                                  height: 1,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -1.6,
                                  color: on
                                      ? t.surface.onBase
                                      : t.surface.onBaseMuted,
                                  fontFeatures: t.numericFontFeatures,
                                ),
                              ),
                            if (widget.dimmable)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text('%',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: t.surface.onBaseMuted)),
                              ),
                            const Spacer(),
                            Text(
                              _whiteName(d) ?? (on ? 'On' : 'Off'),
                              style: TextStyle(
                                  fontSize: 11.5, color: t.surface.onBaseMuted),
                            ),
                          ],
                        ),
                        if (widget.dimmable) ...[
                          SizedBox(height: t.space.xs),
                          Text('Drag to dim',
                              style: TextStyle(
                                  fontSize: 11, color: t.surface.onBaseMuted)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The white a tunable bulb is sitting at, named rather than numbered. Hue
/// reports mirek and takes Kelvin, so the conversion happens here rather than
/// showing a number that does not match what you would send back.
String? _whiteName(DeviceState d) {
  final mirek = d.state['color_temp_mirek'];
  final k = mirek is num && mirek > 0
      ? 1000000 / mirek
      : (d.state['color_temp'] is num ? (d.state['color_temp'] as num) : null);
  if (k == null) return null;
  final name = switch (k) {
    < 2400 => 'Candle',
    < 3000 => 'Warm white',
    < 4200 => 'Soft white',
    < 5200 => 'Cool white',
    _ => 'Daylight',
  };
  return '$name · ${k.round()} K';
}

// ── Screen (a TV / streaming box, when there is no track to show) ────────────

/// What the device is showing: the app it is in, or the input it is on.
String? _screenOf(DeviceState d) {
  for (final k in const ['app_name', 'source']) {
    if (d.state[k] case final String v when v.isNotEmpty) return v;
  }
  return null;
}

class _ScreenHero extends StatelessWidget {
  const _ScreenHero({required this.device});

  final DeviceState device;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final on = device.state['on'] == true;
    final what = _screenOf(device) ?? '—';
    // Standby is not offline: ECP still answers, so the panel says so rather
    // than implying the TV has fallen off the network.
    final mode = device.state['power_mode'];
    final sub = on
        ? (device.state['screensaver_active'] == true
            ? 'Screensaver'
            : humanize(device.playbackState))
        : 'Standby${mode is String && mode.isNotEmpty ? ' · $mode' : ''}';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: t.radius.mdR,
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on
                  ? t.accent.primary.withValues(alpha: 0.16)
                  : t.surface.overlay,
              borderRadius: t.radius.smR,
            ),
            child: Icon(on ? Icons.tv_rounded : Icons.tv_off_rounded,
                size: 20, color: on ? t.accent.primary : t.surface.onBaseMuted),
          ),
          SizedBox(width: t.space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(what,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: on ? t.surface.onBase : t.surface.onBaseMuted,
                    )),
                Text(sub,
                    style:
                        TextStyle(fontSize: 12, color: t.surface.onBaseMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Fan ──────────────────────────────────────────────────────────────────────

/// A fan's speed is a named step, so it gets the steps — not a slider that
/// pretends to a precision the hardware does not have.
class _FanHero extends ConsumerWidget {
  const _FanHero({required this.device});

  final DeviceState device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final current = device.state['speed'];
    final enabled = device.available;

    return Container(
      padding: EdgeInsets.all(t.space.xs),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: t.radius.mdR,
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Row(
        children: [
          for (final s in kFanSpeeds)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled
                    ? () => ref
                        .read(devicesProvider.notifier)
                        .command(device.id, {'speed': s})
                    : null,
                child: AnimatedContainer(
                  duration: t.motion.d(t.motion.fast),
                  alignment: Alignment.center,
                  padding: EdgeInsets.symmetric(vertical: t.space.sm + 2),
                  decoration: BoxDecoration(
                    color: s == current ? t.accent.active : Colors.transparent,
                    borderRadius: t.radius.smR,
                  ),
                  child: Text(
                    fanSpeedLabel(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: s == current
                          ? t.accent.onPrimary
                          : t.surface.onBaseMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Lock ─────────────────────────────────────────────────────────────────────

/// Lock and Unlock, not a toggle. A padlock switch reads as "extra locked" in
/// one direction and says nothing about which way is safe.
class _LockHero extends ConsumerWidget {
  const _LockHero({required this.device});

  final DeviceState device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final locked = device.state['locked'];
    final enabled = device.available;

    Widget half(String label, bool value, IconData icon, Color tint) {
      final active = locked == value;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () => ref
                  .read(devicesProvider.notifier)
                  .command(device.id, {'locked': value})
              : null,
          child: AnimatedContainer(
            duration: t.motion.d(t.motion.fast),
            padding: EdgeInsets.symmetric(vertical: t.space.md),
            decoration: BoxDecoration(
              color: active ? tint.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: t.radius.smR,
              border: Border.all(
                color:
                    active ? tint.withValues(alpha: 0.5) : Colors.transparent,
              ),
            ),
            child: Column(
              children: [
                Icon(icon,
                    size: 20, color: active ? tint : t.surface.onBaseMuted),
                SizedBox(height: t.space.xs),
                Text(label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: active ? tint : t.surface.onBaseMuted,
                    )),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(t.space.xs),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: t.radius.mdR,
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Row(
        children: [
          half('Locked', true, Icons.lock_outline, t.accent.success),
          SizedBox(width: t.space.xs),
          half('Unlocked', false, Icons.lock_open_outlined, t.accent.warn),
        ],
      ),
    );
  }
}

// ── Sensor ───────────────────────────────────────────────────────────────────

/// The reading, at the size of the thing you opened the panel to read.
///
/// A weather station reports seventeen values and the old panel gave all of them
/// the same 12.5px row, so "is it hot out" took as long to answer as "what is
/// the vapour-pressure deficit".
class _SensorHero extends StatelessWidget {
  const _SensorHero({required this.device});

  final DeviceState device;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final primary = primaryMetricOf(device);
    if (primary == null) return const SizedBox.shrink();

    final (name, text, colour) = primary;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: t.radius.mdR,
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: t.surface.onBaseMuted,
            ),
          ),
          SizedBox(height: t.space.xs),
          Text(
            text,
            style: TextStyle(
              fontSize: 40,
              height: 1.05,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.6,
              color: colour,
              fontFeatures: t.numericFontFeatures,
            ),
          ),
        ],
      ),
    );
  }
}

/// The attributes the hero already puts on screen, so the Readings block does
/// not print the same fact underneath it. Derived here rather than in the panel
/// because the hero is the thing that knows what it drew.
Set<String> heroAttributesOf(DeviceState d) {
  final facet = facetOf(d, d.schema);
  return switch (facet) {
    DeviceFacet.light ||
    DeviceFacet.dimmableLight ||
    DeviceFacet.colorLight =>
      const {
        'on',
        'brightness',
        'brightness_pct',
        'color_temp',
        'color_temp_mirek',
        'color_temp_mirek_min',
        'color_temp_mirek_max',
        'color_xy',
        'color_rgb',
      },
    DeviceFacet.fan => const {'on', 'speed', 'speed_pct'},
    DeviceFacet.lock => const {'locked'},
    DeviceFacet.mediaPlayer => const {
        'on',
        'state',
        'title',
        'media_title',
        'media_duration',
        'media_position',
        'duration_secs',
        'position_secs',
        'volume',
        'app_name',
        'app_id',
        'source',
        'power_mode',
        'screensaver_active',
        'group_coordinator',
        'group_members',
      },
    _ when !facet.isActuator => {
        'on',
        // The SDK here predates null-aware set elements, so the null case is
        // spelled out rather than folded into the literal.
        ...switch (primaryMetricKeyOf(d)) {
          final k? => {k},
          _ => const <String>{},
        },
      },
    _ => const {'on'},
  };
}

/// The attribute [primaryMetricOf] chose, or null when it chose nothing.
String? primaryMetricKeyOf(DeviceState d) {
  final s = d.state;
  for (final k in const ['leak', 'water_detected', 'smoke', 'open']) {
    if (s[k] is bool) return k;
  }
  if (s['occupancy'] is bool) return 'occupancy';
  if (s['occupied'] is bool) return 'occupied';
  if (s['motion'] is bool) return 'motion';
  for (final k in const [
    'temperature',
    'current_temperature',
    'humidity',
    'illuminance_lux',
    'co2',
    'power',
  ]) {
    if (s[k] is num) return k;
  }
  return null;
}
