import 'descriptor.dart';

/// Local hand-authored descriptors — the stand-in tier of
/// `pluginDescriptorProvider`, sitting between the plugin's own published
/// descriptor and the schema-derived fallback.
///
/// **Empty now.** hc-sonos publishes its own descriptor (SDK
/// `with_config_descriptor` → capability manifest → `GET /config/descriptor`),
/// so the Sonos fixture is retired from the resolution chain; it lives on only
/// as the input to the `/#/dev/config` preview harness (`sonos_fixture.dart`).
///
/// Add a case here only to prototype a descriptor for a plugin that cannot yet
/// publish one — and delete it as soon as the plugin ships its own.
ConfigDescriptor? descriptorFor(String pluginId) => null;
