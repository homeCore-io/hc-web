import '../models/device_state.dart';
import '../text/humanize.dart';

/// Every room the house can put a device in, as the pickers should offer it.
///
/// Two sources, because neither is complete on its own:
///
/// - `/areas` knows the rooms someone *declared* — including one created in the
///   Areas manager that holds nothing yet. A picker built only from devices
///   cannot offer it, and since the only way to fill a room is to pick it, an
///   empty room stays empty forever. That is the bug this exists to close.
/// - Devices know the rooms their bridges *report*, which are not always
///   registered — Hue and Lutron hand core an area name with no area record
///   behind it.
///
/// Core normalises names on the way in (`Master Bedroom`, `master_bedroom` and
/// `master bedroom` are one room), so dedupe on the humanised form: that is
/// both what is shown and what gets written back.
List<String> roomOptions({
  Iterable<Map<String, dynamic>> registered = const [],
  Iterable<DeviceState> devices = const [],
  Iterable<String> extra = const [],
}) {
  final names = <String>{
    for (final a in registered)
      if (a['name'] case final String n when n.trim().isNotEmpty) humanize(n),
    for (final d in devices)
      if (d.effectiveArea case final String a when a.trim().isNotEmpty)
        humanize(a),
    for (final e in extra)
      if (e.trim().isNotEmpty) humanize(e),
  };
  return names.toList()..sort();
}
