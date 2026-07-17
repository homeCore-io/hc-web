import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/plugins_api.dart';
import '../models/plugin_entry.dart';
import '../models/registry_plugin.dart';
import 'auth_provider.dart';
import 'events_provider.dart';

final pluginsApiProvider = Provider<PluginsApi>((ref) {
  return PluginsApi(ref.watch(homecoreClientProvider));
});

/// The remote registry's plugin catalog. Auto-disposes so it re-fetches when the
/// Add-plugin sheet reopens (and after an install invalidates it).
final registryPluginsProvider =
    FutureProvider.autoDispose<List<RegistryPlugin>>((ref) async {
  return ref.watch(pluginsApiProvider).registryPlugins();
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
          final updated = [
            for (final p in current)
              p.pluginId == id ? p.copyWith(status: 'active') : p
          ];
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
          final updated = [
            for (final p in current)
              p.pluginId == id ? p.copyWith(status: 'offline') : p
          ];
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
