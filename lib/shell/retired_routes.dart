/// URLs that used to work and must keep working.
///
/// Its own file rather than a helper inside `app.dart` for a practical reason:
/// `app.dart` imports the whole application, which drags in web-only code that
/// will not compile under the VM test runner — so anything living there cannot
/// be tested directly. A redirect is runtime behaviour the compiler never
/// checks, and these are the URLs sitting in bookmarks and pinned on wall
/// panels, so being untestable was not an option.
library;

/// Where a retired `/dashboards…` URL should land, or null to carry on.
String? retiredDashboardRoute(String path, {String? query}) {
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty || parts.first != 'dashboards') return null;

  // `/dashboards` itself still exists — it is the list, and the only surface
  // with import, templates and reload-from-disk. Retiring it would drop three
  // capabilities with nothing to replace them.
  if (parts.length == 1) return null;

  // Creating a page is an action now (hub launcher → New page), not a URL you
  // can visit, so there is nothing to send `new/edit` to but the list.
  if (parts[1] == 'new') return '/dashboards';

  // `/dashboards/:id` and `/dashboards/:id/edit` both land on the one surface:
  // /pages is view and edit in a mode, so the distinction has no target left.
  // Arriving in view mode is the safe half of that.
  //
  // The query rides along. `room_field` sends `?room=` so one room page can be
  // about the room you opened it for, and a redirect that dropped it turned
  // every room cell into the same page about the same room.
  final tail = (query == null || query.isEmpty) ? '' : '?$query';
  return '/pages/${parts[1]}$tail';
}
