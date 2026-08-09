import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/plugin_runtimes_api.dart';
import 'auth_provider.dart';

final pluginRuntimesApiProvider = Provider<PluginRuntimesApi>((ref) {
  return PluginRuntimesApi(ref.watch(homecoreClientProvider));
});

/// Every runtime, whatever its status.
final pluginRuntimesProvider =
    FutureProvider.autoDispose<List<PluginRuntimeSummary>>((ref) async {
  return ref.watch(pluginRuntimesApiProvider).list();
});

/// Where each plugin runs, keyed by plugin id.
///
/// A plugin lives in one place at a time, so a map is the honest shape. Empty
/// when `[plugin_runtimes]` is off or nothing has been placed, which is the
/// common case and must not read as a failure — every page using this shows
/// *nothing extra*, rather than an error, when it is empty.
final pluginPlacementsProvider =
    FutureProvider.autoDispose<Map<String, PluginPlacement>>((ref) async {
  final rows = await ref.watch(pluginRuntimesApiProvider).placements();
  return {for (final p in rows) p.pluginId: p};
});

/// The runtime hosting [pluginId], if any — with the runtime's own details, so
/// a caller can name it the way an operator would recognise it.
///
/// Returns null both when the plugin runs on core and when the runtime list has
/// not arrived. The caller renders nothing either way: "running here" is the
/// unremarkable case and does not need saying.
final hostingRuntimeProvider =
    Provider.autoDispose.family<PluginRuntimeSummary?, String>((ref, pluginId) {
  final placement = ref.watch(pluginPlacementsProvider).value?[pluginId];
  if (placement == null) return null;
  final runtimes = ref.watch(pluginRuntimesProvider).value ?? const [];
  for (final r in runtimes) {
    if (r.runtimeId == placement.runtimeId) return r;
  }
  return null;
});
