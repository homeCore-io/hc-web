/// What a blank page offers instead of an empty grid.
///
/// The first thing asked for in this arc, and deliberately the last thing
/// built: a starting point is only worth offering once there is something to
/// start *into*. On a page that could only ever be a mosaic of cells there was
/// exactly one shape a template could have, so "add a widget to get started"
/// was not a poor answer — it was the whole truth. With a canvas underneath it
/// is not, and the choice becomes real.
///
/// **Three, and one of them is blank.** A page nobody chose a shape for is a
/// legitimate thing to want, and burying it would make the other two feel like
/// something being done to you. The other two are the two questions a home
/// dashboard is actually the answer to: *show me this room*, and *fill that
/// screen on the wall*.
///
/// **Nothing here invents a design.** A room start makes one card that lists
/// the room; a wall start makes an empty canvas of the right size and shape. A
/// template that arranged a dozen cards would be a page you had to dismantle
/// before you could make it yours, and dismantling is worse work than
/// assembling.
library;

import 'grid_engine.dart';

/// A card a starting point puts on the page.
///
/// A recipe rather than a widget: ids, placement and the draft belong to the
/// screen, and a pure list of intentions is a thing a test can read.
class StartCard {
  const StartCard({
    required this.type,
    required this.title,
    required this.config,
    required this.w,
    required this.h,
  });

  final String type;
  final String title;
  final Map<String, dynamic> config;
  final int w;
  final int h;
}

enum PageStartKind {
  /// The grid, empty. What every page has been until now.
  blank,

  /// One room's devices.
  room,

  /// A fixed canvas the size of a screen, with nothing on it.
  wall,
}

/// The cards [kind] puts on a new page.
///
/// [room] is the area name for [PageStartKind.room], and ignored otherwise.
/// An empty or missing room gives nothing, because a card selecting on no area
/// at all shows the whole house — which is not what "this room" means and is a
/// surprising page to be handed.
List<StartCard> startCards(PageStartKind kind, {String? room, String? label}) {
  switch (kind) {
    case PageStartKind.blank:
    case PageStartKind.wall:
      return const [];
    case PageStartKind.room:
      final area = room?.trim() ?? '';
      if (area.isEmpty) return const [];
      return [
        StartCard(
          type: 'device_grid',
          // The room as a person writes it, not as the house stores it: areas
          // arrive normalised (`living_room`), and a card titled that reads
          // like a database row.
          title: (label?.trim().isNotEmpty ?? false) ? label!.trim() : area,
          // Selected by area rather than by listing the devices: a room start
          // should keep meaning the room after somebody plugs in a new lamp.
          config: {'selection_mode': 'area', 'area_name': area},
          w: 12,
          h: 4,
        ),
      ];
  }
}

/// The canvas [kind] wants, or null to leave the page a plain grid.
///
/// 1080p because it is the screen most people have on a wall, and because a
/// starting point that asks a question before it starts is not a starting
/// point — the size is a control in the inspector and changing it moves
/// nothing.
DashboardFrame? startFrame(PageStartKind kind) => switch (kind) {
      PageStartKind.blank || PageStartKind.room => null,
      PageStartKind.wall => const DashboardFrame(
          width: 1920,
          height: 1080,
          fit: DashboardFrameFit.fixed,
        ),
    };

/// Whether [kind] needs a room chosen before it can do anything.
bool startNeedsRoom(PageStartKind kind) => kind == PageStartKind.room;

/// One room on offer: the area as the house stores it, as a person writes it,
/// and how many devices are in it.
typedef StartRoom = ({String area, String label, int count});

/// The rooms on offer, commonest first.
///
/// Sorted by size because the room somebody wants a page for is far more often
/// the busy one than the one that sorts first alphabetically — and because a
/// room with one device in it makes a thin page.
///
/// [areas] must arrive already filtered to the devices a card would actually
/// show. A count that includes what the card then hides is a promise of a
/// fuller room than you get — and scenes alone were the difference between
/// "Living Room 31" here and "Living Room 18" in the library beside it.
///
/// [name] turns a stored area into a written one. Absent, the raw value is
/// used, which is right for a test and wrong for a person.
List<StartRoom> roomsBySize(
  Iterable<String?> areas, {
  String Function(String)? name,
}) {
  final counts = <String, int>{};
  for (final area in areas) {
    final raw = area?.trim() ?? '';
    if (raw.isEmpty) continue;
    counts[raw] = (counts[raw] ?? 0) + 1;
  }
  final out = [
    for (final e in counts.entries)
      (area: e.key, label: name?.call(e.key) ?? e.key, count: e.value),
  ];
  out.sort((a, b) {
    final size = b.count.compareTo(a.count);
    // Alphabetical within a size, so the list does not reshuffle every time a
    // device goes offline and comes back.
    return size != 0
        ? size
        : a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return out;
}
