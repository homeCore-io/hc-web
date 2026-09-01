import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/plugin_render.dart';
import '../dashboard/vocabulary.dart';
import 'auth_provider.dart';

/// Asks the core in front of us what a dashboard may contain, and what cards
/// its plugins have added.
///
/// A plugin widget cannot be compiled in — that is the entire point of it — so
/// unlike core's own cards, the only way to learn a plugin card's title, its
/// bindings and what it wants drawn is to ask. `plugin_widget` named a widget
/// nothing could enumerate until core started serving these.
///
/// **A core without the endpoint is not an error**, for the same reason
/// `vocabularyProvider` treats it that way: every core older than it fails the
/// request, and hitting one means we cannot ask, not that something is wrong.
/// The result is null, a plugin card falls back to naming itself, and the drift
/// notice stays silent rather than shouting about a check it never ran.
///
/// Note the failure is deliberately not narrowed to a 404. An older core
/// answers **400** here — there is no `/dashboards/vocabulary` route, so the
/// path falls through to `/dashboards/:id`, which looks for a dashboard called
/// "vocabulary". Core pins that ordering with
/// `the_vocabulary_route_is_not_shadowed_by_the_id_route`, and this is the
/// client half of the same worry.
final dashboardVocabularyProvider =
    FutureProvider<DashboardVocabularyDoc?>((ref) async {
  final client = ref.watch(homecoreClientProvider);

  try {
    final response = await client.dio.get('/dashboards/vocabulary');
    return DashboardVocabularyDoc.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  } on DioException catch (_) {
    return null;
  } catch (_) {
    return null;
  }
});

/// What this build cannot do about the core in front of it.
///
/// Null when we could not ask. Empty when we asked and agree.
final dashboardDriftProvider = Provider<DashboardDrift?>((ref) {
  final vocabulary = ref.watch(dashboardVocabularyProvider).value;
  if (vocabulary == null) return null;
  return DashboardDrift.between(vocabulary);
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
  final vocabulary = ref.watch(dashboardVocabularyProvider).value;
  if (vocabulary == null) return null;
  return vocabulary.pluginWidgets
      .where((s) => s.pluginId == pluginId && s.widgetId == widgetId)
      .cast<PluginWidgetSpec?>()
      .firstOrNull;
}

/// Every plugin card this installation offers, for a picker.
List<PluginWidgetSpec>? pluginWidgetCatalogue(WidgetRef ref) =>
    ref.watch(dashboardVocabularyProvider).value?.pluginWidgets;
