import '../../core/models/dashboard.dart';

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

  /// Reads the arrangement out of a dashboard, ignoring anything else on it.
  static HomeArrangement fromDashboard(DashboardDefinition? d) {
    if (d == null) return const HomeArrangement();

    // Placement order is the source of truth for sequence; a widget with no
    // placement still counts, it just sorts last.
    final desktop = d.layouts
        .where((l) => l.breakpoint == DashboardBreakpoint.desktop)
        .firstOrNull;
    final yOf = <String, int>{
      for (final p in desktop?.placements ?? const []) p.widgetId: p.y,
    };

    final rooms = d.widgets
        .where((w) => w.id.startsWith(_kRoomPrefix))
        .where((w) => w.config[_kAreaKey] is String)
        .toList()
      ..sort((a, b) => (yOf[a.id] ?? 1 << 20).compareTo(yOf[b.id] ?? 1 << 20));

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
      for (final area in ordered)
        DashboardWidgetModel(
          id: '$_kRoomPrefix$area',
          type: 'device_grid',
          title: area.replaceAll('_', ' '),
          subtitle: null,
          refreshPolicy: DashboardRefreshPolicy.live,
          config: {
            _kAreaKey: area,
            if (hidden.contains(area)) _kHiddenKey: true,
          },
        ),
    ];

    final placements = <DashboardWidgetPlacement>[
      // Anything that is not a room keeps whatever placement it had.
      for (final l in d.layouts)
        if (l.breakpoint == DashboardBreakpoint.desktop)
          ...l.placements.where((p) => keepIds.contains(p.widgetId)),
      for (var i = 0; i < roomWidgets.length; i++)
        DashboardWidgetPlacement(
          widgetId: roomWidgets[i].id,
          x: 0,
          y: i,
          w: 12,
          h: 1,
        ),
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
