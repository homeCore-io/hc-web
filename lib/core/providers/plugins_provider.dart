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

  /// Ask [pluginId] to change its live log filter, then refetch.
  ///
  /// Refetch rather than patch the record locally: core echoes back what it
  /// stored, and the whole point of showing this value is that it is core's
  /// record of the request rather than the client's memory of one.
  Future<void> setLogLevel(String pluginId, String directive) async {
    await ref.read(pluginsApiProvider).setLogLevel(pluginId, directive);
    final raw = await ref.read(pluginsApiProvider).listPlugins();
    state = AsyncData(raw.map(PluginEntry.fromJson).toList());
  }

  /// Refetch until the plugin has finished coming back, or we give up.
  ///
  /// Install and restart both return the moment core has *dispatched* the
  /// work: the process still has to start, connect to MQTT and register. A
  /// single invalidate at that moment refetches the old, still-offline record
  /// and never looks again — which is why an updated plugin sat there reading
  /// "offline" until the page was reloaded by hand.
  ///
  /// Backs off rather than hammering, stops as soon as [pluginId] reports
  /// active, and gives up quietly: a plugin that genuinely failed to start
  /// should read offline, because it is.
  Future<void> settle(String pluginId) async {
    const waits = [
      Duration(milliseconds: 400),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 3),
      Duration(seconds: 5),
    ];
    for (final w in waits) {
      ref.invalidateSelf();
      await future;
      final back = state.valueOrNull
          ?.where((p) => p.pluginId == pluginId)
          .any((p) => p.isActive);
      if (back == true) return;
      await Future<void>.delayed(w);
    }
    ref.invalidateSelf();
  }
}

final pluginsProvider =
    AsyncNotifierProvider<PluginsNotifier, List<PluginEntry>>(
        PluginsNotifier.new);
