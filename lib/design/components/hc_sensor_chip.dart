import 'package:flutter/material.dart';

import '../../core/devices/presentation.dart';
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
    final facet = facetOf(device, device.schema);
    final offline = !device.available;
    final reading = offline ? 'Offline' : summarise(device);
    final alert = _alerting(device, offline);

    final accent = offline
        ? t.accent.offline
        : alert
            ? t.accent.danger
            : isOn(device)
                ? t.accent.active
                : t.surface.onBaseMuted;

    return InkWell(
      onTap: onTap,
      borderRadius: t.radius.mdR,
      child: Container(
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(facet.icon, size: 16, color: accent),
            SizedBox(width: t.space.sm),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    device.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.15,
                      color: t.surface.onBaseMuted,
                    ),
                  ),
                  Text(
                    reading,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: offline || alert ? accent : t.surface.onBase,
                      fontFeatures: t.numericFontFeatures,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
