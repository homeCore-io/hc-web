import '../models/device_state.dart';

/// Devices nothing owns any more.
///
/// A plugin that is removed, or hardware that goes away, leaves its devices
/// registered: unavailable forever, still in every picker, still referenced by
/// rules that will never fire again. Nothing else in the app surfaces them.
///
/// "Nothing owns it" is read from the device list itself rather than the plugin
/// registry: a device is orphaned when it is unavailable *and* no available
/// device shares its plugin id. A plugin that is merely restarting has its
/// other devices still live, so its devices are not swept up with it.
///
/// Lives here rather than inside the Maintenance screen because Manage counts
/// them too, and two copies of this rule would be two answers to the same
/// question.
List<DeviceState> orphanDevices(List<DeviceState> devices) {
  final livePlugins = {
    for (final d in devices)
      if (d.available) d.pluginId,
  };
  return [
    for (final d in devices)
      if (!d.available && !livePlugins.contains(d.pluginId)) d,
  ]..sort((a, b) => a.id.compareTo(b.id));
}
