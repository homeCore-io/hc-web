import '../../core/models/dashboard.dart';
import '../../core/text/humanize.dart';

/// How the house is laid out — which rooms, in what order, and which are hidden.
///
/// This is pure logic with no widgets and no providers, so the one rule that
/// actually matters can be tested without a browser: **a room you have never
/// arranged must still appear.** Get that wrong and installing a new device in a
/// new room makes it silently invisible, and the user has no way to know the app
/// is hiding it. Every layout system that persists an explicit order has this
/// bug waiting in it.
class HomeArrangement {
  const HomeArrangement({this.order = const [], this.hidden = const {}});

  /// Room keys, in the order the user put them. Rooms absent from this list are
  /// NOT unknown-and-therefore-hidden — they are simply new. See [apply].
  final List<String> order;

  /// Rooms the user explicitly hid. Only an explicit act hides a room.
  final Set<String> hidden;

  bool get isEmpty => order.isEmpty && hidden.isEmpty;

  /// The bucket for devices with no area. It is not a room, so it never leads.
  static const kNoRoom = 'No room';

  /// Orders [rooms] by the saved arrangement, appending anything it has never
  /// seen.
  ///
  /// Unknown rooms go to the END rather than being dropped: a room the
  /// arrangement does not mention is new, not deleted.
  List<String> apply(Iterable<String> rooms) =>
      all(rooms).where((r) => !hidden.contains(r)).toList();

  /// Every room, including hidden ones — what the Arrange editor works on.
  List<String> all(Iterable<String> rooms) {
    final present = rooms.toSet();
    final known = order.where(present.contains);
    final novel = present.where((r) => !order.contains(r)).toList()
      ..sort(_byName);
    return [...known, ...novel];
  }

  /// "No room" is a dumping ground, not a room, and it sorts LAST.
  ///
  /// Plain alphabetical put it first — uppercase 'N' sorts before lowercase 'a'
  /// in ASCII — so the 33 devices nobody has assigned an area to were the first
  /// thing you saw when you opened your house, above the attic and the bathroom.
  /// A default order should lead with the rooms you actually live in.
  static int _byName(String a, String b) {
    if (a == kNoRoom) return b == kNoRoom ? 0 : 1;
    if (b == kNoRoom) return -1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  HomeArrangement copyWith({List<String>? order, Set<String>? hidden}) =>
      HomeArrangement(
        order: order ?? this.order,
        hidden: hidden ?? this.hidden,
      );

  // -- persistence ----------------------------------------------------------
  //
  // Stored in the default dashboard as one `device_grid` widget per room, its
  // area in the config and its position given by the layout's placements. That
  // reuses the dashboard document core already has rather than inventing a
  // second place to keep user layout — and it means a room card sits in the same
  // registry a camera card or a plugin card does, which is what makes the
  // security wall the same surface as the house.

  static const _kRoomPrefix = 'room_';
  static const _kAreaKey = 'area';
  static const _kHiddenKey = 'hidden';
  static const _kOrderKey = 'order';

  /// A private marker type, NOT `device_grid`. Two reasons the old type was a
  /// bug: core validates `device_grid` and rejects one without a
  /// `selection_mode` (so every arrange-save 400'd), and a real widget type gets
  /// a grid placement — which would draw these order-markers as cards on top of
  /// the very dashboard they are stored on. Core accepts unknown types
  /// untouched, and a widget with no placement is never drawn.
  static const _kMarkerType = 'home_arrangement';

  static int _orderOf(DashboardWidgetModel w) =>
      (w.config[_kOrderKey] as num?)?.toInt() ?? (1 << 20);

  static String _title(String area) {
    final h = humanize(area);
    return h.isNotEmpty ? h : (area.isNotEmpty ? area : 'Area');
  }

  /// Reads the arrangement out of a dashboard, ignoring anything else on it.
  static HomeArrangement fromDashboard(DashboardDefinition? d) {
    if (d == null) return const HomeArrangement();

    // Sequence is carried in each marker's `order`, not a placement — the
    // markers are deliberately unplaced so they never render.
    final rooms = d.widgets
        .where((w) => w.id.startsWith(_kRoomPrefix))
        .where((w) => w.config[_kAreaKey] is String)
        .toList()
      ..sort((a, b) => _orderOf(a).compareTo(_orderOf(b)));

    return HomeArrangement(
      order: [for (final w in rooms) w.config[_kAreaKey] as String],
      hidden: {
        for (final w in rooms)
          if (w.config[_kHiddenKey] == true) w.config[_kAreaKey] as String,
      },
    );
  }

  /// Writes this arrangement back onto [d], leaving every other widget it
  /// carries untouched — a camera card someone added does not get eaten by a
  /// room reorder.
  DashboardDefinition toDashboard(DashboardDefinition d, List<String> rooms) {
    final keep =
        d.widgets.where((w) => !w.id.startsWith(_kRoomPrefix)).toList();
    final keepIds = keep.map((w) => w.id).toSet();

    final ordered = all(rooms);
    final roomWidgets = [
      for (var i = 0; i < ordered.length; i++)
        DashboardWidgetModel(
          id: '$_kRoomPrefix${ordered[i]}',
          type: _kMarkerType,
          title: _title(ordered[i]),
          subtitle: null,
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {
            _kAreaKey: ordered[i],
            _kOrderKey: i,
            if (hidden.contains(ordered[i])) _kHiddenKey: true,
          },
        ),
    ];

    // Markers carry NO placement — they are order/hidden state, not cards to
    // draw. Only the dashboard's real widgets keep their placements.
    final placements = <DashboardWidgetPlacement>[
      for (final l in d.layouts)
        if (l.breakpoint == DashboardBreakpoint.desktop)
          ...l.placements.where((p) => keepIds.contains(p.widgetId)),
    ];

    final layouts = [
      for (final l in d.layouts)
        if (l.breakpoint == DashboardBreakpoint.desktop)
          DashboardLayout(
            breakpoint: l.breakpoint,
            columns: l.columns,
            rowHeight: l.rowHeight,
            gap: l.gap,
            placements: placements,
          )
        else
          l,
    ];

    return d.copyWith(
      widgets: [...keep, ...roomWidgets],
      layouts: layouts.isEmpty
          ? [
              DashboardLayout(
                breakpoint: DashboardBreakpoint.desktop,
                columns: 12,
                rowHeight: 120,
                gap: 12,
                placements: placements,
              )
            ]
          : layouts,
    );
  }
}
