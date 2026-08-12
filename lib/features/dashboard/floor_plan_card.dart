import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/floor_plan.dart';
import '../../core/devices/presentation.dart';
import '../../core/models/dashboard.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/text/humanize.dart';
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
    this.entered = false,
    this.onConfigChanged,
  });

  final Map<String, dynamic> config;

  /// The editor has been entered into this card, so markers can be placed.
  ///
  /// Placing is an explicit mode, decided rather than inferred. The
  /// alternative was to guess from what a drag started on — a marker, or the
  /// card beneath it — and a gesture that guesses between "move this marker"
  /// and "move this whole card" is the kind of cleverness that is wrong five
  /// percent of the time and infuriating for it.
  ///
  /// The mode is not this card's to own, though, and trying was the bug: the
  /// grid veils a card's body in the editor, so the Place button this card used
  /// to draw was underneath it — rendered, and impossible to press. Now the
  /// frame offers the way in and this flag is the answer. See
  /// [WidgetDescriptor.inPlaceLabel].
  final bool entered;

  /// Null when nothing is listening, which is also how this card knows it may
  /// not edit itself.
  final ValueChanged<Map<String, dynamic>>? onConfigChanged;

  @override
  ConsumerState<FloorPlanCard> createState() => _FloorPlanCardState();
}

class _FloorPlanCardState extends ConsumerState<FloorPlanCard> {
  /// Which marker is being dragged, by index. Null between gestures.
  int? _dragging;

  /// Which marker the inspector is about, by index. Null for none.
  ///
  /// By index, and so cleared whenever the list under it could have shifted:
  /// a marker has no id, because a marker is a *position and a selection* and
  /// giving it an identity would be inventing a thing the document does not
  /// have. Index is honest as long as nothing outlives the list.
  int? _selected;

  /// Where the keys land while a marker is selected.
  ///
  /// A child of the frame's own node, which is what makes Escape two-stage:
  /// this handles it while something is selected and *ignores* it otherwise,
  /// so the same key deselects and then leaves the card.
  final _focus = FocusNode(debugLabel: 'floor plan markers');

  /// May this card place markers right now? Being entered is not enough — the
  /// result has to have somewhere to go.
  bool get _placing => widget.entered && widget.onConfigChanged != null;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(FloorPlanCard old) {
    super.didUpdateWidget(old);
    // Left the card, e.g. by Escape. The gesture and the selection end with the
    // mode — an inspector for a marker you can no longer touch is a lie.
    if (!_placing) {
      _dragging = null;
      _selected = null;
      return;
    }
    // The list shrank under us — an undo, or another surface editing the same
    // draft. Selecting by index means never trusting a stale one.
    if (_selected != null &&
        _selected! >= markersFromConfig(widget.config).length) {
      _selected = null;
    }
  }

  void _select(int? index) {
    setState(() => _selected = index);
    if (index != null) _focus.requestFocus();
  }

  void _remove(int index) {
    final markers = markersFromConfig(widget.config);
    if (index < 0 || index >= markers.length) return;
    markers.removeAt(index);
    setState(() => _selected = null);
    _write(markers);
  }

  /// A name of your own, or none.
  ///
  /// Empty clears it rather than storing `''`: "no label" is a real choice —
  /// the default one — and a plan full of empty strings would be a plan whose
  /// document says something it does not mean.
  void _relabel(int index, String raw) {
    final markers = markersFromConfig(widget.config);
    if (index < 0 || index >= markers.length) return;
    final trimmed = raw.trim();
    markers[index] =
        markers[index].copyWith(label: trimmed.isEmpty ? null : trimmed);
    _write(markers);
  }

