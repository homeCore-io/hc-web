import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/plugin_entry.dart';
import '../../core/providers/plugins_provider.dart';
import '../../shared/widgets/skeleton.dart';
import '../../core/providers/time_display_provider.dart';
import '../plugins/plugin_actions.dart';

class PluginsPage extends ConsumerWidget {
  const PluginsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pluginsAsync = ref.watch(pluginsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plugins'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(pluginsProvider)),
        ],
      ),
      body: pluginsAsync.when(
        loading: () => const SkeletonList(count: 6),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (plugins) {
          if (plugins.isEmpty) {
            return const Center(child: Text('No plugins registered'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: plugins.length,
            itemBuilder: (context, i) => _PluginTile(plugin: plugins[i]),
          );
        },
      ),
    );
  }
}

class _PluginTile extends ConsumerWidget {
  final PluginEntry plugin;
  const _PluginTile({required this.plugin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor =
        plugin.isActive ? Colors.green : Theme.of(context).colorScheme.error;
    final statusLabel = plugin.isActive ? 'Active' : plugin.status;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(
              Icons.extension,
              color: statusColor,
            ),
            title: Text(plugin.pluginId),
            subtitle: Text(
              '$statusLabel  ·  registered ${_shortDate(plugin.registeredAt, ref.watch(timeUtcProvider))}',
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (action) async {
                if (action == 'deregister') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('Deregister ${plugin.pluginId}?'),
                      content: const Text(
                          'The plugin process is not stopped — only the registry entry is removed.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel')),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Deregister')),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  try {
                    await ref
                        .read(pluginsApiProvider)
                        .deregister(plugin.pluginId);
                    ref.invalidate(pluginsProvider);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Failed: $e')));
                    }
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'deregister', child: Text('Deregister')),
              ],
            ),
          ),
          // Whatever this plugin declared it can do. Renders nothing for the
          // plugins that publish no manifest.
          PluginActions(pluginId: plugin.pluginId),
        ],
      ),
    );
  }

  String _shortDate(String iso, bool utc) {
    if (iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    final t = utc ? dt.toUtc() : dt.toLocal();
    final sfx = utc ? 'Z' : '';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}$sfx';
  }
}
