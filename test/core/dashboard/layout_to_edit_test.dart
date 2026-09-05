import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/breakpoints.dart';
import 'package:hc_web/core/models/dashboard.dart';

/// **A page with one layout could not be saved from the designer.**
///
/// `availableBreakpoint` answers *which layout to borrow from*, and the
/// borrowing returned that layout as it stood — still stamped with the
/// breakpoint it came from. Its caller appends the result to a list it has just
/// checked for the breakpoint it wanted, so opening the designer on a page with
/// only a desktop layout added a **second desktop layout**. Core refused every
/// save with "duplicate layout breakpoint 'Desktop'", and the app showed Dio's
/// boilerplate instead of that sentence, so it looked like nothing at all.

DashboardLayout layout(DashboardBreakpoint b) => DashboardLayout(
      breakpoint: b,
      columns: 12,
      rowHeight: 120,
      gap: 12,
      placements: const [
        DashboardWidgetPlacement(widgetId: 'a', x: 0, y: 0, w: 4, h: 2),
      ],
    );

DashboardDefinition page(List<DashboardLayout> layouts) => DashboardDefinition(
      id: 'p',
      name: 'Page',
      ownerUserId: 'me',
      description: null,
      visibility: DashboardVisibility.private,
      tags: const [],
      isDefault: false,
      icon: 'home',
      widgets: const [],
      layouts: layouts,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

DashboardLayout edit(DashboardDefinition d, DashboardBreakpoint b) =>
    layoutToEdit(d, b,
        defaultColumns: 12, defaultRowHeight: 120, defaultGap: 12);

void main() {
  test('a borrowed layout takes the breakpoint it was asked for', () {
    final d = page([layout(DashboardBreakpoint.desktop)]);
    final got = edit(d, DashboardBreakpoint.tablet);
    expect(got.breakpoint, DashboardBreakpoint.tablet);
    expect(got.derivedFrom, DashboardBreakpoint.desktop,
        reason: 'borrowed is exactly what derived means');
  });

  test('and the page it lands in still has one layout per breakpoint', () {
    // The shape of the original bug: the caller appends when the breakpoint is
    // missing, so a result carrying the wrong breakpoint is a duplicate.
    final d = page([layout(DashboardBreakpoint.desktop)]);
    for (final wanted in DashboardBreakpoint.values) {
      final layouts = [...d.layouts];
      if (!layouts.any((l) => l.breakpoint == wanted)) {
        layouts.add(edit(d, wanted));
      }
      final seen = <DashboardBreakpoint>{};
      for (final l in layouts) {
        expect(seen.add(l.breakpoint), isTrue,
            reason: 'duplicate ${l.breakpoint} after asking for $wanted');
      }
    }
  });

  test('its own layout comes back untouched', () {
    // Not re-stamped and not marked derived: a breakpoint that has its own
    // arrangement is not following anything.
    final d = page([layout(DashboardBreakpoint.desktop)]);
    final got = edit(d, DashboardBreakpoint.desktop);
    expect(got.breakpoint, DashboardBreakpoint.desktop);
    expect(got.derivedFrom, isNull);
    expect(got.placements, hasLength(1));
  });

  test('a page with no layouts gets an empty one of the right shape', () {
    final got = edit(page(const []), DashboardBreakpoint.mobile);
    expect(got.breakpoint, DashboardBreakpoint.mobile);
    expect(got.columns, 4, reason: 'a phone is four columns');
    expect(got.placements, isEmpty);
    expect(got.derivedFrom, isNull);
  });
}
