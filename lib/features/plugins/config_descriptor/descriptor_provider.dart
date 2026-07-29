import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/plugin_config_provider.dart';
import '../../../core/providers/plugins_provider.dart';
import 'descriptor.dart';
import 'descriptor_auto.dart';
import 'descriptor_registry.dart';

/// Resolve the config descriptor the editor should render, in precedence order:
///
/// 1. **Plugin-authored** — `GET /plugins/:id/config/descriptor` (phase 3).
///    Wins whenever present; this is the endgame once the SDK emits it.
/// 2. **Local fixture** — hand-authored stand-in while the SDK is unbuilt
///    (Sonos today). Drops out as soon as the plugin ships its own.
/// 3. **Auto-derived** — built from the plugin's JSON Schema (phase 4), so every
///    un-migrated plugin still gets the descriptor renderer instead of the
///    legacy schema form.
///
/// Null only when the plugin publishes neither descriptor nor schema — the
/// Studio then falls back to the raw/legacy editor.
final pluginDescriptorProvider =
    FutureProvider.family<ConfigDescriptor?, String>((ref, id) async {
  // 1. plugin-authored
  final published = await ref.watch(pluginsApiProvider).configDescriptor(id);
  if (published != null) return ConfigDescriptor.fromJson(published);

  // 2. local hand-authored stand-in
  final fixture = descriptorFor(id);
  if (fixture != null) return fixture;

  // 3. derived from the schema
  final schema = await ref.watch(pluginConfigSchemaProvider(id).future);
  if (schema == null) return null;
  return autoDeriveDescriptor(id, schema);
});
