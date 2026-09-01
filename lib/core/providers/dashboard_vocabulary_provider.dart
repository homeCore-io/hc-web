import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/plugin_render.dart';
import 'auth_provider.dart';

/// The cards the core in front of us knows about, including the ones plugins
/// contributed.
///
/// A plugin widget cannot be compiled in — that is the entire point of it — so
/// unlike core's own cards, the only way to learn a plugin card's title, its
/// bindings and what it wants drawn is to ask. `plugin_widget` named a widget
/// nothing could enumerate until core started serving these.
///
/// **A core without the endpoint is not an error**, for the same reason
/// `vocabularyProvider` treats it that way: every core older than it fails the
/// request, and hitting one means we cannot ask, not that something is wrong.
/// The result is null and a plugin card falls back to naming itself.
///
/// Note the failure is deliberately not narrowed to a 404. An older core
/// answers **400** here — there is no `/dashboards/vocabulary` route, so the
/// path falls through to `/dashboards/:id`, which looks for a dashboard called
/// "vocabulary". Core pins that ordering with
/// `the_vocabulary_route_is_not_shadowed_by_the_id_route`, and this is the
/// client half of the same worry.
final dashboardVocabularyProvider =
    FutureProvider<List<PluginWidgetSpec>?>((ref) async {
  final client = ref.watch(homecoreClientProvider);

  try {
    final response = await client.dio.get('/dashboards/vocabulary');
    final data = Map<String, dynamic>.from(response.data as Map);
    return [
      for (final w in (data['plugin_widgets'] as List? ?? const []))
        if (PluginWidgetSpec.fromJson(w) case final spec?) spec,
    ];
  } on DioException catch (_) {
    return null;
  } catch (_) {
    return null;
  }
});

/// The declaration behind one `{plugin_id, widget_id}` pair, or null while we
/// are still asking, could not ask, or the plugin that owned it went away.
///
/// A plugin that has stopped publishing is the ordinary case, not a failure:
/// its cards stay on the page and stop being drawable, which is exactly what a
/// person should see when the thing feeding a card is gone.
PluginWidgetSpec? pluginWidgetSpec(
  WidgetRef ref,
  String pluginId,
  String widgetId,
) {
  final all = ref.watch(dashboardVocabularyProvider).value;
  if (all == null) return null;
  return all
      .where((s) => s.pluginId == pluginId && s.widgetId == widgetId)
      .cast<PluginWidgetSpec?>()
      .firstOrNull;
}
