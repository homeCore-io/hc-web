/// One element that produces *many* sections — a section per room.
///
/// **This is the thing the designer could not express.** Every element until
/// now is one you place: you choose it, you put it somewhere, and it draws what
/// you told it to. That is why a designed page cannot look like the house's own
/// home page. The home page has a section per room and fills each from the
/// house, so installing a light in the kitchen makes it appear; a designed page
/// would need a card per room, placed by hand, and would be wrong the moment a
/// room changed.
///
/// The difference is repetition. This element takes a *query* — which rooms,
/// and what counts as being in one — and yields a section for each answer. Add
/// a room and a section arrives. Add a device and it lands in its room. Nobody
/// touches the page.
///
/// Pure on purpose: which rooms, in what order, holding what, is decided here
/// and tested against a list of devices. What a section *looks* like is the
/// card's problem, and it reuses the tiles the rest of the app already draws.
library;

import '../models/device_state.dart';

/// A room, and what is in it.
typedef RoomSection = ({
  /// The area as stored — normalised, the way core keeps it.
  String area,

  /// What to put on the heading. The area's own spelling where the house has
  /// one, so a page says "Living Room" rather than `living_room`.
  String label,
  List<DeviceState> devices,
});

/// Which rooms this element is asking for.
enum RoomChoice {
  /// Every room that has something in it. The answer that follows the house:
  /// this is what makes a page keep up with a new room without being edited.
  all,

  /// Only the rooms named. For a page about the upstairs.
  named,
}

RoomChoice roomChoiceFrom(Object? raw) =>
    raw == 'named' ? RoomChoice.named : RoomChoice.all;

/// Builds the sections.
///
/// [devices] is the whole house; the filtering happens here so that one
/// function answers "what is on this element" — the same rule
/// `selectDevicesForConfig` follows, and for the same reason: a preview and a
/// render that computed it separately would disagree eventually.
///
/// [keep] is the per-device filter the caller wants applied *inside* each room
/// — usually a facet, so "every light, by room" is one element. It is passed in
/// rather than re-derived here because the app already has one answer for
/// "which devices does this config mean" and a second one would drift from it.
///
/// [order] names rooms that should come first, in that order; everything else
/// follows alphabetically by label. A page that listed rooms in whatever order
/// the device list happened to arrive in would reshuffle itself as devices
/// came and went, which is the one thing a *layout* must never do.
List<RoomSection> roomSections({
  required List<DeviceState> devices,
  RoomChoice choice = RoomChoice.all,
  List<String> rooms = const [],
  List<String> order = const [],
  bool Function(DeviceState)? keep,
  String Function(String area)? label,
  bool hideEmpty = true,
}) {
  final wanted = {for (final r in rooms) _norm(r)};
  final byArea = <String, List<DeviceState>>{};

  for (final device in devices) {
    final area = _norm(device.effectiveArea);
    // Unplaced devices are deliberately dropped rather than gathered into an
    // "Unassigned" room. A section nobody made, that appears because something
    // is misconfigured elsewhere, is a page changing shape for a reason its
    // author cannot see.
    if (area.isEmpty) continue;
    if (choice == RoomChoice.named && !wanted.contains(area)) continue;
    if (keep != null && !keep(device)) continue;
    (byArea[area] ??= []).add(device);
  }

  // A named room with nothing in it still gets a section unless asked
  // otherwise: you named it, so its absence would read as the element being
  // broken rather than as the room being empty.
  if (choice == RoomChoice.named && !hideEmpty) {
    for (final r in wanted) {
      byArea.putIfAbsent(r, () => []);
    }
  }

  final sections = [
    for (final entry in byArea.entries)
      if (!(hideEmpty && entry.value.isEmpty))
        (
          area: entry.key,
          label: label?.call(entry.key) ?? _title(entry.key),
          devices: entry.value,
        ),
  ];

  final first = [for (final r in order) _norm(r)];
  sections.sort((a, b) {
    final ai = first.indexOf(a.area);
    final bi = first.indexOf(b.area);
    if (ai != bi) {
      if (ai < 0) return 1;
      if (bi < 0) return -1;
      return ai.compareTo(bi);
    }
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return sections;
}

/// `living_room` → `living_room`, `Living Room` → `living_room`.
///
/// The same normalisation core does, applied to both sides. A card that
/// compared raw strings shipped once and matched zero devices on every house.
String _norm(String? raw) =>
    (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');

/// `living_room` → `Living Room`, for a heading.
///
/// Only used when the house has no better spelling to offer. The areas list
/// does, and the caller passes it in — this is the fallback, not the answer.
String _title(String area) => area
    .split('_')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');
