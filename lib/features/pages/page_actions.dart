import 'package:dio/dio.dart';
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
    // Creating a page is offered from the page you are on, because that is
    // where you are when you decide you want another one. It was reachable only
    // from the launcher and the Pages list, so the menu that could duplicate a
    // page could not make one.
    case 'new':
      await createPage(context, ref);
      break;
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
    // **The page you designed becomes something to start the next one from.**
    //
    // Templates were five documents compiled into core, read-only, so every
    // good page anybody made stayed a one-off. This is the write path, and the
    // whole of it: a template is a copy of this page with the house taken out
    // of it, which is the transform sharing already did.
    //
    // It says the name back, because the name may not be this page's — a
    // second template of the same name is given a suffix, and finding out by
    // going to look is a worse way to learn it.
    case 'template':
      final messenger = ScaffoldMessenger.of(context);
      final notifier = ref.read(dashboardsProvider.notifier);
      if (!notifier.canSaveTemplates) {
        // Rather than appearing to work. Without core the templates list is a
        // fixed set built in Dart, so a saved one has nowhere to go.
        messenger.showSnackBar(const SnackBar(
          content: Text('Starting points need a connection to the house.'),
        ));
        return;
      }
      final template = await notifier.saveAsTemplate(dashboard.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Saved “${template.name}” — start a page from it '
              'with New page'),
        ),
      );
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
///
/// **Nothing here may reach through [context] after the first `await`.** This
/// is called from the hub launcher, which is a route that closes as part of the
/// same gesture, and a `BuildContext` dies with the route it belongs to: the
/// router and the messenger are taken *now*, while they are still real. Doing
/// it the other way is what made New page look like it did nothing — the page
/// was created and then never opened, because the `context.mounted` guard on
/// the way out was false and silently skipped the navigation.
///
/// [dismiss] closes whatever surface offered the action, once there is a name
/// to act on. It runs *after* the prompt rather than before, so the prompt is
/// still being shown by a live route.
Future<void> createPage(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? dismiss,
}) async {
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);

  final name = await _prompt(context, 'New page', 'New page');
  if (name == null || name.isEmpty) return;
  dismiss?.call();

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

  // **Loudly, or not at all.** A create that throws used to close the dialog
  // and leave the house exactly as it was, which is indistinguishable from a
  // button that is not wired up — and that is what it was reported as.
  try {
    await ref.read(dashboardsProvider.notifier).createDashboard(page);
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not create "$name": ${_short(e)}')),
    );
    return;
  }

  // Through the router taken above, not through `context`: by now the surface
  // that offered this action has usually closed, and a page created but not
  // opened is the same bug wearing a different hat.
  router.go('/pages/$id');
}

/// The useful half of an error, without the stack or the wrapper type.
String _short(Object e) {
  final text = e is DioException
      ? (e.response?.data is Map
          ? '${(e.response!.data as Map)['error'] ?? e.message}'
          : 'HTTP ${e.response?.statusCode ?? '—'}')
      : e.toString();
  return text.length > 120 ? '${text.substring(0, 117)}…' : text;
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
