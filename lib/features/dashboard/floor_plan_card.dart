import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/floor_plan.dart';
import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../devices/device_readings.dart';
import 'builtin_cards.dart';

/// A picture of the house, with the house on it.
///
/// **The plan is ground, the live state is figure.** Everything here follows
/// from that: the picture is held back by [planDim] and, where it is line art
/// on white, turned inside out by [planInvert], so that the markers are the
/// only saturated, glowing, moving things on the card. Get it wrong and it is
/// a pretty picture you cannot read; get it right and a lit room is visible
/// across a dark one at a glance.
///
/// A marker is **not a new kind of thing**. It is what the device already is,
/// placed at a point: the same [DeviceFacet] and [TilePresentation] the tiles
/// use decide whether it draws as a glowing dot or as a reading. That means a
/// plan needs no second opinion about what a device is, and cannot drift from
/// the rest of the app.
class FloorPlanCard extends ConsumerWidget {
  const FloorPlanCard({super.key, required this.config});

  final Map<String, dynamic> config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = (config['url'] as String?)?.trim() ?? '';
    final markers = markersFromConfig(config);
    final devices = ref.watch(devicesProvider).value ?? const <DeviceState>[];

    return LayoutBuilder(
      builder: (context, box) => Stack(
        fit: StackFit.expand,
        children: [
          _Ground(url: url, config: config),
          for (final marker in markers)
            Positioned(
              // Fractions, so the marker holds its place on the plan through a
              // resize, a zoom and a breakpoint change.
              left: marker.x * box.maxWidth,
              top: marker.y * box.maxHeight,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5),
                child: _Marker(marker: marker, devices: devices),
              ),
            ),
        ],
      ),
    );
  }
}

/// The picture, held back.
class _Ground extends StatelessWidget {
  const _Ground({required this.url, required this.config});

  final String url;
  final Map<String, dynamic> config;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    if (url.isEmpty) {
      return ColoredBox(
        color: t.surface.sunken,
        child: Center(
          child: Text(
            'Choose a picture of your floor plan.',
            style: t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted),
          ),
        ),
      );
    }

    Widget image = Image.network(
      url,
      fit: switch (config['fit'] as String?) {
        'cover' => BoxFit.cover,
        'fill' => BoxFit.fill,
        // Contain by default, unlike the plain image card: a floor plan cropped
        // to fill the card is a floor plan with rooms cut off it.
        _ => BoxFit.contain,
      },
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => ColoredBox(
        color: t.surface.sunken,
        child: Center(
          child: Text('That address did not load.',
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted)),
        ),
      ),
    );

    if (planInvert(config)) {
      image = ColorFiltered(colorFilter: _invert, child: image);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        // Dim as a scrim in the surface colour rather than in black: on a light
        // skin, black would grey the plan out instead of settling it back into
        // the card.
        IgnorePointer(
          child: ColoredBox(
            color: t.surface.base.withValues(alpha: planDim(config)),
          ),
        ),
      ],
    );
  }
}

/// Luminance inversion, hue left alone.
///
/// Floor plans in the wild are black line art on white. Dropped onto a dark
/// skin that is a white slab with the house's state invisible on it, so this
/// is the difference between the feature working and not for most images
/// anyone actually has.
const _invert = ColorFilter.matrix(<double>[
  -1, 0, 0, 0, 255, //
  0, -1, 0, 0, 255, //
  0, 0, -1, 0, 255, //
  0, 0, 0, 1, 0, //
]);

/// What the device already is, at a point.
class _Marker extends StatelessWidget {
  const _Marker({required this.marker, required this.devices});

  final FloorPlanMarker marker;
  final List<DeviceState> devices;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final selected = selectDevicesForConfig(devices, marker.selection);

    // A marker pointing at nothing is a placement mistake, and saying so where
    // it sits beats a blank spot on the plan.
    if (selected.isEmpty) {
      return _Dot(
        icon: HcIcons.forFacet(DeviceFacet.unknown),
        on: false,
        label: marker.label,
        tint: t.surface.onBaseMuted,
      );
    }

    final lead = selected.first;
    final facet = facetOf(lead);

    // A sensor marker is its reading. The icon tells you nothing you did not
    // already know; the value is the entire reason the sensor is on the plan.
    if (facet.presentation == TilePresentation.readout) {
      return _Reading(text: _readingOf(lead), label: marker.label);
    }

    // Any of them being on lights the marker, which is what makes one marker
    // able to speak for a room.
    final on = selected.any(isOn);
    return _Dot(
      icon: HcIcons.forFacet(facet, on: on),
      on: on,
      label: marker.label,
      tint: t.accent.active,
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.icon,
    required this.on,
    required this.tint,
    this.label,
  });

  final IconData icon;
  final bool on;
  final Color tint;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on
                ? tint.withValues(alpha: 0.22)
                : t.surface.raised.withValues(alpha: 0.85),
            border: Border.all(
              color: on ? tint : t.stroke.hairline,
              width: on ? 1.5 : 1,
            ),
            // The app's own signature: a lit thing spills light. Through
            // `glow.halo` and not a hand-rolled BoxShadow, so a flat skin —
            // where strength is 0 — simply has no halo rather than growing one
            // this card invented. The token ratchet catches the other way.
            boxShadow: on ? t.glow.halo(tint, blur: 16, alpha: 0.45) : null,
          ),
          child: Icon(icon, size: 16, color: on ? tint : t.surface.onBaseMuted),
        ),
        if (label != null) ...[
          SizedBox(width: t.space.xs),
          _Plate(child: Text(label!, style: t.text.captionStyle)),
        ],
      ],
    );
  }
}

/// A number, which is the whole marker.
class _Reading extends StatelessWidget {
  const _Reading({required this.text, this.label});

  final String text;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return _Plate(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            // Tabular, because a live number that changes width shoves the
            // plan around under it.
            style: t.text.bodySmallStyle.copyWith(
              color: t.surface.onBase,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (label != null) ...[
            SizedBox(width: t.space.xs),
            Text(label!,
                style:
                    t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
          ],
        ],
      ),
    );
  }
}

/// The one number a sensor is on the plan for.
///
/// There is no "primary reading" on `DeviceState` and inventing a getter for
/// one would be a decision the rest of the app has not made. So: the first of
/// these the device actually reports, formatted the way the device panel
/// formats it, and the device's own state string if it reports none of them.
String _readingOf(DeviceState d) {
  const candidates = [
    'temperature',
    'humidity',
    'power',
    'illuminance',
    'co2',
    'pressure',
    'battery',
  ];
  for (final key in candidates) {
    if (d.state[key] != null) return formatReading(d, key);
  }
  final fallback = d.state['state'];
  return fallback is String && fallback.isNotEmpty ? fallback : '—';
}

/// A small backing so text stays readable over any part of the picture.
class _Plate extends StatelessWidget {
  const _Plate({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: t.space.xs, vertical: t.space.xs / 2),
      decoration: BoxDecoration(
        color: t.surface.raised.withValues(alpha: 0.85),
        borderRadius: t.radius.smR,
        border: Border.all(color: t.stroke.hairline),
      ),
      child: child,
    );
  }
}
