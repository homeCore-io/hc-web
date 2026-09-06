import '../models/device_state.dart';
import 'presentation.dart';
import '../models/scene.dart';
import 'scene_state.dart';

/// One scene as a picker or a row sees it: what it is called, and where it
/// lives.
///
/// The room is not decoration — it is the only thing telling four scenes
/// called *Nightlight* apart.
typedef ScenePick = ({String id, String name, String? area});

/// Every scene a scene row shows *right now*, in the order it draws them.
///
/// **One answer, asked by both halves.** The row worked out what to draw and
/// the picker worked out what to offer, and the two did not agree: a footer
/// showing fourteen scenes opened a picker with nothing ticked at all, because
/// "nothing picked" means "all of them" to one and "none of them" to the
/// other. John: *"when I drill into either of those nothing is already
/// selected but there are items in the box."*
///
/// So the picker opens ticked with exactly what is on the page, and unticking
/// is how you take one off — which is the thing everybody tried first.
List<ScenePick> scenesInScope(
  Map<String, dynamic> config,
  List<SceneModel> native,
  List<DeviceState> devices,
) {
  final scope = config['scope'] as String? ?? 'all';
  final room = (config['room'] as String? ?? '').trim();

  // A Hue scene is a property of a room's group, so a room page listing them
  // beside its lights AND under the picked light says them twice. Under the
  // light is where they belong.
  if (scope == 'device') {
    final id = (config['device_id'] as String? ?? '').trim();
    final owner = devices.where((d) => d.id == id).firstOrNull;
    if (owner == null) return const [];
    return [
      for (final d in scenesForDevice(owner, devices))
        (id: d.id, name: d.displayName, area: d.effectiveArea),
    ];
  }

  // `house` keeps the scenes with no room — a whole-house footer listing every
  // room's prints the same name three times, and none of the three is a
  // whole-house scene. `room` keeps one room's. Anything else keeps them all.
  bool wanted(String? area) => switch (scope) {
        'house' => area == null || area.isEmpty,
        'room' => room.isEmpty || area == room,
        _ => true,
      };

  // **The scenes a room has that none of its lights offer.**
  //
  // A Hue scene belongs to a room's *group*, so it is shown under the light it
  // sets and a room row listing every scene would say those twice. A Lutron or
  // Caseta scene is attached to no light at all — and so had nowhere on a room
  // page to be. John: *"some plugins provide scenes like lutron. Currently
  // there is no device scenes area in the room pages for these types of
  // scenes."*
  //
  // Claimed by asking the lights themselves rather than by testing for a
  // bridge id: whatever `scenesForDevice` decides belongs to a light is what
  // the light's own panel will draw, and this is the remainder by
  // construction.
  final claimed = <String>{};
  if (config['skip_light_scenes'] == true) {
    for (final d in devices) {
      if (!facetOf(d, d.schema).isLight) continue;
      if (!wanted(d.effectiveArea)) continue;
      for (final scene in scenesForDevice(d, devices)) {
        claimed.add(scene.id);
      }
    }
  }

  return [
    for (final s in native)
      if (wanted(null) && !claimed.contains(s.id))
        (id: s.id, name: s.name, area: null),
    for (final d in devices.where(isSceneDevice))
      if (wanted(d.effectiveArea) && !claimed.contains(d.id))
        (id: d.id, name: d.displayName, area: d.effectiveArea),
  ];
}

/// Every scene in the house, whatever any one element shows — what a picker
/// offers, sorted by name and then by room so two of the same name are next to
/// each other rather than scattered.
List<ScenePick> allScenes(
  List<SceneModel> native,
  List<DeviceState> devices,
) =>
    <ScenePick>[
      for (final s in native) (id: s.id, name: s.name, area: null),
      for (final d in devices)
        if (isSceneDevice(d))
          (id: d.id, name: d.displayName, area: d.effectiveArea),
    ]..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : (a.area ?? '').compareTo(b.area ?? '');
      });

/// The ids a scene row draws: what somebody picked, or everything in scope.
List<String> scenesShown(
  Map<String, dynamic> config,
  List<SceneModel> native,
  List<DeviceState> devices,
) {
  final picked =
      ((config['scene_ids'] as List?) ?? const []).whereType<String>().toList();
  if (picked.isNotEmpty) return picked;
  return [for (final s in scenesInScope(config, native, devices)) s.id];
}

/// The Hue scenes that belong to the same bridge and room as [device].
///
/// Returns empty for anything that is not a Hue light, which is most of the
/// house — the match is on `bridge_id`, so a device without one can never
/// accidentally collect another integration's scenes.
List<DeviceState> scenesForDevice(DeviceState device, List<DeviceState> all) {
  final bridge = device.state['bridge_id'];
  final area = device.effectiveArea;
  if (bridge is! String || bridge.isEmpty) return const [];
  if (area == null || area.isEmpty) return const [];

  final facet = facetOf(device, device.schema);
  const lights = {
    DeviceFacet.light,
    DeviceFacet.dimmableLight,
    DeviceFacet.colorLight,
  };
  if (!lights.contains(facet)) return const [];

  final out = [
    for (final d in all)
      if (facetOf(d, d.schema) == DeviceFacet.scene &&
          d.state['bridge_id'] == bridge &&
          d.effectiveArea == area)
        d,
  ]..sort((a, b) => a.displayName.compareTo(b.displayName));
  return out;
}
