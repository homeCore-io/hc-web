import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/floor_plan.dart';
import '../../core/dashboard/sweet_home.dart';
import '../../core/devices/presentation.dart';
import '../../core/models/dashboard.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../devices/device_readings.dart';
import '../devices/device_sheet.dart';
import 'builtin_cards.dart';
import 'plan_view.dart';

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

  /// The room the pointer is over, so the drawing can say so. Hover only.
  PlanRoom? _hovered;

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

  /// What pressing a marker means, or null when it means nothing.
  ///
  /// **One decision, used three ways** — it names the marker for a screen
  /// reader, decides whether the cursor says "pressable", and is what runs on
  /// the tap. Derived separately, those drift, and a plan that says *on* while
  /// turning something on is worse than one that does nothing.
  ///
  /// The rule is §7.4's: a marker glows if any of its devices are on, and
  /// pressing it turns *all* of them off — the honest 80% of a room zone with
  /// no polygon geometry. Which is also why the decision is taken over the
  /// devices the press can actually command: a marker whose group holds a
  /// speaker must not promise to switch it, and must not sit there dead
  /// because of it either.
  ({String label, VoidCallback act})? _pressFor(
          FloorPlanMarker marker, List<DeviceState> devices) =>
      _pressOn(marker.selection,
          marker.label ?? describeMarker(marker, devices), devices);

  /// The same decision for anything on the plan that can be pressed — a marker,
  /// or a room of an imported home. One rule, so a room and a dot standing in
  /// it can never disagree about what pressing does.
  ({String label, VoidCallback act})? _pressOn(
      Map<String, dynamic> selection, String name, List<DeviceState> devices) {
    // Inside the card a press means "show me this marker", and the plan is a
    // thing being arranged rather than a thing being worked.
    if (widget.entered) return null;

    final matched = selectDevicesForConfig(devices, selection);
    if (matched.isEmpty) return null;

    final switches = [
      for (final d in matched)
        if (!d.isMediaPlayer &&
            facetOf(d).presentation == TilePresentation.control)
          d,
    ];

    // Nothing here takes a bare on/off: a sensor, or a speaker where "on"
    // would be the wrong verb. The tiles answer the same tap with the detail
    // sheet, and a temperature you can press through to its history is worth
    // more than a marker that ignores you.
    if (switches.isEmpty) {
      final lead = matched.first;
      // The reading is what the marker draws and the whole reason it is on the
      // plan, so it belongs in the spoken name too — the label has to carry
      // everything the picture says.
      final reading = facetOf(lead).presentation == TilePresentation.readout
          ? ', ${_readingOf(lead)}'
          : '';
      return (
        label: '$name$reading',
        act: () => showDeviceSheet(context, lead.id),
      );
    }

    final on = switches.any(isOn);
    return (
      label: '$name, ${on ? 'on' : 'off'}',
      act: () {
        final notifier = ref.read(devicesProvider.notifier);
        for (final d in switches) {
          // Optimistic, with its own rollback and failure reporting — so the
          // marker lights the instant you press it, and un-lights itself if
          // the house disagrees. See DevicesNotifier.command.
          notifier.command(d.id, {'on': !on});
        }
      },
    );
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
    final fit = _fitFor(box);
    final markers = markersFromConfig(widget.config);

    // Dropped *on* a marker that is waiting to be told what it is: bind that
    // one rather than laying a second dot on top of it. This is how an
    // imported home gets bound — the file placed the lamps, you say which
    // device each one is, and the gesture is the same one that places a marker
    // from nothing.
    final waiting = _unboundAt(local, markers, fit, box);
    if (waiting != null) {
      markers[waiting] = markers[waiting]
          .copyWith(selection: selectionFromPayload(payload.config));
      _write(markers);
      _select(waiting);
      return;
    }

    markers.add(FloorPlanMarker(
      selection: selectionFromPayload(payload.config),
      x: local.dx / box.width,
      y: local.dy / box.height,
      // On a drawn home the card is the wrong frame, so the point is kept in
      // the home's own centimetres as well. The fractions stay as the
      // fallback for a card whose home is later removed.
      home: fit?.toHome(local),
      // No label: a plan that starts life labelled is a word search, and the
      // inspector is where you give one a name it did not have.
    ));
    _write(markers);
  }

  void _moveTo(int index, Offset local, Size box) {
    final markers = markersFromConfig(widget.config);
    if (index < 0 || index >= markers.length) return;
    if (box.width <= 0 || box.height <= 0) return;
    final fit = _fitFor(box);
    markers[index] = markers[index].copyWith(
      x: local.dx / box.width,
      y: local.dy / box.height,
      home: fit?.toHome(local),
    );
    _write(markers);
  }

  /// The room a marker stands in, and what the house has in it.
  ///
  /// Null unless all three hold: the marker has a place in an imported home,
  /// that place falls in a room the file named, and this house has an area of
  /// the same name. Any of them missing and there is nothing honest to offer,
  /// so the panel says to drag instead.
  ({String room, String area, List<DeviceState> devices})? _nearby(
      FloorPlanMarker marker, List<DeviceState> devices) {
    final at = marker.home;
    if (at == null) return null;
    final plan = planFromConfig(widget.config);
    final name = plan?.roomAt(at)?.name;
    if (name == null || name.isEmpty) return null;

    final wanted = humanize(name);
    final inRoom = [
      for (final d in devices)
        if (d.effectiveArea != null && humanize(d.effectiveArea) == wanted) d,
    ];
    if (inRoom.isEmpty) return null;
    // The area key as the house spells it, taken from a device rather than
    // guessed back from the room's name.
    return (room: name, area: inRoom.first.effectiveArea!, devices: inRoom);
  }

  void _bind(int index, Map<String, dynamic> selection) {
    final markers = markersFromConfig(widget.config);
    if (index < 0 || index >= markers.length) return;
    markers[index] = markers[index].copyWith(selection: selection);
    _write(markers);
  }

  /// The rooms of a drawn home, as things you can press.
  ///
  /// A room is offered only when the house has an **area of the same name** —
  /// `Living Room` in the file against `living_room` here, compared after the
  /// same humanising the rest of the app does. An exact match after
  /// normalisation rather than anything fuzzy: a room that quietly worked a
  /// different room's lights would be the worst bug this card could have, and a
  /// room with no match simply is not pressable.
  List<Widget> _roomTargets(HomePlan? plan, PlanFit? fit,
      List<DeviceState> devices, PlanRoom? hovered) {
    if (plan == null || fit == null || widget.entered) return const [];

    // The house's own areas, by the name a person would read.
    final areas = <String, String>{};
    for (final d in devices) {
      final area = d.effectiveArea;
      if (area != null && area.isNotEmpty) areas[humanize(area)] = area;
    }

    return [
      for (final room in plan.rooms)
        if (room.points.length >= 3 && room.name != null)
          if (areas[humanize(room.name)] case final area?)
            if (_pressOn({'selection_mode': 'area', 'area_name': area},
                    room.name!, devices)
                case final press?)
              PlanRoomTarget(
                key: ValueKey(room.name),
                room: room,
                fit: fit,
                label: press.label,
                onTap: press.act,
                onHover: (over) => setState(() => _hovered =
                    over ? room : (_hovered == room ? null : _hovered)),
              ),
    ];
  }

  /// The unbound marker under a point, if the drop is close enough to have
  /// meant it.
  ///
  /// Only unbound ones: dropping a device on a marker that already stands for
  /// something would be an edit nobody asked for, and the place to change what
  /// a marker means is not a gesture you can make by half an inch of aim.
  int? _unboundAt(
      Offset local, List<FloorPlanMarker> markers, PlanFit? fit, Size box) {
    // A little wider than the dot itself, so a drop that visually lands on a
    // marker counts as one, and no wider — two lamps in the same room are
    // often a hand's width apart on the drawing.
    const reach = 22.0;
    for (final (index, marker) in markers.indexed) {
      if (!isUnbound(marker)) continue;
      if ((_pointOf(marker, fit, box) - local).distance <= reach) return index;
    }
    return null;
  }

  /// The transform between this card and the home it is drawing, or null when
  /// it is drawing a picture instead.
  PlanFit? _fitFor(Size box) {
    final plan = planFromConfig(widget.config);
    return plan == null ? null : PlanFit.of(plan, box);
  }

  /// Where a marker sits on the card, in pixels.
  ///
  /// Anchored to the home when it has a place in one and the card still draws
  /// that home; otherwise a fraction of the card. Both are stored, so removing
  /// a home leaves every marker roughly where it looked rather than piled in
  /// the corner.
  Offset _pointOf(FloorPlanMarker marker, PlanFit? fit, Size size) {
    final home = marker.home;
    if (fit != null && home != null) return fit.toCard(home.x, home.y);
    return Offset(marker.x * size.width, marker.y * size.height);
  }

  /// One marker, in whichever of its two lives this card is having.
  ///
  /// Placing, it is a thing you move and inspect. Otherwise it is a control:
  /// the plan stops being a picture of the house and becomes a way to work it,
  /// which is the whole point of putting the house on a plan.
  Widget _markerAt({
    required int index,
    required FloorPlanMarker marker,
    required List<DeviceState> devices,
    required Size size,
    required bool selected,
  }) {
    if (_placing) {
      return _Draggable(
        dragging: _dragging == index,
        // Touching a marker is how you get its inspector, and dragging one is
        // touching it. Anything else would mean moving a marker and then
        // hunting for the panel about the thing already under your finger.
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
        child: _Marker(marker: marker, devices: devices, selected: selected),
      );
    }

    final body = _Marker(marker: marker, devices: devices);
    final press = _pressFor(marker, devices);
    // A marker pointing at nothing, or at something with nothing to press, is
    // drawn and left alone rather than given a dead affordance.
    if (press == null) return body;
    return _Tappable(label: press.label, onTap: press.act, child: body);
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
        // Computed once for the frame: the drawing and everything standing on
        // it must agree, and recomputing per marker is how they stop agreeing.
        final fit = _fitFor(size);
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
                _Ground(url: url, config: widget.config, lit: _hovered),
                // Under the markers, so a dot standing in a room is still the
                // thing you press when you press the dot.
                ..._roomTargets(
                    planFromConfig(widget.config), fit, devices, _hovered),
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
                    // Never a pixel from the document: either the home's own
                    // centimetres or a fraction of the card, so the marker
                    // holds its place through a resize, a zoom and a
                    // breakpoint change.
                    left: _pointOf(marker, fit, size).dx,
                    top: _pointOf(marker, fit, size).dy,
                    child: FractionalTranslation(
                      translation: const Offset(-0.5, -0.5),
                      child: _markerAt(
                        index: index,
                        marker: marker,
                        devices: devices,
                        size: size,
                        selected: selected == index,
                      ),
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
                      nearby: _nearby(markers[selected], devices),
                      onBind: (selection) => _bind(selected, selection),
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

/// A marker you can press.
///
/// The gesture is a plain tap and nothing else: a plan lives inside a scrolling
/// page, and a marker that claimed drags would fight the page for every
/// gesture that started on it.
class _Tappable extends StatelessWidget {
  const _Tappable({
    required this.label,
    required this.onTap,
    required this.child,
  });

  /// What this marker is and what state it is in, for anyone not looking at
  /// the glow — which is the only thing the sighted version says.
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Semantics(
        // Its own node, not an annotation folded into the card's. Without this
        // every marker's name lands on one big node covering the whole plan,
        // which is a plan a screen reader reads as a single sentence.
        container: true,
        button: true,
        label: label,
        // The label already carries everything the marker draws — its name and
        // its state or reading — so letting the plate underneath announce
        // itself as well would say the name twice.
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
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
  const _Ground({required this.url, required this.config, this.lit});

  final String url;
  final Map<String, dynamic> config;

  /// The room under the pointer, passed through to the drawing.
  final PlanRoom? lit;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    // An imported home, if there is one. Drawn *over* the picture rather than
    // instead of it: both can come from the same Sweet Home 3D file, and when
    // they do — a top-down render plus the geometry that made it — they are
    // registered to each other and belong on top of one another.
    final drawn = planFromConfig(config);

    if (url.isEmpty) {
      if (drawn != null) {
        return ColoredBox(
          color: t.surface.sunken,
          child: PlanView(plan: drawn, lit: lit),
        );
      }
      return ColoredBox(
        color: t.surface.sunken,
        child: Center(
          child: Text(
            'Choose a picture of your floor plan, or import a Sweet Home 3D '
            'file.',
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
        // Above the scrim, and so undimmed. Dimming exists to make a photograph
        // survivable underneath live state; a drawing already in the skin's own
        // muted ink has nothing to be held back from.
        if (drawn != null) PlanView(plan: drawn, lit: lit),
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

  /// The dot is the marker, and the marker is a point on a plan.
  static const _size = 30.0;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final dot = Container(
      width: _size,
      height: _size,
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
    );
    if (label == null) return dot;

    // **The label hangs off the dot; it must not move it.**
    //
    // As a Row it did: the caller centres this whole widget on the marker's
    // point, so a dot with a name beside it sat half the name's width to the
    // left of the spot it was placed on — and grew further off as the name got
    // longer. Nothing in the document moved, which is what made it easy to
    // miss: the fraction was right and the drawing was wrong, on the plan and
    // in view mode alike.
    //
    // A Stack sized by the dot alone fixes it without measuring anything: only
    // the unpositioned child decides the size, the label is placed past the
    // dot's edge, and `Clip.none` lets it paint outside. The dot stays the
    // hit target, which is also the honest answer to "what am I grabbing".
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        dot,
        Positioned(
          left: _size + t.space.xs,
          child: _Plate(child: Text(label!, style: t.text.captionStyle)),
        ),
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
    required this.nearby,
    required this.onBind,
  });

  final FloorPlanMarker marker;
  final List<DeviceState> devices;
  final double maxWidth;
  final ValueChanged<String> onLabel;
  final VoidCallback onRemove;

  /// The room this marker stands in and what is in it, when the plan knows —
  /// see [_FloorPlanCardState._nearby].
  final ({String room, String area, List<DeviceState> devices})? nearby;

  /// Bind the marker to a selection.
  final ValueChanged<Map<String, dynamic>> onBind;

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
            // A marker the import placed is half a job. The other half is a
            // choice among what is *in that room* — the file knows which room
            // the lamp hangs in, so the list is three or four things rather
            // than the whole house.
            if (isUnbound(marker)) _Bind(nearby: nearby, onBind: onBind),
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

/// What a marker placed by an import could be.
///
/// **The room does the narrowing.** The file says the lamp hangs in the
/// bedroom, so the question stops being "which of 188 devices is this" and
/// becomes "which of the four things in the bedroom" — which is a list you can
/// read, and the difference between an import that saves work and one that
/// hands you a puzzle.
///
/// Nothing is guessed even so. Every device here is one press, and the press is
/// yours: a name that nearly matches still gets picked by a person.
class _Bind extends StatelessWidget {
  const _Bind({required this.nearby, required this.onBind});

  final ({String room, String area, List<DeviceState> devices})? nearby;
  final ValueChanged<Map<String, dynamic>> onBind;

  /// Enough to choose from, few enough to read at a glance on a panel this
  /// size. Past it the library is the better tool and says so.
  static const _most = 6;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final at = nearby;
    // No room, or a room this house has no area for: the drag is the only way,
    // and saying so beats an empty list.
    if (at == null || at.devices.isEmpty) {
      return Text('Drop a device on it to say which one.',
          style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted));
    }

    final shown = at.devices.take(_most).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('In ${at.room}:',
            style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
        SizedBox(height: t.space.xs),
        Wrap(
          spacing: t.space.xs,
          runSpacing: t.space.xs,
          children: [
            // The room itself first: one marker speaking for a room is the
            // shape §7.4 is built around, and on a plan it is often what you
            // wanted rather than a single lamp.
            _BindChip(
              label: 'The whole room',
              onTap: () => onBind({
                'selection_mode': 'area',
                'area_name': at.area,
              }),
            ),
            for (final device in shown)
              _BindChip(
                label: device.displayName,
                onTap: () => onBind({
                  'selection_mode': 'manual',
                  'device_ids': [device.id],
                }),
              ),
          ],
        ),
        if (at.devices.length > _most) ...[
          SizedBox(height: t.space.xs),
          Text(
            '${at.devices.length - _most} more — drop one on it instead.',
            style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
          ),
        ],
      ],
    );
  }
}

class _BindChip extends StatelessWidget {
  const _BindChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Material(
      color: t.surface.raised,
      shape: RoundedRectangleBorder(
        borderRadius: t.radius.smR,
        side: BorderSide(color: t.stroke.hairline),
      ),
      child: InkWell(
        borderRadius: t.radius.smR,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: t.space.xs, vertical: t.space.xs / 2),
          child: Text(label,
              style: t.text.captionStyle.copyWith(color: t.surface.onBase)),
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
  // Placed by an import and not yet told what it stands for. Distinct from a
  // marker whose device has since vanished: one is a job half done, the other
  // is a thing gone wrong, and they want different words.
  if (isUnbound(marker)) return 'Not bound yet';

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
