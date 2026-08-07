import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/dashboard.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/dashboards_provider.dart';
import '../../core/providers/nav_prefs_provider.dart';

/// The per-page actions behind the "⋯" menu and the launcher's "+".
///
/// All of them go through [dashboardsProvider], the same CRUD the old CMS used —
/// only the UI is app-native now. Creating a page lands you straight in it; the
/// editing happens on the page, not in a form.

Future<void> onPageAction(
  BuildContext context,
  WidgetRef ref,
  DashboardDefinition dashboard,
  String action,
) async {
  switch (action) {
    case 'rename':
      final name = await _prompt(context, 'Rename page', dashboard.name);
      if (name == null || name.isEmpty) return;
      await ref
          .read(dashboardsProvider.notifier)
          .updateDashboard(dashboard.copyWith(name: name));
      break;
    case 'home':
      await ref
          .read(landingRouteProvider.notifier)
          .set('/pages/${dashboard.id}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${dashboard.name} is now your Home page')),
        );
      }
      break;
    case 'duplicate':
      await ref
          .read(dashboardsProvider.notifier)
          .duplicateDashboard(dashboard.id);
      break;
    case 'delete':
      final ok = await _confirmDelete(context, dashboard.name);
      if (!ok) return;
      await ref.read(dashboardsProvider.notifier).deleteDashboard(dashboard.id);
      // If this was the Home page, fall back to the house.
      if (ref.read(landingRouteProvider) == '/pages/${dashboard.id}') {
        await ref.read(landingRouteProvider.notifier).set('/');
      }
      if (context.mounted) context.go('/');
      break;
  }
}

/// Creates a blank page and navigates into it, in edit mode-ready state.
Future<void> createPage(BuildContext context, WidgetRef ref) async {
  final name = await _prompt(context, 'New page', 'New page');
  if (name == null || name.isEmpty) return;

  final currentUser = await ref.read(currentUserProvider.future);
  final owner = currentUser?['id'] as String? ??
      currentUser?['username'] as String? ??
      'local_user';
  final now = DateTime.now();
  final id = 'dashboard_${now.microsecondsSinceEpoch}';

  final page = DashboardDefinition(
    id: id,
    name: name,
    description: null,
    ownerUserId: owner,
    visibility: DashboardVisibility.private,
    tags: const [],
    icon: 'dashboard',
    isDefault: false,
    createdAt: now,
    updatedAt: now,
    // Desktop is the one you draw; the other three follow it until someone
    // arranges one by hand, at which point that one stops following. A page
    // created with desktop alone would render on a phone through the fallback
    // chain — legible, but nobody could then give the phone its own order
    // without the derived layouts existing first.
    layouts: const [
      DashboardLayout(
        breakpoint: DashboardBreakpoint.desktop,
        columns: 12,
        rowHeight: 120,
        gap: 12,
        placements: [],
      ),
      DashboardLayout(
        breakpoint: DashboardBreakpoint.mobile,
        columns: 4,
        rowHeight: 100,
        gap: 8,
        placements: [],
        derivedFrom: DashboardBreakpoint.desktop,
      ),
      DashboardLayout(
        breakpoint: DashboardBreakpoint.tablet,
        columns: 8,
        rowHeight: 120,
        gap: 12,
        placements: [],
        derivedFrom: DashboardBreakpoint.desktop,
      ),
      DashboardLayout(
        breakpoint: DashboardBreakpoint.tv,
        columns: 12,
        rowHeight: 180,
        gap: 16,
        placements: [],
        derivedFrom: DashboardBreakpoint.desktop,
      ),
    ],
    widgets: const [],
  );

  await ref.read(dashboardsProvider.notifier).createDashboard(page);
  if (context.mounted) context.go('/pages/$id');
}

Future<String?> _prompt(BuildContext context, String title, String initial) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<bool> _confirmDelete(BuildContext context, String name) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete "$name"?'),
      content: const Text('This removes the page. Devices are not affected.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
