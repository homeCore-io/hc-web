import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import '../../core/models/dashboard.dart';
import '../../core/providers/dashboards_provider.dart';

class DashboardsPage extends ConsumerWidget {
  const DashboardsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardsAsync = ref.watch(dashboardsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboards'),
        actions: [
          IconButton(
            tooltip: 'Import dashboard',
            onPressed: () => _showImportDialog(context, ref),
            icon: const Icon(Icons.upload_file_outlined),
          ),
          IconButton(
            tooltip: 'New from template',
            onPressed: () => _showTemplateDialog(context, ref),
            icon: const Icon(Icons.dashboard_customize_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/dashboards/new/edit'),
        icon: const Icon(Icons.add),
        label: const Text('New Dashboard'),
      ),
      body: dashboardsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (dashboards) => dashboards.isEmpty
            ? const Center(child: Text('No dashboards yet'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemBuilder: (context, index) =>
                    _DashboardCard(dashboard: dashboards[index]),
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemCount: dashboards.length,
              ),
      ),
    );
  }
}

class _DashboardCard extends ConsumerWidget {
  final DashboardDefinition dashboard;
  const _DashboardCard({required this.dashboard});

  IconData _icon() {
    switch (dashboard.icon) {
      case 'shield':
        return Icons.shield_outlined;
      case 'chair':
        return Icons.chair_outlined;
      case 'play':
        return Icons.play_circle_outline;
      case 'tablet':
        return Icons.tablet_mac_outlined;
      default:
        return Icons.dashboard_outlined;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon()),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dashboard.name,
                          style: Theme.of(context).textTheme.titleMedium),
                      if (dashboard.description != null &&
                          dashboard.description!.isNotEmpty)
                        Text(dashboard.description!,
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (dashboard.isDefault) const Chip(label: Text('Default')),
              ],
            ),
            if (dashboard.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: dashboard.tags
                    .map((tag) => Chip(label: Text(tag)))
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => context.go('/dashboards/${dashboard.id}'),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      context.go('/dashboards/${dashboard.id}/edit'),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(dashboardsProvider.notifier).duplicateDashboard(
                            dashboard.id,
                          ),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Duplicate'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(dashboardsProvider.notifier).setDefault(
                            dashboard.id,
                          ),
                  icon: const Icon(Icons.star_border),
                  label: const Text('Set Default'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showExportDialog(context, ref, dashboard),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Export'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete dashboard?'),
                        content: Text('Delete "${dashboard.name}"?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await ref
                          .read(dashboardsProvider.notifier)
                          .deleteDashboard(dashboard.id);
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showTemplateDialog(BuildContext context, WidgetRef ref) async {
  final templates = await ref.read(dashboardTemplatesProvider.future);
  if (!context.mounted) return;
  final templateId = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Create From Template'),
      children: templates
          .map((template) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, template.id),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(template.name),
                  subtitle: Text(template.description ?? template.id),
                ),
              ))
          .toList(),
    ),
  );
  if (templateId == null) return;
  await ref.read(dashboardsProvider.notifier).createFromTemplate(templateId);
}

Future<void> _showExportDialog(
  BuildContext context,
  WidgetRef ref,
  DashboardDefinition dashboard,
) async {
  final exported =
      await ref.read(dashboardsProvider.notifier).exportDashboard(dashboard.id);
  if (!context.mounted) return;
  final controller = TextEditingController(
    text: const JsonEncoder.withIndent('  ').convert(exported.toJson()),
  );
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Export ${dashboard.name}'),
      content: SizedBox(
        width: 700,
        child: TextField(
          controller: controller,
          maxLines: 20,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Dashboard JSON',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> _showImportDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final imported = await showDialog<DashboardDefinition>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Import Dashboard'),
      content: SizedBox(
        width: 700,
        child: TextField(
          controller: controller,
          maxLines: 20,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Paste exported dashboard JSON',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final decoded = jsonDecode(controller.text);
            Navigator.pop(
              context,
              DashboardDefinition.fromJson(
                Map<String, dynamic>.from(decoded as Map),
              ),
            );
          },
          child: const Text('Import'),
        ),
      ],
    ),
  );
  if (imported == null) return;
  await ref.read(dashboardsProvider.notifier).importDashboard(imported);
}
