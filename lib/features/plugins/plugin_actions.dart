import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/action_stream.dart';
import '../../core/api/plugins_api.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/plugins_provider.dart';
import '../../core/schema/plugin_capabilities.dart';
import '../../design/tokens.dart';
import 'action_drawer.dart';
import 'action_form.dart';
import 'discovery_dialog.dart';

/// A plugin's declared actions, or null if it never published a manifest.
final pluginCapabilitiesProvider =
    FutureProvider.family<PluginCapabilities?, String>((ref, pluginId) async {
  return ref.watch(pluginsApiProvider).capabilities(pluginId);
});

/// How to lay a plugin's actions out: compact buttons, or the Studio's rich
/// icon/name/description cards.
enum PluginActionsLayout { buttons, cards }

/// Renders every action a plugin declares as a working control.
///
/// There is no plugin-specific code here or anywhere downstream. On a real
/// install this surfaces 25 actions across 7 plugins — Z-Wave inclusion, Hue and
/// Sonos discovery, Ecowitt gateway configuration — none of which the UI could
/// reach before, and all of which arrive with a label, a param schema and a
/// required role.
class PluginActions extends ConsumerWidget {
  const PluginActions({
    super.key,
    required this.pluginId,
    this.layout = PluginActionsLayout.buttons,
  });

  final String pluginId;
  final PluginActionsLayout layout;

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

        if (layout == PluginActionsLayout.cards) {
          return LayoutBuilder(builder: (context, box) {
            final cols = box.maxWidth > 560 ? 2 : 1;
            final w = (box.maxWidth - (cols - 1) * 12) / cols;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final action in c.actions)
                  SizedBox(
                    width: w,
                    child: _ActionCard(
                      pluginId: pluginId,
                      action: action,
                      allowed: action.requiresRole.satisfiedBy(role),
                    ),
                  ),
              ],
            );
          });
        }

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
      onPressed: allowed
          ? () => runPluginAction(context, ref, pluginId, action)
          : null,
    );

    if (allowed) return button;

    return Tooltip(
      message: 'Requires the ${action.requiresRole.name} role',
      child: button,
    );
  }
}

/// The Studio's rich action card: icon tile · label · description · Run.
/// Runs through the same [runPluginAction] path as the compact button.
class _ActionCard extends ConsumerWidget {
  const _ActionCard({
    required this.pluginId,
    required this.action,
    required this.allowed,
  });

  final String pluginId;
  final PluginAction action;
  final bool allowed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final card = Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 13, 13),
      decoration: BoxDecoration(
        color: t.surface.raised,
        borderRadius: t.radius.mdR,
        border: Border.all(color: t.stroke.hairline),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.surface.sunken,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: t.stroke.hairline),
          ),
          child: Icon(_actionIcon(action), size: 19, color: t.accent.active),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: t.surface.onBase,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600)),
              if (action.description != null) ...[
                const SizedBox(height: 2),
                Text(action.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: t.surface.onBaseMuted, fontSize: 12.5)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed: allowed
              ? () => runPluginAction(context, ref, pluginId, action)
              : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: t.accent.active,
            side: BorderSide(color: t.accent.active.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: Text(action.stream ? 'Start' : 'Run'),
        ),
      ]),
    );

    if (allowed) return card;
    return Tooltip(
      message: 'Requires the ${action.requiresRole.name} role',
      child: Opacity(opacity: 0.55, child: card),
    );
  }
}

/// Best-effort icon for an action from its id/label keywords. No plugin-specific
/// coupling — just a friendlier default than a generic play arrow.
IconData _actionIcon(PluginAction a) {
  if (a.stream) return Icons.stream_rounded;
  final s = '${a.id} ${a.label}'.toLowerCase();
  if (s.contains('pair') || s.contains('link') || s.contains('connect')) {
    return Icons.link_rounded;
  }
  if (s.contains('discover') || s.contains('scan') || s.contains('search')) {
    return Icons.travel_explore_rounded;
  }
  if (s.contains('refresh') || s.contains('sync') || s.contains('reload')) {
    return Icons.refresh_rounded;
  }
  if (s.contains('clean') ||
      s.contains('prune') ||
      s.contains('remove') ||
      s.contains('delete')) {
    return Icons.cleaning_services_rounded;
  }
  if (s.contains('include') || s.contains('add')) return Icons.add_rounded;
  if (s.contains('identify') || s.contains('locate')) {
    return Icons.my_location_rounded;
  }
  return Icons.play_arrow_rounded;
}

/// Shared runner for a plugin action — param form, invoke, stream follow, toast.
/// Both the compact button and the Studio card call this so behaviour never
/// diverges.
Future<void> runPluginAction(
  BuildContext context,
  WidgetRef ref,
  String pluginId,
  PluginAction action,
) async {
  // Ask for params first — but only when there are any. Most of these actions
  // take none, and a confirmation dialog for "Rescan nodes" is friction.
  Map<String, Object?>? params = const {};
  if (action.params.isNotEmpty || action.stream) {
    params = await showDialog<Map<String, Object?>>(
      context: context,
      // Pop the DIALOG's navigator, not the caller's. `context` here belongs to
      // the page, which lives inside go_router's ShellRoute navigator, while
      // showDialog pushes onto the root one — so popping `context` unmounted the
      // page and left a blank white app instead of submitting the form.
      builder: (dialogContext) => ActionForm(
        action: action,
        onSubmit: (p) => Navigator.pop(dialogContext, p),
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
      // A `discover_devices`-style result (a `discovered` array) opens the
      // review-and-add dialog instead of a toast; anything else just toasts.
      final discovered = _discoveryList(data);
      if (discovered != null && discovered.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (_) => DiscoveryResultsDialog(
              pluginId: pluginId, discovered: discovered),
        );
      } else {
        _toast(context, _summarise(data));
      }

    case CommandStreaming(:final requestId):
      await _follow(context, ref, pluginId, action, requestId);

    // A `single` action already running: attach to the run in progress rather
    // than reporting a collision. Starting a second Z-Wave inclusion is never
    // what the user meant.
    case CommandBusy(:final activeRequestId):
      _toast(context, 'Already running — attaching.');
      await _follow(context, ref, pluginId, action, activeRequestId);
  }
}

Future<void> _follow(
  BuildContext context,
  WidgetRef ref,
  String pluginId,
  PluginAction action,
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

/// Extracts a `discovered` array from an action result, normalised to a list of
/// string-keyed maps. Null when the result isn't a discovery payload.
List<Map<String, dynamic>>? _discoveryList(Object? data) {
  if (data is! Map) return null;
  final d = data['discovered'];
  if (d is! List) return null;
  return d
      .whereType<Map>()
      .map((m) => m.map((k, v) => MapEntry('$k', v)))
      .toList();
}

String _summarise(Object? data) {
  if (data == null) return 'Done.';
  if (data is Map) {
    // A plugin that ran but reported a problem answers with status:"error"
    // (HTTP 200, not a 504) — surface its message rather than a raw JSON dump.
    if (data['status'] == 'error') {
      return 'Failed: ${data['error'] ?? data['message'] ?? 'unknown error'}';
    }
    if (data['message'] != null) return '${data['message']}';
  }
  final s = '$data';
  return s.length > 160 ? '${s.substring(0, 157)}…' : s;
}