  KeyEventResult _onKey(KeyEvent event) {
    final index = _selected;
    if (index == null || event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      // Deselect first, leave the card second. One key, and never a surprise:
      // pressing it always undoes the last thing you got into.
      case LogicalKeyboardKey.escape:
        _select(null);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        _remove(index);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

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
    if (!_placing || box.width <= 0 || box.height <= 0) return;
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
        final selected =
            _selected != null && _selected! < markers.length ? _selected : null;
        return Focus(
          focusNode: _focus,
          onKeyEvent: (_, event) => _onKey(event),
          child: DragTarget<Object>(
            onWillAcceptWithDetails: (d) =>
                _placing && d.data is DashboardWidgetModel,
            onAcceptWithDetails: (d) => _drop(d.data, d.offset, size),
            builder: (context, candidate, __) => Stack(
              fit: StackFit.expand,
              children: [
                _Ground(url: url, config: widget.config),
                if (_placing) _EditingWash(inviting: candidate.isNotEmpty),
                if (_placing && markers.isEmpty) const _DropHint(),
                // Clicking the plan itself puts the inspector away, the way
                // clicking the canvas clears the card selection. Only while
                // placing: outside the mode this would swallow the taps that
                // will one day work a light from the plan.
                if (_placing)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _select(null),
                    ),
                  ),
                for (final (index, marker) in markers.indexed)
                  Positioned(
                    // Fractions, so the marker holds its place on the plan
                    // through a resize, a zoom and a breakpoint change.
                    left: marker.x * size.width,
                    top: marker.y * size.height,
                    child: FractionalTranslation(
                      translation: const Offset(-0.5, -0.5),
                      child: _placing
                          ? _Draggable(
                              dragging: _dragging == index,
                              // Touching a marker is how you get its inspector,
                              // and dragging one is touching it. Anything else
                              // would mean moving a marker and then hunting for
                              // the panel about the thing already under your
                              // finger.
                              onTap: () => _select(index),
                              onStart: () {
                                _select(index);
                                setState(() => _dragging = index);
                              },
                              onUpdate: (global) {
                                final rb = context.findRenderObject();
                                if (rb is! RenderBox) return;
                                _moveTo(index, rb.globalToLocal(global), size);
                              },
                              onEnd: () => setState(() => _dragging = null),
                              child: _Marker(
                                marker: marker,
                                devices: devices,
                                selected: selected == index,
                              ),
                            )
                          : _Marker(marker: marker, devices: devices),
                    ),
                  ),
                if (_placing && selected != null)
                  Positioned(
                    // Bottom-left, opposite the frame's Done chip, and pinned
                    // rather than following the marker: a panel that moves with
                    // what it is about is a panel you chase, and one anchored to
                    // a marker near an edge has nowhere to be.
                    left: 8,
                    bottom: 8,
                    child: _MarkerInspector(
                      key: ValueKey(selected),
                      marker: markers[selected],
                      devices: devices,
                      maxWidth: size.width - 16,
                      onLabel: (text) => _relabel(selected, text),
                      onRemove: () => _remove(selected),
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

/// A marker you can move.
///
/// The gesture is claimed here, on the marker, so the card's own drag never
/// sees it — which is what "the grid goes inert" means in practice.
class _Draggable extends StatelessWidget {
  const _Draggable({
    required this.dragging,
    required this.onTap,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.child,
  });

  final bool dragging;
  final VoidCallback onTap;
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
        onTap: onTap,
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
  const _Marker({
    required this.marker,
    required this.devices,
    this.selected = false,
  });

  final FloorPlanMarker marker;
  final List<DeviceState> devices;

  /// The inspector is about this one. Drawn as a ring rather than by changing
  /// the marker itself: a marker's own colour already means *this device is
  /// on*, and borrowing it to mean "chosen" would put a second meaning on the
  /// one thing the plan exists to say.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final matched = selectDevicesForConfig(devices, marker.selection);

    final Widget body;
    if (matched.isEmpty) {
      // A marker pointing at nothing is a placement mistake, and saying so
      // where it sits beats a blank spot on the plan.
      body = _Dot(
        icon: HcIcons.forFacet(DeviceFacet.unknown),
        on: false,
        label: marker.label,
        tint: t.surface.onBaseMuted,
      );
    } else if (facetOf(matched.first).presentation ==
        TilePresentation.readout) {
      // A sensor marker is its reading. The icon tells you nothing you did not
      // already know; the value is the entire reason the sensor is on the plan.
      body = _Reading(text: _readingOf(matched.first), label: marker.label);
    } else {
      // Any of them being on lights the marker, which is what makes one marker
      // able to speak for a room.
      final on = matched.any(isOn);
      body = _Dot(
        icon: HcIcons.forFacet(facetOf(matched.first), on: on),
        on: on,
        label: marker.label,
        tint: t.accent.active,
      );
    }

    if (!selected) return body;
    return Container(
      padding: EdgeInsets.all(t.space.xs / 2),
      decoration: BoxDecoration(
        borderRadius: t.radius.pillR,
        border: Border.all(color: t.surface.onBase, width: 1.5),
        color: t.surface.onBase.withValues(alpha: 0.08),
      ),
      child: body,
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

/// The one marker you touched: what it speaks for, what to call it, and the way
/// to get rid of it.
///
/// **On the card, not in the rail.** A marker is not a card, and the rail is
/// about the card — the plan, its picture, its dimming. More to the point, the
/// in-place editor on a phone has no rail at all, and a marker you can place
/// but never label or delete is the state this whole feature shipped in.
/// Anchored on the plan, it is in the same place on every surface.
///
/// Deliberately three things. Position is already editable — by dragging, which
/// is the entire point of the mode — and *which devices* is the card library's
/// job, done by dropping another one. Repeating either here would be a second
/// way to say something the plan already says better.
class _MarkerInspector extends StatelessWidget {
  const _MarkerInspector({
    super.key,
    required this.marker,
    required this.devices,
    required this.maxWidth,
    required this.onLabel,
    required this.onRemove,
  });

  final FloorPlanMarker marker;
  final List<DeviceState> devices;
  final double maxWidth;
  final ValueChanged<String> onLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth.clamp(120.0, 260.0)),
      child: Container(
        padding: EdgeInsets.all(t.space.sm),
        decoration: BoxDecoration(
          color: t.surface.overlay,
          borderRadius: t.radius.mdR,
          border: Border.all(color: t.stroke.hairline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Which marker this is about. Without it the panel could be about
            // any of them, and on a plan with eight markers that is a panel you
            // have to verify before you dare press Remove.
            Text(
              describeMarker(marker, devices),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
            ),
            SizedBox(height: t.space.xs),
            _LabelField(value: marker.label ?? '', onChanged: onLabel),
            SizedBox(height: t.space.xs),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRemove,
                icon: Icon(HcIcons.trash, size: 14, color: t.accent.danger),
                label: Text('Remove',
                    style:
                        t.text.captionStyle.copyWith(color: t.accent.danger)),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                      horizontal: t.space.sm, vertical: t.space.xs),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The custom name, or none.
///
/// Its own widget for its own controller: the card rewrites its config on every
/// keystroke — that is how an in-place edit reaches the draft — and a field
/// rebuilt from that config without one would put the caret back at the start
/// of the word on every letter.
class _LabelField extends StatefulWidget {
  const _LabelField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_LabelField> createState() => _LabelFieldState();
}

class _LabelFieldState extends State<_LabelField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return TextField(
      controller: _controller,
      // Not autofocused, deliberately. The field would swallow Delete, and
      // Delete on the marker you just touched is how you get rid of a marker
      // dropped in the wrong room — the commoner of the two things you come
      // here to do, and the one with no other keyboard route.
      style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        labelText: 'Label',
        labelStyle: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
        // Not the device's name: an unlabelled marker shows *nothing*, and a
        // hint naming the room would promise a word the plan will not draw.
        hintText: 'None',
        hintStyle: t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted),
      ),
    );
  }
}

/// What a marker speaks for, in the fewest words that identify it.
///
/// Public because the inspector is not the only thing that has to name a
/// marker — anything that lists or previews one must say the same words, or the
/// two disagree about which marker you are looking at.
String describeMarker(FloorPlanMarker marker, List<DeviceState> devices) {
  final area = marker.selection['area_name'];
  if (marker.selection['selection_mode'] == 'area' &&
      area is String &&
      area.isNotEmpty) {
    return humanize(area);
  }
  final matched = selectDevicesForConfig(devices, marker.selection);
  if (matched.isEmpty) return 'Nothing here now';
  if (matched.length == 1) return matched.first.displayName;
  return '${matched.length} devices';
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
