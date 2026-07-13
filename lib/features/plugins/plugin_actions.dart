import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/action_stream.dart';
import '../../core/api/plugins_api.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/plugins_provider.dart';
import '../../core/schema/plugin_capabilities.dart';
import 'action_drawer.dart';
import 'action_form.dart';

/// A plugin's declared actions, or null if it never published a manifest.
final pluginCapabilitiesProvider =
    FutureProvider.family<PluginCapabilities?, String>((ref, pluginId) async {
  return ref.watch(pluginsApiProvider).capabilities(pluginId);
});

/// Renders every action a plugin declares as a working button.
///
/// There is no plugin-specific code here or anywhere downstream. On a real
/// install this surfaces 25 actions across 7 plugins — Z-Wave inclusion, Hue and
/// Sonos discovery, Ecowitt gateway configuration — none of which the UI could
/// reach before, and all of which arrive with a label, a param schema and a
/// required role.
class PluginActions extends ConsumerWidget {
  const PluginActions({super.key, required this.pluginId});

  final String pluginId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(pluginCapabilitiesProvider(pluginId));
    final role = ref.watch(currentUserProvider).valueOrNull?['role'] as String?;

    return caps.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(8),
        child: LinearProgressIndicator(),
      ),
      // Most plugins publish nothing; that is not an error worth a red box.
      error: (_, __) => const SizedBox.shrink(),
      data: (c) {
        if (c == null || c.actions.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final action in c.actions)
                _ActionButton(
                  pluginId: pluginId,
                  action: action,
                  // Core answers 403 anyway, but a button you cannot press
                  // should look unpressable rather than fail on click.
                  allowed: action.requiresRole.satisfiedBy(role),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionButton extends ConsumerWidget {
  const _ActionButton({
    required this.pluginId,
    required this.action,
    required this.allowed,
  });

  final String pluginId;
  final PluginAction action;
  final bool allowed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final button = OutlinedButton.icon(
      icon: Icon(
        action.stream ? Icons.stream : Icons.play_arrow,
        size: 16,
      ),
      label: Text(action.label),
      onPressed: allowed ? () => _run(context, ref) : null,
    );

    if (allowed) return button;

    return Tooltip(
      message: 'Requires the ${action.requiresRole.name} role',
      child: button,
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref) async {
    // Ask for params first — but only when there are any. Most of these actions
    // take none, and a confirmation dialog for "Rescan nodes" is friction.
    Map<String, Object?>? params = const {};
    if (action.params.isNotEmpty || action.stream) {
      params = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (_) => ActionForm(
          action: action,
          onSubmit: (p) => Navigator.pop(context, p),
        ),
      );
      if (params == null) return; // cancelled
    }

    final api = ref.read(pluginsApiProvider);

    final CommandOutcome outcome;
    try {
      outcome = await api.invoke(pluginId, action, params);
    } catch (e) {
      if (context.mounted) _toast(context, 'Failed: $e');
      return;
    }

    if (!context.mounted) return;

    switch (outcome) {
      case CommandDone(:final data):
        _toast(context, _summarise(data));

      case CommandStreaming(:final requestId):
        await _follow(context, ref, requestId);

      // A `single` action already running: attach to the run in progress rather
      // than reporting a collision. Starting a second Z-Wave inclusion is never
      // what the user meant.
      case CommandBusy(:final activeRequestId):
        _toast(context, 'Already running — attaching.');
        await _follow(context, ref, activeRequestId);
    }
  }

  Future<void> _follow(
    BuildContext context,
    WidgetRef ref,
    String requestId,
  ) async {
    // EventSource cannot set headers, so the JWT rides in the query string —
    // which is exactly why core accepts `?token=` on this route.
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null || !context.mounted) return;

    final events = openActionStream(
      pluginId: pluginId,
      requestId: requestId,
      token: token,
    ).asBroadcastStream();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ActionDrawer(
        action: action,
        events: events,
        onCancel: action.cancelable
            ? () => ref.read(pluginsApiProvider).invoke(
                  pluginId,
                  action,
                  {'cancel': requestId},
                )
            : null,
      ),
    );

    // A completed inclusion or discovery has almost certainly changed the
    // device list.
    ref.invalidate(pluginsProvider);
  }

  void _toast(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  String _summarise(Object? data) {
    if (data == null) return 'Done.';
    if (data is Map && data['message'] != null) return '${data['message']}';
    final s = '$data';
    return s.length > 160 ? '${s.substring(0, 157)}…' : s;
  }
}
