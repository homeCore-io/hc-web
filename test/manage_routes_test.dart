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
    final shell = read('lib/features/admin/administration_shell.dart');
    final adminSections = RegExp(r"AdminSection\(\s*'([a-z-]+)'")
        .allMatches(shell)
        .map((m) => '/admin/${m.group(1)!}')
        .toSet();
    // Every `AdminSection(` that is not the constructor declaration itself.
    final declared =
        RegExp(r'AdminSection\(\s*(?!this\.)').allMatches(shell).length;
    expect(
      adminSections,
      hasLength(declared),
      reason: 'parsed fewer sections than administration_shell.dart declares',
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
  });
}
