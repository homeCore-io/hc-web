import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/widget_registry.dart';
import '../../core/models/dashboard.dart';
import '../../core/models/device_state.dart';
import '../../core/api/assets_api.dart';
import '../../core/providers/assets_provider.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/devices/presentation.dart';
import '../../core/text/humanize.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../devices/device_query.dart';

/// What you can put on a page, drawn from the house you are putting it on.
///
/// Step 6 of `dashboard-authoring-plan.md`, and the point at which the editor
/// stops being a config panel. The palette it replaces was thirteen near
/// identical rows — twelve of them a bare noun, three of them the same idea in
/// three renderers — and it was **byte-identical on a homeCore with no
/// devices**. It could not have told you your house has a living room.
///
/// This one is a view of the device map: *Living room · 31 devices · 6 on*.
/// Picking a room places a card for that room, configured and titled, with no
/// form in between. Two houses see two different libraries, which is the whole
/// argument.
///
/// **No filter chips yet, deliberately.** `/devices` offers Lights 22, Sensors
/// 55, Low battery 2, and they are computed from each device's *facet* — a
/// schema-derived idea. The stored card format has three selection modes,
/// `manual | area | query`, and none can express "every light": a query for
/// `light` matches 17 of this house's 22, because a colour bulb's type is not
/// the word light. Offering a chip labelled 22 that places a card showing 17
/// would be precisely the silent wrongness this arc has been removing. They
/// arrive with a selection mode that can hold them.
class CardLibrary extends ConsumerStatefulWidget {
  const CardLibrary({super.key, required this.onPick});

  /// A ready-to-place card. The page decides where it lands.
  final ValueChanged<DashboardWidgetModel> onPick;

  @override
  ConsumerState<CardLibrary> createState() => _CardLibraryState();
}

class _CardLibraryState extends ConsumerState<CardLibrary> {
  String _query = '';

  /// Explicit, for the reason [CardInspector] records: Flutter web draws no
  /// scrollbar for an unmanaged scroll view, so fifteen rooms above four
  /// collapsed groups looked like the whole library.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // The accordion is gone. Groups that opened and closed were the honest
  // answer while every entry was a full-width row and fifteen rooms pushed
  // everything else into the bottom third of the panel — but a palette whose
  // contents are behind carets is a browser, not a palette. Tiles are three to
  // a row, so the whole catalogue fits without anything being hidden.

  /// Rooms with something in them, most-populated first.
  ///
  /// Derived from the devices themselves rather than from `GET /areas`: the
  /// area catalog is empty on a fresh house, and a room derived from a device
  /// is guaranteed to select at least that device. The same reasoning the
  /// config form's area list already uses.
  List<_Room> _rooms(List<DeviceState> devices) {
    final byArea = <String, List<DeviceState>>{};
    for (final d in devices) {
      if (d.isSystem || d.deviceType == 'scene') continue;
      final area = d.effectiveArea;
      if (area == null || area.isEmpty) continue;
      byArea.putIfAbsent(area, () => []).add(d);
    }
    final rooms = [
      for (final entry in byArea.entries)
        _Room(
          area: entry.key,
          label: humanize(entry.key),
          total: entry.value.length,
          on: entry.value.where(isOn).length,
        ),
    ]..sort((a, b) => b.total.compareTo(a.total));
    return rooms;
  }

  /// The kinds this house has, with their live counts.
  ///
  /// Withheld from this panel until now, and the reason is worth keeping: a
  /// chip saying "Lights 22" had no stored selection that could reproduce 22.
  /// The nearest was `query: "light"`, which matches on the *name* and found 17
  /// of them — a chip labelled 22 that places a card showing 17 is exactly the
  /// silent wrongness this arc has been removing, so the honest answer was to
  /// offer nothing. Core learned `selection_mode: facet`, so the chip can now
  /// mean what it says.
  ///
  /// Counted through the same `facetGroupOf(facetOf(...))` the card filters on,
  /// and past the same exclusions, so the number here is the number you get.
  List<_Kind> _kinds(List<DeviceState> devices) {
    final counts = <DeviceFacetGroup, int>{};
    for (final d in devices) {
      if (d.isSystem || d.deviceType == 'scene') continue;
      final group = facetGroupOf(facetOf(d, d.schema));
      counts[group] = (counts[group] ?? 0) + 1;
    }
    return [
      for (final entry in counts.entries)
        _Kind(group: entry.key, total: entry.value),
    ]..sort((a, b) => b.total.compareTo(a.total));
  }

