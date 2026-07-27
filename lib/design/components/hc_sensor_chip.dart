import 'package:flutter/material.dart';

import '../../core/devices/metrics.dart';
import '../../core/models/device_state.dart';
import '../tokens.dart';
import 'hc_tile.dart' show summarise;

/// A sensor, as the reading it is.
///
/// A leak sensor is not a thing you operate — it is a value you glance at — so
/// it has no business occupying the same 84px control card as a dimmable light.
/// Giving every one of a house's ~100 sensors that card is what turned the home
/// into "a box of things dumped on a canvas". This is the dense alternative: an
/// icon, a name, and its reading, packed several to a row.
///
/// It stays *legible*, not merely small: an alerting sensor (leak, smoke,
/// offline) is coloured so a wall of calm greys can never hide the one chip that
/// matters.
class HcSensorChip extends StatelessWidget {
  const HcSensorChip({super.key, required this.device, this.onTap});

  final DeviceState device;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final offline = !device.available;
    final alert = _alerting(device, offline);

    // The reading and its colour come from the same place the device panel's
    // hero uses, so a chip and the panel it opens never disagree about which
    // number matters or what colour it is. `summarise` is the fallback for a
    // device with no metric worth leading on.
    final metric = offline ? null : primaryMetricOf(device);
    // The fallback is `summarise`, which speaks in lowercase fragments meant to
    // be joined ("dry · 100%"). As a chip's whole value it needs a capital,
    // and its em-dash for "nothing reported" needs saying out loud — a bare
    // dash under a device's name reads as a rendering failure.
    final reading = offline ? 'Offline' : (metric?.$2 ?? _fallbackFor(device));

    final accent = offline
        ? t.accent.offline
        : alert
            ? t.accent.danger
            : (metric?.$3 ?? t.surface.onBase);

    return InkWell(
      onTap: onTap,
      borderRadius: t.radius.mdR,
      child: Container(
        // A floor, not a fixed width: chips that all start at the same size
        // form tidy rows, and a long name can still grow rather than being cut
        // to nothing. Without it every chip hugged its own text and the strip
        // read as rubble.
        constraints: const BoxConstraints(minWidth: 132),
        padding: EdgeInsets.symmetric(
            horizontal: t.space.sm + 2, vertical: t.space.sm),
        decoration: BoxDecoration(
          color: alert
              ? t.accent.danger.withValues(alpha: 0.10)
              : t.surface.raised,
          borderRadius: t.radius.mdR,
          border: Border.all(
            color: alert
                ? t.accent.danger.withValues(alpha: 0.45)
                : t.stroke.hairline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              device.displayName.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                height: 1.3,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: t.surface.onBaseMuted,
              ),
            ),
            Text(
              reading,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                height: 1.25,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: accent,
                fontFeatures: t.numericFontFeatures,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `summarise` said the way a chip needs it.
  static String _fallbackFor(DeviceState d) {
    final s = summarise(d);
    if (s == '—' || s.isEmpty) return 'No reading';
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }

  /// A reading worth colouring red: a detected leak or smoke. `summarise`
  /// uppercases exactly these when they fire.
  static bool _alerting(DeviceState d, bool offline) {
    if (offline) return false;
    final s = d.state;
    if ((s['leak'] ?? s['water_detected']) == true) return true;
    if (s['smoke'] == true) return true;
    return false;
  }
}
