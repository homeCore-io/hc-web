import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/plugins_api.dart';
import '../models/plugin_entry.dart';
import 'auth_provider.dart';
import 'events_provider.dart';

final pluginsApiProvider = Provider<PluginsApi>((ref) {
  return PluginsApi(ref.watch(homecoreClientProvider));
});

class PluginsNotifier extends AsyncNotifier<List<PluginEntry>> {
  @override
  Future<List<PluginEntry>> build() async {
    // Apply live WS updates for plugin status changes.
    ref.listen(eventsStreamProvider, (_, next) {
      next.whenData((event) {
        final current = state.valueOrNull;
        if (current == null) return;

        if (event.type == 'plugin_registered') {
          final id = event.data['plugin_id'] as String?;
          if (id == null) return;
          final updated = current.map((p) {
            if (p.pluginId != id) return p;
            return PluginEntry(
                pluginId: p.pluginId,
                status: 'active',
                registeredAt: p.registeredAt);
          }).toList();
          // If plugin not in list yet, add it.
          if (!updated.any((p) => p.pluginId == id)) {
            updated.add(PluginEntry(
                pluginId: id,
                status: 'active',
                registeredAt: DateTime.now().toIso8601String()));
          }
          state = AsyncData(updated);
        } else if (event.type == 'plugin_offline') {
          final id = event.data['plugin_id'] as String?;
          if (id == null) return;
          final updated = current.map((p) {
            if (p.pluginId != id) return p;
            return PluginEntry(
                pluginId: p.pluginId,
                status: 'offline',
                registeredAt: p.registeredAt);
          }).toList();
          state = AsyncData(updated);
        }
      });
    });

    final raw = await ref.read(pluginsApiProvider).listPlugins();
    return raw.map(PluginEntry.fromJson).toList();
  }
}

final pluginsProvider =
    AsyncNotifierProvider<PluginsNotifier, List<PluginEntry>>(
        PluginsNotifier.new);
