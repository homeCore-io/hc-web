import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ManagePage is a menu of routes, and nothing checks that the routes exist.
///
/// Notifications, Data and Maintenance shipped as three finished screens —
/// 1,214 lines, with their own passing tests — that no one could open. The
/// pages were written, ManagePage listed them, and `app.dart` routed none of
/// them, so every tap dead-ended on go_router's default error page for a week.
///
/// Nothing else catches this. A page nothing imports is still valid Dart, so
/// `flutter analyze` is happy; the screens' own widget tests pump them
/// directly and never go through the router; and the router has no
/// `errorBuilder`, so the failure is a raw framework page rather than anything
/// that looks like a bug report.
///
/// So compare the two structures the way the Rust side compares a descriptor
/// against its schema: read both files, and report what one names that the
/// other never defines.
void main() {
  test('every route ManagePage links is a route the app defines', () {
    String read(String p) => File(p).readAsStringSync();

    final linked = RegExp("route: '([^']+)'")
        .allMatches(read('lib/features/manage/manage_page.dart'))
        .map((m) => m.group(1)!)
        .toSet();

    final defined = RegExp("path: '([^']+)'")
        .allMatches(read('lib/app.dart'))
        .map((m) => m.group(1)!)
        .toSet();

    // Administration's routes are generated from its section list rather than
    // written out in app.dart, so read them from where they are declared.
    // Skipping this would let the whole of Administration go unchecked.
    //
    // `\s*` is load-bearing: dart format wraps the longer constructors onto the
    // next line, and the first version of this regex silently matched seven of
    // nine — reporting two real routes as missing. Partial parsing is the
    // failure mode of reading source as text, so it is asserted against below
    // rather than left to be noticed.
    final shell = read('lib/features/manage/manage_shell.dart');
    // A section's route is `/admin/<id>` unless it declares `path:` — the
    // house sections keep the top-level paths they already ship with.
    final adminSections = <String>{};
    for (final m
        in RegExp(r"ManageSection\(\s*'([a-z-]+)'[^)]*?\)").allMatches(shell)) {
      final decl = m.group(0)!;
      final explicit = RegExp(r"path:\s*'([^']+)'").firstMatch(decl);
      adminSections
          .add(explicit != null ? explicit.group(1)! : '/admin/${m.group(1)!}');
    }
    // Every `ManageSection(` that is not the constructor declaration itself.
    // Counted by subtraction rather than a lookahead: the constructor's
    // parameters sit on the next line, and `\s*(?!this\.)` happily matches the
    // whitespace before them — which counted the declaration as a section and
    // made this assertion fail by exactly one.
    final total = RegExp(r'ManageSection\(').allMatches(shell).length;
    final ctor = RegExp(r'ManageSection\(\s*this\.').allMatches(shell).length;
    expect(
      adminSections,
      hasLength(total - ctor),
      reason: 'parsed fewer sections than manage_shell.dart declares',
    );
    // The invariant this actually guards now: the rail is a hand-written list
    // and the routes are hand-written too, so a section can be added to one
    // and not the other. A rail entry with no route is a dead menu row — the
    // exact bug this file was written for, one level up.
    expect(
      adminSections.difference(defined),
      isEmpty,
      reason: 'manage_shell.dart lists these sections and app.dart defines no '
          'route for them; the rail entry will dead-end',
    );
    defined.addAll(adminSections);

    // If either regex stops matching — someone reformats the entries, or
    // switches to a route-name constant — this test would pass by finding
    // nothing to check. Fail loudly instead.
    expect(linked, isNotEmpty,
        reason: 'no entries parsed out of manage_page.dart — fix this test');
    expect(defined, isNotEmpty,
        reason: 'no routes parsed out of app.dart — fix this test');

    expect(
      linked.difference(defined),
      isEmpty,
      reason: 'ManagePage links these paths and app.dart defines no route for '
          'them; the menu row will dead-end on the router error page',
    );

    // Manage says the same thing twice — a sidebar and a landing pane — and a
    // new page has to be added to both. `/admin/files` shipped in the landing
    // pane alone and was invisible in the rail until it was spotted on the
    // live box: routed, tested, reachable by URL, and absent from the
    // navigation everyone actually uses. Nothing above catches that, because
    // both lists were internally consistent.
    //
    // Asserted one way only. The rail carries Appearance and Plugin runtimes,
    // which the landing pane has never listed; that asymmetry predates this
    // and is a decision to make during the cleanup noted in webPlan.md, not a
    // bug to fail on now.
    expect(
      linked.difference(adminSections),
      isEmpty,
      reason: 'ManagePage offers these and the rail does not, so the page is '
          'invisible from every screen except the Manage landing page',
    );
  });

  test('paths that moved still resolve', () {
    // Every one of these shipped as a real route and is in bookmarks and the
    // command palette. They are redirects now, and a redirect is exactly the
    // kind of line that looks like dead weight to someone tidying up — so
    // name them here, where deleting one fails.
    final app = File('lib/app.dart').readAsStringSync();
    const moved = {
      '/config': '/admin/config',
      '/notifications': '/admin/notifications',
      '/data': '/admin/data',
      '/maintenance': '/admin/maintenance',
      '/admin/areas': '/areas',
    };

    for (final entry in moved.entries) {
      // `[\s\S]{0,120}?` and not `[^)]*`: the redirect is written
      // `redirect: (_, __) => '/x'`, and a negated-paren class stops at the
      // lambda's own closing paren, never reaching the target.
      final route = RegExp(
        "path:\\s*'${RegExp.escape(entry.key)}'[\\s\\S]{0,120}?"
        "redirect:[\\s\\S]{0,60}?'${RegExp.escape(entry.value)}'",
      );
      expect(
        route.hasMatch(app),
        isTrue,
        reason: '${entry.key} no longer redirects to ${entry.value}',
      );
    }
  });
}
