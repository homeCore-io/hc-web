import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/floor_plan.dart';
import '../../core/devices/presentation.dart';
import '../../core/models/dashboard.dart';
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
class FloorPlanCard extends ConsumerStatefulWidget {
  const FloorPlanCard({
    super.key,
    required this.config,
    this.editing = false,
    this.onConfigChanged,
  });

  final Map<String, dynamic> config;

  /// The designer is drawing this card, so plan editing can be *offered*.
  final bool editing;

  /// Null when nothing is listening, which is also how this card knows it may
  /// not edit itself.
  final ValueChanged<Map<String, dynamic>>? onConfigChanged;

  @override
  ConsumerState<FloorPlanCard> createState() => _FloorPlanCardState();
}

class _FloorPlanCardState extends ConsumerState<FloorPlanCard> {
  /// Plan editing is an explicit mode, decided rather than inferred.
  ///
  /// The alternative was to guess from what a drag started on — a marker, or
  /// the card beneath it — and a gesture that guesses between "move this
  /// marker" and "move this whole card" is the kind of cleverness that is
  /// wrong five percent of the time and infuriating for it. So: a button in,
  /// Escape out, the way entering a group works in a vector editor.
  bool _planEditing = false;

  /// Which marker is being dragged, by index. Null between gestures.
  int? _dragging;

  final _focus = FocusNode(debugLabel: 'floor plan');

  bool get _canEdit => widget.editing && widget.onConfigChanged != null;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _enter() {
    setState(() => _planEditing = true);
    _focus.requestFocus();
  }

  void _leave() => setState(() {
        _planEditing = false;
        _dragging = null;
      });

  void _write(List<FloorPlanMarker> markers) {
    widget.onConfigChanged?.call({
      ...widget.config,
      'markers': [for (final m in markers) m.toJson()],
    });
  }

  /// A device dropped from the library becomes a marker where the pointer was.
  ///
  /// Accepted only while the mode is on, deliberately. Outside it the canvas
  /// beneath is itself a drop target — that is how a card gets placed — and two
  /// things claiming the same drop would make which one you got depend on
  /// pixels. Inside the mode the plan wins, unambiguously.
  void _drop(Object? payload, Offset global, Size box) {
    if (!_planEditing || box.width <= 0 || box.height <= 0) return;
    if (payload is! DashboardWidgetModel) return;
    final rb = context.findRenderObject();
    if (rb is! RenderBox) return;
    final local = rb.globalToLocal(global);

    final markers = markersFromConfig(widget.config)
      ..add(FloorPlanMarker(
        selection: selectionFromPayload(payload.config),
        x: local.dx / box.width,
        y: local.dy / box.height,
        // No label: a plan that starts life labelled is a word search, and the
        // inspector is where you give one a name it did not have.
      ));
    _write(markers);
  }

  void _moveTo(int index, Offset local, Size box) {
    final markers = markersFromConfig(widget.config);
    if (index < 0 || index >= markers.length) return;
    if (box.width <= 0 || box.height <= 0) return;
    markers[index] = markers[index].copyWith(
      x: local.dx / box.width,
      y: local.dy / box.height,
    );
    _write(markers);
  }

