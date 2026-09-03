import 'package:flutter/material.dart';

import '../../core/dashboard/card_style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/widget_registry.dart';
import '../../core/models/dashboard.dart';
import '../../design/tokens.dart';

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

  /// Every widget type the catalogue offers.
  ///
  /// Public so a test can ask. `WidgetRegistry` says what this app can *draw*
  /// and this list says what you can *place*, and for seven elements those two
  /// answers disagreed in silence for a whole release: the switch, the slider,
  /// the icon, the stepper, the colour wheel, the warmth bar and the scene
  /// button were all registered, validated, drawable and unreachable. The page
  /// looked identical to the one before them because it was.
  ///
  /// Exactly the drift the dashboard vocabulary exists to prevent between core
  /// and this client, living inside this client between two hand-kept lists.
  static Set<String> get offeredTypes => {
        for (final group in _CardLibraryState._groups)
          for (final entry in group.entries) entry.type,
      };
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
        // Undecorated, like everything else made here — see
        // `CardStyle.undecorated`. The catalogue's own preview still shows the
        // card look, because that is what the entry *is*; what arrives on the
        // page is the content, and the frame is a thing you ask for.
        config: CardStyle.undecorated.toConfig(config),
      );

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

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
                  // **Rooms, kinds and devices are gone from here.** They
                  // live in the Devices panel, where they are FILTERS over a
                  // list of devices rather than tiles you drop. John, twice:
                  // "it should be a shortcut for selecting devices in the room
                  // or of those kinds not a what it is", and then "it's not
                  // intuitive to drop a blob on the page and have to remove
                  // items". A tile you can drag reads as a thing; a chip that
                  // narrows a list does not, and only one of those is what a
                  // room actually is.
                  //
                  // Pictures went to the Assets panel for the same reason: this
                  // is a catalogue of card and element TYPES, and everything
                  // that is a fact about the HOUSE belongs in the panel.
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Everything that is not a room, grouped by **what the thing does to the
  /// house** rather than by which renderer draws it.
  ///
  /// The groups are the mockup's, and the order is its argument. A page is made
  /// of marks, of instruments that read, of controls that set, and of things
  /// that hold other things — and until now the catalogue had no name for the
  /// third, because the app had nothing to put in it. "Set something" being a
  /// heading you can see is the point.
  ///
  /// The cards that were here before are unchanged and still here. They are
  /// simply no longer the only thing you can place.
  static const _groups = <_Group>[
    // ── Draw ────────────────────────────────────────────────────────────────
    // Marks. A rectangle is a rectangle whatever the house is doing. Most of
    // these are faster from the tool rail — drag and it exists at the size you
    // dragged — and they are here too because a catalogue that omitted them
    // would be lying about what you can place.
    _Group('Draw', [
      _Entry('Rectangle', 'shape', 'drag one out with R',
          {'shape': 'rectangle', 'fill': 'accent', 'opacity': 20}),
      _Entry('Ellipse', 'shape', 'or O for a circle',
          {'shape': 'circle', 'fill': 'accent', 'opacity': 20}),
      _Entry('Line', 'line', 'a rule at an angle', {'ink': 'muted'}),
      _Entry('Text', 'text', 'words, at any size',
          {'text': 'Text', 'size': 'title', 'align': 'start'}),
      _Entry('Heading', 'heading', 'a section title',
          {'text': 'Section', 'level': 'section', 'align': 'start'}),
      _Entry('Divider', 'divider', 'a rule between things', {}),
      _Entry('Spacer', 'spacer', 'a gap that stays a gap', {}),
      _Entry(
          'Image', 'image', 'a picture, scaled to the card', {'fit': 'cover'}),
      // **It was in no picker at all.** The whole floor plan feature could only
      // be reached by already having one of these cards on the page, which
      // meant editing the document by hand. Added blank on purpose: an empty
      // one says what to do next — choose a picture, or import a Sweet Home 3D
      // file — and the inspector is where both of those live.
      _Entry('Floor plan', 'floor_plan', 'your home, with its lights on',
          {'fit': 'contain'}),
    ]),
    // ── Show a reading ──────────────────────────────────────────────────────
    // Instruments. Which one you want depends on the room rather than on the
    // number: a dial to see at a glance whether something is in range, a big
    // figure to read across a room, a line to see where it has been.
    _Group('Show a reading', [
      _Entry('Icon', 'icon', 'a device as its own symbol', {}),
      // **A state dot is not a new element.** It is a circle whose fill follows
      // a reading, and the binding arc made exactly that expressible: `fill` is
      // a bindable property of `shape`, so this is the shape element with a
      // starting config and nothing more.
      //
      // Adding a `state_dot` type would have been a second way to say one
      // thing — a type to declare in core, a renderer to keep in step, and a
      // page able to express the same dot two ways with different bugs. The
      // mockup lists it beside the others because that is where it belongs in
      // a catalogue, not because it needs its own code.
      //
      // Placed unbound: which device it follows is the next thing you choose,
      // and the Data section is where you say so.
      _Entry('State dot', 'shape', 'a circle that follows a device', {
        'shape': 'circle',
        'fill': 'muted',
        ..._bareCard,
      }),
      _Entry('Gauge', 'gauge', 'one reading against a range',
          {'min': 0, 'max': 100}),
      // The same element with its card taken off and its number turned down —
      // the piece you stack.
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
      // A sparkline is a chart with its box taken off — the piece you put
      // beside a number rather than the panel you hang on a wall. The same
      // element, as the arc and the bar are the same gauge.
      _Entry('Sparkline', 'history_chart', 'a line to tuck beside a value',
          {'timeframe_hours': 6, ..._bareCard}),
      _Entry('Chart', 'history_chart', 'a value over time',
          {'timeframe_hours': 24}),
      _Entry('Numbers', 'stat_summary', 'counts of things', {
        'metrics': ['devices', 'on', 'offline']
      }),
      _Entry('Camera', 'camera_video', 'a live view',
          {'source_type': 'image_refresh'}),
    ]),
    // ── Set something ───────────────────────────────────────────────────────
    // The class the catalogue had no heading for, because the app had nothing
    // to put in it. Each of these reads a device AND writes to it, and each
    // refuses to write unless the plugin registered the attribute — an inferred
    // `writable` is this app's opinion, and a control built on one looks right,
    // sends, and changes nothing. See `attribute_policy.dart`.
    _Group('Set something', [
      _Entry('Switch', 'toggle', 'on and off', {'attribute': 'on'}),
      _Entry('Slider', 'slider', 'a number you drag', {}),
      // The control for a number the plugin gave no range for, which a slider
      // cannot show at all.
      _Entry('Stepper', 'stepper', 'up a bit, down a bit', {}),
      _Entry('Colour wheel', 'colour_wheel', 'hue and saturation',
          {'attribute': 'color_xy'}),
      _Entry('Warmth', 'warmth', 'warm to cool white',
          {'attribute': 'color_temp', 'axis': 'vertical'}),
      // Scenes activate directly, like a device — no rule stands between the
      // button and the house.
      _Entry('Scene button', 'scene_button', 'runs one scene', {}),
      // A setpoint against its reading, which two numbers side by side cannot
      // say: whether the house is working, which way, and how far to go.
      _Entry('Thermostat', 'thermostat', 'a dial, not two numbers', {}),
      // The buttons a keypad publishes, pressable. The repeater accepts a
      // virtual press on every one of them.
      _Entry('Keypad', 'keypad', 'a keypad’s real buttons', {}),
    ]),
    // ── The house ───────────────────────────────────────────────────────────
    _Group('The house', [
      _Entry(
          'At a glance', 'house_status_hero', 'lights, climate, security', {}),
      _Entry('Activity', 'event_feed', 'what just happened',
          {'limit': 20, 'group_by': 'none'}),
      _Entry('Modes', 'mode_chips', 'day, night, away', {}),
      _Entry('Scenes', 'scene_row', 'one tap each', {}),
      _Entry('Now playing', 'media_player', 'speakers and TVs',
          {'selection_mode': 'query', 'query': '', 'limit': 4}),
      // Reachable from nothing until now — the one element that keeps up with
      // the house on its own, and you could not put it on a page.
      _Entry('Rooms', 'rooms', 'every device, by room',
          {'rooms_mode': 'all', 'hide_empty': true}),
      // The whole house as one shape. A row of room cards says there are
      // fifteen rooms; this says which of them the house is actually in.
      _Entry('Room field', 'room_field', 'every room, sized by what is in it',
          {'gap': 4}),
      _Entry('Other pages', 'dashboard_link', 'links to your dashboards',
          {'dashboard_ids': <String>[]}),
    ]),
    // ── Hold other things ───────────────────────────────────────────────────
    _Group('Hold other things', [
      // Search above finds individual devices; these two are the containers.
      _Entry('Several devices', 'device_grid', 'a card you fill yourself',
          {'selection_mode': 'manual', 'device_ids': <String>[]}),
      _Entry('One device', 'device_tile', 'pick it in the panel', {
        'selection_mode': 'manual',
        'device_ids': <String>[],
        ..._bareCard,
      }),
      _Entry('A list of devices', 'device_list', 'a row each, with its state',
          {'selection_mode': 'manual', 'device_ids': <String>[]}),
      // "A group is one card with a heading and its own arrangement of
      // devices, which is what a room card already is generalised" — so it is
      // that card, pre-titled, rather than a fourth type that would be
      // `device_grid` wearing a hat. See designer-plan.md §7.
      _Entry('Group', 'device_grid', 'a titled box of devices',
          {'selection_mode': 'manual', 'device_ids': <String>[]}),
      _Entry('Note', 'markdown', 'text you write',
          {'markdown': '# Note\nWrite something here.'}),
      _Entry('Web page', 'web_embed', 'anything with a URL',
          {'sandbox_profile': 'readonly_embed'}),
      // Between the gauges we draw and the code you write: bring the artwork,
      // wire it up in a list. Granted nothing until told otherwise, like the
      // code element it shares a sandbox with.
      _Entry('Drawing', 'svg', 'your svg, wired to the house',
          {'selection_mode': 'manual', 'device_ids': <String>[]}),
      // Placed blank on purpose, like the floor plan: an empty code element
      // renders its own starter, which says what the API is at the moment
      // somebody wants to know. Granted nothing until it is told otherwise —
      // the device selection is the permission, so the safe default is none.
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
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final DashboardWidgetModel Function() payload;
  final String? hint;

  /// A count — how many devices a room holds, how many a kind matches. The
  /// number the card will show, so the tile is a promise rather than a label.

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
                Icon(icon, size: 18, color: t.surface.onBaseMuted),
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
