import 'descriptor.dart';
import 'sonos_fixture.dart';

/// Resolve a plugin's config descriptor.
///
/// Prototype: the hand-authored Sonos fixture. Later this fetches
/// `GET /plugins/:id/config/descriptor` (with an auto-derived-from-schema
/// fallback for plugins that ship no descriptor yet). Returning null means
/// "no descriptor" → the Studio falls back to the legacy schema form.
ConfigDescriptor? descriptorFor(String pluginId) {
  switch (pluginId) {
    case 'plugin.sonos':
      return ConfigDescriptor.fromJson(sonosDescriptorFixture);
    default:
      return null;
  }
}