  @override
  Widget build(BuildContext context) {
    final url = (widget.config['url'] as String?)?.trim() ?? '';
    final markers = markersFromConfig(widget.config);
    final devices = ref.watch(devicesProvider).value ?? const <DeviceState>[];

    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        return Focus(
          focusNode: _focus,
          onKeyEvent: (_, event) {
            if (_planEditing &&
                event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              _leave();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: DragTarget<Object>(
            onWillAcceptWithDetails: (d) =>
                _planEditing && d.data is DashboardWidgetModel,
            onAcceptWithDetails: (d) => _drop(d.data, d.offset, size),
            builder: (context, candidate, __) => Stack(
              fit: StackFit.expand,
              children: [
                _Ground(url: url, config: widget.config),
                if (_planEditing) _EditingWash(inviting: candidate.isNotEmpty),
                if (_planEditing && markers.isEmpty) const _DropHint(),
                for (final (index, marker) in markers.indexed)
                  Positioned(
                    // Fractions, so the marker holds its place on the plan
                    // through a resize, a zoom and a breakpoint change.
                    left: marker.x * size.width,
                    top: marker.y * size.height,
                    child: FractionalTranslation(
                      translation: const Offset(-0.5, -0.5),
                      child: _planEditing
                          ? _Draggable(
                              dragging: _dragging == index,
                              onStart: () => setState(() => _dragging = index),
                              onUpdate: (global) {
                                final rb = context.findRenderObject();
                                if (rb is! RenderBox) return;
                                _moveTo(index, rb.globalToLocal(global), size);
                              },
                              onEnd: () => setState(() => _dragging = null),
                              child: _Marker(marker: marker, devices: devices),
                            )
                          : _Marker(marker: marker, devices: devices),
                    ),
                  ),
                if (_canEdit)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: _EditToggle(
                      editing: _planEditing,
                      onPressed: _planEditing ? _leave : _enter,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// While the mode is on, the plan says so.
///
/// Not decoration: entering a mode you cannot see is how you end up dragging
/// markers when you meant to move the card, which is the confusion the mode
/// exists to remove.
class _EditingWash extends StatelessWidget {
  const _EditingWash({this.inviting = false});

  /// Something draggable is over the plan right now.
  final bool inviting;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: t.accent.active, width: inviting ? 3 : 2),
          color: t.accent.active.withValues(alpha: inviting ? 0.10 : 0.04),
        ),
      ),
    );
  }
}

/// What to do with an empty plan, said on the empty plan.
///
/// The mode is enterable before there is anything in it to move, so without
/// this the first thing you see after pressing Place is a picture that does
/// nothing.
class _DropHint extends StatelessWidget {
  const _DropHint();

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: t.space.md, vertical: t.space.sm),
          decoration: BoxDecoration(
            color: t.surface.raised.withValues(alpha: 0.9),
            borderRadius: t.radius.mdR,
            border: Border.all(color: t.stroke.hairline),
          ),
          child: Text(
            'Drag a device or a room onto the plan.',
            style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
          ),
        ),
      ),
    );
  }
}

/// In, and out.
class _EditToggle extends StatelessWidget {
  const _EditToggle({required this.editing, required this.onPressed});

  final bool editing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Tooltip(
      message: editing ? 'Done placing — or press Escape' : 'Place markers',
      child: Material(
        color:
            editing ? t.accent.active : t.surface.raised.withValues(alpha: .9),
        shape: RoundedRectangleBorder(borderRadius: t.radius.pillR),
        child: InkWell(
          borderRadius: t.radius.pillR,
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: t.space.sm, vertical: t.space.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(editing ? Icons.check : Icons.edit_location_alt_outlined,
                    size: 14,
                    color: editing ? t.accent.onPrimary : t.surface.onBase),
                SizedBox(width: t.space.xs),
                Text(
                  editing ? 'Done' : 'Place',
                  style: t.text.captionStyle.copyWith(
                      color: editing ? t.accent.onPrimary : t.surface.onBase),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A marker you can move.
///
/// The gesture is claimed here, on the marker, so the card's own drag never
/// sees it — which is what "the grid goes inert" means in practice.
class _Draggable extends StatelessWidget {
  const _Draggable({
    required this.dragging,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.child,
  });

  final bool dragging;
  final VoidCallback onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => onStart(),
        onPanUpdate: (d) => onUpdate(d.globalPosition),
        onPanEnd: (_) => onEnd(),
        onPanCancel: onEnd,
        child: Opacity(opacity: dragging ? 0.75 : 1, child: child),
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

/// The selection half of a card the library was about to place.
///
/// A row in the library drags a whole `DashboardWidgetModel` — a card, with a
/// type and a title and presentation settings. Dropped on a plan it should
/// become a *marker*, and the part that carries over is the selection: which
/// devices it meant. Everything else described a card that is not being made.
///
/// So a "Living Room" row becomes a marker that speaks for the living room,
/// and a single device becomes a marker for that device, with no new vocabulary
/// on either side.
Map<String, dynamic> selectionFromPayload(Map<String, dynamic> config) {
  const keys = [
    'selection_mode',
    'device_ids',
    'area_name',
    'facet',
    'query',
    'limit',
    'show_offline',
  ];
  return {
    for (final k in keys)
      if (config.containsKey(k)) k: config[k],
  };
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