  DashboardWidgetModel _kindCard(_Kind kind) => _model(
        type: 'device_grid',
        // Named for what was picked, as rooms are. "Device grid" would be
        // naming the renderer at them.
        title: kind.group.label,
        config: {
          'selection_mode': 'facet',
          'facet': kind.group.key,
          'show_offline': true,
          'limit': 12,
        },
      );

  /// Individual devices, but only once you have typed something.
  ///
  /// A hundred and twenty-three rows above the rooms would bury them, and the
  /// room is the answer most of the time. Search is what turns the list from a
  /// wall into an index — the same reason `/devices` opens grouped and not as
  /// one long list.
  List<DeviceState> _matchingDevices(List<DeviceState> devices) {
    final q = _query.toLowerCase();
    return devices
        .where((d) =>
            !d.isSystem &&
            d.deviceType != 'scene' &&
            (d.displayName.toLowerCase().contains(q) ||
                (d.effectiveArea ?? '').toLowerCase().contains(q)))
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  /// One device, as a tile. What "manual" mode was always for, without making
  /// anyone meet the word.
  DashboardWidgetModel _deviceCard(DeviceState d) => _model(
        type: 'device_tile',
        title: d.displayName,
        config: {
          'selection_mode': 'manual',
          'device_ids': [d.id],
          ..._bareCard,
        },
      );

  /// A single device is not a collection, so it does not get a collection's
  /// container.
  ///
  /// John, on the live page: *"look at the single device entity, it's
  /// un-readable, does not mesh/flow with the dashboard and placing several
  /// single devices next to each other would consume lots of unnecessary
  /// space."* The card was the problem, not the tile. A 3×1 cell is 100px; a
  /// title band and two lots of padding took most of it, leaving the control
  /// squeezed into a thin strip — and four of them side by side were four
  /// boxes rather than four controls.
  ///
  /// The tile already carries the device's own name and state, so the band was
  /// saying it twice.
  ///
  /// Written explicitly rather than made the type's default, because the
  /// default has to stay "a card" for every dashboard already saved. Existing
  /// tiles keep their box until someone turns it off, which is now three
  /// switches in the inspector.
  static const _bareCard = {
    'style': {'filled': false, 'bordered': false, 'titled': false},
  };

  bool _matches(String label) =>
      _query.isEmpty || label.toLowerCase().contains(_query.toLowerCase());

  DashboardWidgetModel _entryCard(_Entry e) =>
      _model(type: e.type, title: e.label, config: e.config);

  DashboardWidgetModel _model({
    required String type,
    required String title,
    required Map<String, dynamic> config,
  }) =>
      DashboardWidgetModel(
        id: 'widget_${DateTime.now().microsecondsSinceEpoch}',
        type: type,
        title: title,
        refreshPolicy: DashboardRefreshPolicy.live,
        config: config,
      );

  void _placeRoom(_Room room) => widget.onPick(_roomCard(room));

  DashboardWidgetModel _roomCard(_Room room) => _model(
        type: 'device_grid',
        // Titled with the room, because that is what the user picked. A card
        // called "Device grid" would be naming its renderer at them.
        title: room.label,
        config: {
          'selection_mode': 'area',
          'area_name': room.area,
          'show_offline': true,
          'limit': 12,
        },
      );

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value;
    final rooms = devices == null ? const <_Room>[] : _rooms(devices);
    final shownRooms = rooms.where((r) => _matches(r.label)).toList();
    final kinds = devices == null ? const <_Kind>[] : _kinds(devices);
    final shownKinds = kinds.where((k) => _matches(k.group.label)).toList();

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: t.surface.raised,
        borderRadius: BorderRadius.circular(t.radius.md),
        border: Border.all(color: t.stroke.hairline, width: t.stroke.width),
      ),
      padding: EdgeInsets.all(t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add to this page',
              style: t.text.subtitleStyle.copyWith(
                  color: t.surface.onBase, fontWeight: FontWeight.w600)),
          SizedBox(height: t.space.sm),
          _Search(onChanged: (v) => setState(() => _query = v)),
          SizedBox(height: t.space.md),
          Expanded(
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: ListView(
                controller: _scroll,
                padding: EdgeInsets.only(right: t.space.sm),
                children: [
                  if (devices == null)
                    Text('Loading the house…',
                        style: t.text.captionStyle
                            .copyWith(color: t.surface.onBaseMuted))
                  else ...[
                    if (shownRooms.isNotEmpty)
                      _Section(
                        label: 'Rooms',
                        count: shownRooms.length,
                        children: [
                          for (final room in shownRooms)
                            _Tile(
                              label: room.label,
                              badge: '${room.total}',
                              // The live count comes with it. A room is a real
                              // thing rather than a label because of these two
                              // numbers, and a tile 88 pixels wide can only
                              // carry one of them on its face.
                              hint: '${room.total} devices, ${room.on} on',
                              icon: HcIcons.home,
                              onTap: () => _placeRoom(room),
                              payload: () => _roomCard(room),
                            ),
                        ],
                      )
                    else if (_query.isEmpty && rooms.isEmpty)
                      Padding(
                        padding: EdgeInsets.only(bottom: t.space.md),
                        child: Text(
                          'No rooms yet. Assign devices to rooms in Manage and '
                          'they will show up here.',
                          style: t.text.captionStyle.copyWith(
                              color: t.surface.onBaseMuted, height: 1.4),
                        ),
                      ),
                    // Kinds sit under rooms because the room is the answer more
                    // often: "the kitchen" before "every light". Both are one
                    // drag, and neither asks anyone to meet the word "facet".
                    if (shownKinds.isNotEmpty)
                      _Section(
                        label: 'Kinds',
                        count: shownKinds.length,
                        children: [
                          for (final kind in shownKinds)
                            _Tile(
                              label: kind.group.label,
                              badge: '${kind.total}',
                              icon: kind.icon,
                              onTap: () => widget.onPick(_kindCard(kind)),
                              payload: () => _kindCard(kind),
                            ),
                        ],
                      ),
                  ],
                  // Devices stay rows, not tiles: a device's name is long and
                  // means little without its room, and neither survives a
                  // label two lines deep in an 88-pixel tile.
                  if (devices != null && _query.isNotEmpty)
                    if (_matchingDevices(devices).isNotEmpty) ...[
                      _SectionHead(
                          label: 'Devices found',
                          count: _matchingDevices(devices).length),
                      for (final d in _matchingDevices(devices).take(12))
                        _PlainRow(
                          label: d.displayName,
                          hint: humanize(d.effectiveArea ?? ''),
                          type: 'device_tile',
                          onTap: () => widget.onPick(_deviceCard(d)),
                          payload: () => _deviceCard(d),
                        ),
                      SizedBox(height: t.space.md),
                    ],
                  for (final group in _groups)
                    if (group.entries.any((e) => _matches(e.label)))
                      _Section(
                        label: group.label,
                        count: group.entries
                            .where((e) => _matches(e.label))
                            .length,
                        children: [
                          for (final entry in group.entries)
                            if (_matches(entry.label))
                              _Tile(
                                label: entry.label,
                                hint: entry.hint,
                                icon: WidgetRegistry.lookup(entry.type)?.icon ??
                                    Icons.widgets_outlined,
                                onTap: () => widget.onPick(_entryCard(entry)),
                                payload: () => _entryCard(entry),
                              ),
                        ],
                      ),
                  // Your own pictures, which had no way in at all: placing one
                  // meant making an image element and then typing an address
                  // into it. They are assets of this house, so they belong
                  // beside the rooms rather than behind a field.
                  _AssetSection(query: _query, onPick: widget.onPick),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Everything that is not a room, grouped by what it is for rather than by
  /// which renderer draws it.
  static const _groups = <_Group>[
    _Group('Devices', [
      // Search above finds individual devices; these two are the containers.
      _Entry('Several devices', 'device_grid', 'a card you fill yourself',
          {'selection_mode': 'manual', 'device_ids': <String>[]}),
      _Entry('One device', 'device_tile', 'pick it in the panel', {
        'selection_mode': 'manual',
        'device_ids': <String>[],
        ..._bareCard,
      }),
    ]),
    _Group('The house', [
      _Entry(
          'At a glance', 'house_status_hero', 'lights, climate, security', {}),
      _Entry('Activity', 'event_feed', 'what just happened',
          {'limit': 20, 'group_by': 'none'}),
      _Entry('Modes', 'mode_chips', 'day, night, away', {}),
      _Entry('Scenes', 'scene_row', 'one tap each', {}),
      _Entry('Now playing', 'media_player', 'speakers and TVs',
          {'selection_mode': 'query', 'query': '', 'limit': 4}),
      // **It was in no picker at all.** The whole floor plan feature could only
      // be reached by already having one of these cards on the page, which
      // meant editing the document by hand. Added blank on purpose: an empty
      // one says what to do next — choose a picture, or import a Sweet Home 3D
      // file — and the inspector is where both of those live.
      _Entry('Floor plan', 'floor_plan', 'your home, with its lights on',
          {'fit': 'contain'}),
    ]),
    // Data is its own family, not part of "Other". Three ways to show a
    // number, and which one you want depends on the room rather than on the
    // number: a dial to see at a glance whether something is in range, a big
    // figure to read across a room, a line to see where it has been.
    _Group('Data', [
      _Entry('Gauge', 'gauge', 'one reading against a range',
          {'min': 0, 'max': 100}),
      // The same element with its card taken off and its number turned down —
      // the piece you stack. Three of these at three sizes on the free layer
      // is the instrument cluster that used to need a page of JavaScript, and
      // offering only the full dial would keep that a secret.
      _Entry('Arc', 'gauge', 'a ring you can stack', {
        'min': 0,
        'max': 100,
        'readout': 'none',
        'thickness': 10,
        'color': 'accent',
        ..._bareCard,
      }),
      _Entry('Bar', 'gauge', 'a reading as a line', {
        'min': 0,
        'max': 100,
        'shape': 'bar',
        'readout': 'none',
        'thickness': 10,
        'color': 'accent',
        ..._bareCard,
      }),
      _Entry('Reading', 'device_reading', 'one number, large', {}),
      _Entry('Chart', 'history_chart', 'a value over time',
          {'timeframe_hours': 24}),
      _Entry('Numbers', 'stat_summary', 'counts of things', {
        'metrics': ['devices', 'on', 'offline']
      }),
    ]),
    // Structure and space, rather than anything about the house. These are the
    // elements that let a page stop being a wall of boxes — and the spacer is
    // the one that makes a gap survive a save, which free flow alone does not
    // do for the derived breakpoints.
    _Group('Layout', [
      _Entry('Heading', 'heading', 'a section title',
          {'text': 'Section', 'level': 'section', 'align': 'start'}),
      _Entry('Divider', 'divider', 'a rule between things', {}),
      _Entry('Spacer', 'spacer', 'a gap that stays a gap', {}),
      // "A group is one card with a heading and its own arrangement of
      // devices, which is what a room card already is generalised" — so it is
      // that card, pre-titled, rather than a fourth type that would be
      // `device_grid` wearing a hat. See designer-plan.md §7.
      _Entry('Group', 'device_grid', 'a titled box of devices',
          {'selection_mode': 'manual', 'device_ids': <String>[]}),
    ]),
    _Group('Other', [
      _Entry('Camera', 'camera_video', 'a live view',
          {'source_type': 'image_refresh'}),
      _Entry('Web page', 'web_embed', 'anything with a URL',
          {'sandbox_profile': 'readonly_embed'}),
      _Entry(
          'Image', 'image', 'a picture, scaled to the card', {'fit': 'cover'}),
      _Entry('Note', 'markdown', 'text you write',
          {'markdown': '# Note\nWrite something here.'}),
      // Placed blank on purpose, like the floor plan: an empty code element
      // renders its own starter, which says what the API is at the moment
      // somebody wants to know. Granted nothing until it is told otherwise —
      // the device selection is the permission, so the safe default is none.
      // Between the gauges we draw and the code you write: bring the artwork,
      // wire it up in a list. Granted nothing until told otherwise, like the
      // code element it shares a sandbox with.
      _Entry('Drawing', 'svg', 'your svg, wired to the house',
          {'selection_mode': 'manual', 'device_ids': <String>[]}),
      _Entry('Code', 'code', 'html, svg and script you write',
          {'selection_mode': 'manual', 'device_ids': <String>[]}),
    ]),
  ];
}

class _Group {
  const _Group(this.label, this.entries);
  final String label;
  final List<_Entry> entries;
}

class _Entry {
  const _Entry(this.label, this.type, this.hint, this.config);
  final String label;
  final String type;
  final String hint;
  final Map<String, dynamic> config;
}

class _Kind {
  const _Kind({required this.group, required this.total});
  final DeviceFacetGroup group;
  final int total;

  /// Borrowed from a facet in the group, so the icon in the library is the one
  /// the devices themselves wear.
  IconData get icon => switch (group) {
        DeviceFacetGroup.lights => DeviceFacet.light.icon,
        DeviceFacetGroup.outlets => DeviceFacet.outlet.icon,
        DeviceFacetGroup.switches => DeviceFacet.switch_.icon,
        DeviceFacetGroup.covers => DeviceFacet.cover.icon,
        DeviceFacetGroup.locks => DeviceFacet.lock.icon,
        DeviceFacetGroup.doorsWindows => DeviceFacet.door.icon,
        DeviceFacetGroup.garage => DeviceFacet.garage.icon,
        DeviceFacetGroup.motion => DeviceFacet.motion.icon,
        DeviceFacetGroup.environment => DeviceFacet.temperature.icon,
        DeviceFacetGroup.power => DeviceFacet.power.icon,
        DeviceFacetGroup.safety => DeviceFacet.smoke.icon,
        DeviceFacetGroup.climate => DeviceFacet.climate.icon,
        DeviceFacetGroup.fans => DeviceFacet.fan.icon,
        DeviceFacetGroup.media => DeviceFacet.mediaPlayer.icon,
        DeviceFacetGroup.scenes => DeviceFacet.scene.icon,
        DeviceFacetGroup.buttons => DeviceFacet.button.icon,
        DeviceFacetGroup.timers => DeviceFacet.timer.icon,
        DeviceFacetGroup.sirens => DeviceFacet.siren.icon,
        DeviceFacetGroup.sensors => DeviceFacet.sensor.icon,
        DeviceFacetGroup.other => DeviceFacet.unknown.icon,
      };
}

class _Room {
  const _Room(
      {required this.area,
      required this.label,
      required this.total,
      required this.on});
  final String area;
  final String label;
  final int total;
  final int on;
}

class _Search extends StatelessWidget {
  const _Search({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: BorderRadius.circular(t.radius.sm),
        border: Border.all(color: t.stroke.hairline, width: t.stroke.width),
      ),
      padding: EdgeInsets.symmetric(horizontal: t.space.sm),
      child: TextField(
        onChanged: onChanged,
        style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: 'Search rooms and cards',
          hintStyle:
              t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted),
        ),
      ),
    );
  }
}

