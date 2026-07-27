import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';

/// One short phrase about a room, for its header.
class RoomSummary {
  const RoomSummary(this.text, {this.warn = false});

  final String text;

  /// Whether it wants attention — an unlocked lock, an open door, a leak. Drawn
  /// in the warn accent so a collapsed room can still shout.
  final bool warn;
}

/// What a room is like, beyond how many things are on.
///
/// "3 of 9 on" is a fact about switches, not about the room. It cannot tell you
/// the back door is open or that the garage is at 87°, which are exactly the
/// things you would want before deciding a collapsed room is fine to leave
/// collapsed.
///
/// Faults win over comfort, because a temperature is never the more urgent of
/// the two. Returns null when the room has nothing to add — a room of three
/// lamps says nothing here rather than padding the header.
RoomSummary? roomSummary(List<DeviceState> devices) {
  final faults = <String>[];
  var openDoors = 0;
  double? temperature;
  bool? occupied;

  for (final d in devices) {
    if (!d.available) continue;
    final s = d.state;
    final facet = facetOf(d, d.schema);

    // A leak is the loudest thing a house can say.
    if ((s['leak'] ?? s['water_detected']) case true) {
      return const RoomSummary('water detected', warn: true);
    }
    if (s['smoke'] case true) {
      return const RoomSummary('smoke', warn: true);
    }

    if (facet == DeviceFacet.lock && s['locked'] == false) {
      faults.add('unlocked');
    }
    // Only real openings count. A `contact` attribute is ambiguous across
    // plugins (see device_readings.dart), so it is deliberately not read here.
    if (s['open'] == true &&
        const {
          DeviceFacet.door,
          DeviceFacet.window,
          DeviceFacet.garage,
          DeviceFacet.contact,
        }.contains(facet)) {
      openDoors++;
    }

    if (temperature == null) {
      final v = s['temperature'] ?? s['current_temperature'];
      if (v is num) temperature = v.toDouble();
    }
    if ((s['occupancy'] ?? s['occupied']) case final bool o) {
      // Any occupied sensor makes the room occupied; one empty one does not
      // make it empty.
      occupied = (occupied ?? false) || o;
    }
  }

  if (openDoors > 0) {
    faults.add(openDoors == 1 ? 'door open' : '$openDoors doors open');
  }
  if (faults.isNotEmpty) return RoomSummary(faults.join(' · '), warn: true);

  final calm = <String>[
    if (temperature != null) '${temperature.round()}°',
    if (occupied == true) 'occupied',
  ];
  return calm.isEmpty ? null : RoomSummary(calm.join(' · '));
}
