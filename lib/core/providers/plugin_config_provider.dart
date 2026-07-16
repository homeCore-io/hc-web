import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/plugin_config.dart';
import '../schema/plugin_config_schema.dart';
import 'plugins_provider.dart';

/// A plugin's operator config (secrets redacted). Null when the plugin exposes
/// no editable config. Read-only; the editor writes via `putConfig` then
/// invalidates this to reload.
final pluginConfigProvider =
    FutureProvider.family<PluginConfigDoc?, String>((ref, id) {
  return ref.watch(pluginsApiProvider).getConfig(id);
});

/// The plugin's config JSON Schema, or null when it published none (the editor
/// then falls back to the raw-TOML view).
final pluginConfigSchemaProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, id) {
  return ref.watch(pluginsApiProvider).configSchema(id);
});

/// The schema translated to the flat form fields + metadata the editor renders,
/// or null when there is no schema. Depends on [pluginConfigSchemaProvider].
final pluginConfigFieldsProvider =
    FutureProvider.family<SchemaFields?, String>((ref, id) async {
  final schema = await ref.watch(pluginConfigSchemaProvider(id).future);
  if (schema == null) return null;
  return translateSchema(schema);
});
