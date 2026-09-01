/// What a scene is, and whether it is applied — in one place.
///
/// Scenes arrive two ways and the difference matters at every call site:
///
///  * **Native** scenes come from `/scenes`. Core applies them and does not
///    report whether they are currently in effect, because "in effect" is not
///    a thing core tracks — the devices moved and nothing recorded why.
///  * **Plugin** scenes arrive as *devices* with `device_type == 'scene'`.
///    Those do report, because the bridge knows: Hue publishes `active`, Lutron
///    publishes `on` from the phantom-button LED.
///
/// This was inside `features/scenes/scenes_page.dart`, which made it invisible
/// to everything that is not that page — and a drawn scene button that decided
/// "active" differently from the scenes list would be two answers to one
/// question. `attribute_policy.dart` states the principle for device
/// attributes; this is the same principle for scenes.
library;

import '../models/device_state.dart';

/// Coerce an attribute to a bool, accepting the spellings plugins use.
///
/// Null when the value is not a recognisable boolean, so a caller can fall
/// through to the next key rather than treating "unknown" as "off".
bool? boolAttr(Object? v) {
  if (v is bool) return v;
  if (v is String) {
    switch (v.trim().toLowerCase()) {
      case 'true':
      case 'on':
      case 'open':
      case 'active':
      case 'occupied':
      case 'detected':
        return true;
      case 'false':
      case 'off':
      case 'closed':
      case 'inactive':
      case 'clear':
      case 'unoccupied':
        return false;
    }
  }
  return null;
}

/// Whether a plugin scene is currently applied.
///
/// Plugins disagree on the field, so the recognised keys are checked in order
/// and the first recognisable boolean wins — the same resilient logic the
/// previous Leptos UI used.
bool sceneActive(Map<String, dynamic> attrs) {
  for (final k in const ['on', 'active', 'activate', 'state']) {
    final b = boolAttr(attrs[k]);
    if (b != null) return b;
  }
  return false;
}

/// A device that is really a scene the bridge exposes.
bool isSceneDevice(DeviceState d) => d.deviceType == 'scene';

/// Whether this scene's state is knowable at all.
///
/// A native scene always answers false to [sceneActive], and that false means
/// "nobody is tracking" rather than "not applied". Anything that draws a state
/// has to tell those two apart or it will confidently report every native scene
/// as off.
bool sceneStateIsKnowable({required bool isPlugin}) => isPlugin;
