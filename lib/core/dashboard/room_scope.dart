/// One room page, fifteen rooms.
///
/// `room_field` opens the same page for every cell and passes the room in the
/// route — `/dashboards/<id>?room=kitchen`. Nothing read it, so every cell
/// opened a page hard-wired to the office: the right layout showing the wrong
/// room fourteen times out of fifteen. John, asking for the house page's
/// temperature chart everywhere: *"All room pages should have that."* There is
/// only one room page, so it has to be able to be about whichever room you
/// opened it for.
///
/// **`@room` is the whole vocabulary.** A page says *this room* where it would
/// otherwise name one, and the reference is resolved once — at the seam where a
/// placement becomes a widget — so no element learns anything new. The chart,
/// the bindings, the selections and the tap actions all receive a config with
/// real names in it, exactly as if somebody had typed them.
library;

import '../devices/breakdown.dart' show prettyGroup;
import '../models/device_state.dart';
import '../devices/presentation.dart' show normalizeAreaName;

/// What a page writes where it would otherwise name a room or a device.
const roomToken = '@room';

/// The keys whose value may be `@room` meaning *this page's room*.
const _areaKeys = {'area_name', 'room'};

/// Whether [config] mentions the token anywhere this resolver looks.
///
/// Cheap enough to run on every element every build, and it keeps a page that
/// never says `@room` byte-identical to what it was before.
bool mentionsRoom(Map<String, dynamic> config) {
  for (final key in _areaKeys) {
    if (config[key] == roomToken) return true;
  }
  if (config['device_id'] == roomToken) return true;
  if (config['text'] == roomToken) return true;
  final tap = config['on_tap'];
  if (tap is Map && tap['target'] == roomToken) return true;
  final bindings = config['bindings'];
  if (bindings is List) {
    for (final b in bindings) {
      if (b is Map && b['device_id'] == roomToken) return true;
    }
  }
  return false;
}

/// The device in [room] that reports [reporting], or null when none does.
///
/// *Whatever in this room tells you that* — which is the only sensible reading
/// of a room-relative device reference. A page cannot name the kitchen's
/// thermometer, because it is a different device in every room and in some
/// rooms it is not there at all.
///
/// Sorted by name so the answer does not change between two devices that both
/// qualify; an unavailable one is a last resort rather than a disqualification,
/// because a sensor that has gone quiet is still the sensor this room has.
DeviceState? deviceInRoom(
  Iterable<DeviceState> devices,
  String? room, {
  required String reporting,
}) {
  if (room == null || room.isEmpty || reporting.isEmpty) return null;
  final want = normalizeAreaName(room);
  final here = [
    for (final d in devices)
      if (normalizeAreaName(d.effectiveArea) == want &&
          d.state.containsKey(reporting) &&
          d.state[reporting] != null)
        d,
  ]..sort((a, b) => a.displayName.compareTo(b.displayName));
  if (here.isEmpty) return null;
  for (final d in here) {
    if (d.available) return d;
  }
  return here.first;
}

/// [config] with every `@room` replaced by what it means on this page.
///
/// Returns the same map when there is nothing to do, so an element on a page
/// that never mentions a room rebuilds exactly as it did before.
///
/// A reference that resolves to nothing is left as the token rather than
/// blanked: an element pointed at a device this room does not have should say
/// it has no device, which is what an unresolvable id already makes it say.
Map<String, dynamic> resolveRoomRefs(
  Map<String, dynamic> config, {
  required String? room,
  required List<DeviceState> devices,
}) {
  if (room == null || room.isEmpty) return config;
  if (!mentionsRoom(config)) return config;

  final out = Map<String, dynamic>.from(config);

  for (final key in _areaKeys) {
    if (out[key] == roomToken) out[key] = room;
  }

  // A heading that says which room you are looking at. The page cannot know
  // the word, and asking somebody to keep fifteen copies of the page in step
  // is the thing one page exists to avoid.
  if (out['text'] == roomToken) out['text'] = prettyGroup(room);

  // A device reference asks for whatever here reports the thing being read.
  // The sibling key IS the question: a chart names its `attribute`, a binding
  // names its `key`, and either is enough to pick.
  if (out['device_id'] == roomToken) {
    final wants = (out['attribute'] as String? ?? '').trim();
    final found = deviceInRoom(devices, room, reporting: wants);
    if (found != null) out['device_id'] = found.id;
  }

  final tap = out['on_tap'];
  if (tap is Map && tap['target'] == roomToken) {
    final next = Map<String, dynamic>.from(tap);
    final wants = (next['attribute'] as String? ?? 'on').trim();
    final found = deviceInRoom(devices, room, reporting: wants);
    if (found != null) {
      next['target'] = found.id;
      out['on_tap'] = next;
    }
  }

  final bindings = out['bindings'];
  if (bindings is List) {
    out['bindings'] = [
      for (final b in bindings)
        if (b is Map && b['device_id'] == roomToken)
          () {
            final next = Map<String, dynamic>.from(b);
            final wants = (next['key'] as String? ?? '').trim();
            final found = deviceInRoom(devices, room, reporting: wants);
            if (found != null) next['device_id'] = found.id;
            return next;
          }()
        else
          b,
    ];
  }

  return out;
}