/// A section of the palette: a quiet heading, then its tiles.
///
/// The count stays, because it is what tells you a section is complete without
/// counting the tiles yourself — the same reason the old closed headers carried
/// one.
class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.count,
    required this.children,
  });

  final String label;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHead(label: label, count: count),
        Wrap(
          spacing: t.space.xs,
          runSpacing: t.space.xs,
          children: children,
        ),
        SizedBox(height: t.space.md),
      ],
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.xs, top: t.space.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(label.toUpperCase(),
                style: t.text.overlineStyle
                    .copyWith(color: t.surface.onBaseMuted)),
          ),
          Text('$count',
              style: t.text.captionStyle.copyWith(
                  color: t.surface.onBaseMuted,
                  fontFeatures: t.numericFontFeatures)),
        ],
      ),
    );
  }
}

/// One thing you can put on the page.
///
/// A tile rather than a row, and that is the whole change John asked for: a
/// full-width row with a name and a sentence of explanation is a catalogue
/// entry in a content browser, and forty of them are a list you read. Three to
/// a row with the icon carrying the meaning is a palette you scan — the
/// explanation moves to the tooltip, where it is available and not in the way.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.payload,
    this.hint,
    this.badge,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final DashboardWidgetModel Function() payload;
  final String? hint;

  /// A count — how many devices a room holds, how many a kind matches. The
  /// number the card will show, so the tile is a promise rather than a label.
  final String? badge;

  static const double width = 88;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Tooltip(
      // The explanation the old rows carried under every name. Available on
      // the tile you are pointing at, rather than repeated forty times down a
      // panel nobody can scan.
      message: hint == null ? label : '$label — $hint',
      waitDuration: const Duration(milliseconds: 500),
      child: _DragRow(
        payload: payload,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(t.radius.sm),
          child: Container(
            width: width,
            height: 72,
            padding: EdgeInsets.all(t.space.xs),
            decoration: BoxDecoration(
              color: t.surface.sunken,
              borderRadius: BorderRadius.circular(t.radius.sm),
              border:
                  Border.all(color: t.stroke.hairline, width: t.stroke.width),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, size: 18, color: t.surface.onBaseMuted),
                    if (badge case final n?)
                      Positioned(
                        right: -14,
                        top: -2,
                        child: Text(n,
                            style: t.text.captionStyle.copyWith(
                              color: t.surface.onBaseMuted,
                              fontFeatures: t.numericFontFeatures,
                            )),
                      ),
                  ],
                ),
                SizedBox(height: t.space.xs),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.captionStyle.copyWith(color: t.surface.onBase),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DragRow extends StatelessWidget {
  const _DragRow(
      {required this.payload, required this.label, required this.child});

  final DashboardWidgetModel Function() payload;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return MouseRegion(
      // The only honest way to say "this is draggable" without adding a grip
      // to every row: the cursor changes over something you can pick up.
      cursor: SystemMouseCursors.grab,
      child: Draggable<Object>(
        data: payload(),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: t.space.sm, vertical: t.space.xs),
            decoration: BoxDecoration(
              color: t.surface.overlay,
              borderRadius: BorderRadius.circular(t.radius.sm),
              border: Border.all(color: t.accent.active, width: t.stroke.width),
            ),
            child: Text(label,
                style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase)),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: child),
        child: child,
      ),
    );
  }
}

/// An element you can place: what it is, what it does, and how big it lands.
///
/// Three deliberate choices, each replacing something that was wrong.
///
/// **The icon is the registry's own.** The palette this grew out of showed one
/// per card and the first version of this panel dropped them, which turned a
/// library into a column of prose.
///
/// **The size, not a truncated hint.** At 260px the right-hand hint ellipsised
/// on nearly every row — "a card you fill y…", "lights, climate, s…" — which is
/// the shape of text that is present but unreadable. The cell size is short,
/// never truncates, and is the one fact about an element you cannot guess and
/// would otherwise learn by dropping it.
///
/// **The description gets its own line.** It is what tells you Numbers from
/// Chart, so it is worth the height rather than worth abbreviating.
class _PlainRow extends StatelessWidget {
  const _PlainRow(
      {required this.label,
      required this.hint,
      required this.type,
      required this.onTap,
      required this.payload});

  final String label;
  final String hint;
  final String type;
  final VoidCallback onTap;
  final DashboardWidgetModel Function() payload;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final d = WidgetRegistry.lookup(type);
    final size = d == null
        ? null
        : '${d.sizeHint.recommendedW}×${d.sizeHint.recommendedH}';

    return _DragRow(
      payload: payload,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.radius.sm),
        child: Padding(
          padding: EdgeInsets.symmetric(
              vertical: t.space.xs, horizontal: t.space.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(d?.icon ?? Icons.widgets_outlined,
                    size: 15, color: t.surface.onBaseMuted),
              ),
              SizedBox(width: t.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: t.text.bodySmallStyle
                            .copyWith(color: t.surface.onBase)),
                    Text(hint,
                        style: t.text.captionStyle
                            .copyWith(color: t.surface.onBaseMuted)),
                  ],
                ),
              ),
              if (size != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 1),
                  child: Text(size,
                      style: t.text.captionStyle.copyWith(
                          color: t.surface.onBaseMuted,
                          fontFeatures: t.numericFontFeatures)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pictures this house has, as things you can place.
///
/// **They had no way into a page at all.** Uploading worked, and four config
/// fields could pick one, but placing a picture meant making an image element
/// first and then finding the address to put in it — the file existed and the
/// designer could not show you it. A page is designed *around* its pictures at
/// least as often as the other way round.
///
/// Clicking one places an image element already pointing at it. The listing is
/// authenticated, which is why it is only asked for here rather than kept warm
/// somewhere: an asset id is unguessable on purpose, and enumerating them is
/// the one call that would undo that.
class _AssetSection extends ConsumerWidget {
  const _AssetSection({required this.query, required this.onPick});

  final String query;
  final ValueChanged<DashboardWidgetModel> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final async = ref.watch(assetListProvider);

    final pictures = [
      for (final a in async.value ?? const <AssetRef>[])
        if (a.contentType.startsWith('image/') &&
            (query.isEmpty ||
                a.name.toLowerCase().contains(query.toLowerCase())))
          a,
    ];

    // **The section is always here.** Returning nothing while the listing was
    // in flight — and, as written first, while it had *failed* — made the whole
    // section appear not to exist, and there is no way to tell "still asking"
    // from "not built yet" by looking at an empty stretch of panel. Which is
    // exactly what happened: it went missing on the live house and the panel
    // had nothing to say about why.
    //
    // A search that matches no picture is the one case that hides it, because
    // then the empty section is just noise beside the other sections the search
    // has already emptied.
    if (query.isNotEmpty && pictures.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHead(label: 'Pictures', count: pictures.length),
        if (async.hasError)
          Text(
            'Could not list your files: ${async.error}',
            style: t.text.captionStyle
                .copyWith(color: t.accent.danger, height: 1.4),
          )
        else if (async.isLoading)
          Text('Looking…',
              style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted))
        else if (pictures.isEmpty)
          Text(
            'Nothing uploaded yet. Files you add in Manage → Files land here, '
            'ready to place.',
            style: t.text.captionStyle
                .copyWith(color: t.surface.onBaseMuted, height: 1.4),
          )
        else
          Wrap(
            spacing: t.space.xs,
            runSpacing: t.space.xs,
            children: [
              for (final asset in pictures)
                _AssetTile(asset: asset, onPick: onPick),
            ],
          ),
        SizedBox(height: t.space.md),
      ],
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.asset, required this.onPick});

  final AssetRef asset;
  final ValueChanged<DashboardWidgetModel> onPick;

  DashboardWidgetModel _card() => DashboardWidgetModel(
        id: 'widget_${DateTime.now().microsecondsSinceEpoch}',
        // Named for the file, so the layer tree says which picture rather than
        // "Image" four times.
        title: asset.name,
        type: 'image',
        refreshPolicy: DashboardRefreshPolicy.passive,
        config: {'url': asset.url, 'fit': 'cover'},
      );

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Tooltip(
      message: asset.name,
      waitDuration: const Duration(milliseconds: 500),
      child: _DragRow(
        payload: _card,
        label: asset.name,
        child: InkWell(
          onTap: () => onPick(_card()),
          borderRadius: BorderRadius.circular(t.radius.sm),
          child: Container(
            width: _Tile.width,
            height: 72,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: t.surface.sunken,
              borderRadius: BorderRadius.circular(t.radius.sm),
              border:
                  Border.all(color: t.stroke.hairline, width: t.stroke.width),
            ),
            // The picture itself is the label. A filename under a thumbnail
            // would halve the thumbnail to repeat what the tooltip says.
            child: Image.network(
              asset.url,
              fit: BoxFit.cover,
              errorBuilder: (context, _, __) => Center(
                child: Icon(Icons.broken_image_outlined,
                    size: 18, color: t.surface.onBaseMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
