import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/dashboard/layout_write.dart';
import 'package:hc_web/core/models/dashboard.dart';

DashboardWidgetPlacement _p(String id, int x, int y, int w, int h) =>
    DashboardWidgetPlacement(widgetId: id, x: x, y: y, w: w, h: h);

GridItem _i(String id, int x, int y, int w, int h) =>
    GridItem(id: id, x: x, y: y, w: w, h: h);

DashboardLayout _layout(
  DashboardBreakpoint b,
  int columns,
  List<DashboardWidgetPlacement> placements,
) =>
    DashboardLayout(
      breakpoint: b,
      columns: columns,
      rowHeight: 120,
      gap: 12,
      placements: placements,
    );

/// Four deliberately different arrangements of the same three cards — the shape
/// a house actually ends up with, and the thing the old code destroyed.
List<DashboardLayout> _fourDistinctLayouts() => [
      _layout(DashboardBreakpoint.mobile, 4, [
        _p('thermostat', 0, 0, 4, 3),
        _p('camera', 0, 3, 4, 4),
        _p('lights', 0, 7, 4, 2),
      ]),
      _layout(DashboardBreakpoint.tablet, 8, [
        _p('lights', 0, 0, 4, 3),
        _p('thermostat', 4, 0, 4, 3),
        _p('camera', 0, 3, 8, 4),
      ]),
      _layout(DashboardBreakpoint.desktop, 12, [
        _p('thermostat', 0, 0, 4, 3),
        _p('lights', 4, 0, 4, 3),
        _p('camera', 8, 0, 4, 6),
      ]),
      _layout(DashboardBreakpoint.tv, 12, [
        _p('camera', 0, 0, 12, 6),
        _p('thermostat', 0, 6, 6, 3),
        _p('lights', 6, 6, 6, 3),
      ]),
    ];

/// A placement list as a comparable value, so "unchanged" is a real assertion
/// rather than an identity check that a `copyWith` would quietly satisfy.
List<String> _shape(DashboardLayout l) =>
    [for (final p in l.placements) '${p.widgetId}@${p.x},${p.y} ${p.w}x${p.h}'];

void main() {
  group('writeArrangement', () {
    test('editing one breakpoint leaves the other three untouched', () {
      // THE regression test. Before the fix, saving the desktop arrangement
      // repacked mobile, tablet and tv from the desktop items — so a
      // hand-authored phone layout was replaced by a machine reflow, silently,
      // without the user having moved anything.
      final before = _fourDistinctLayouts();

      // Move one card on desktop, exactly as a drag would.
      final desktopItems = [
        _i('thermostat', 8, 0, 4, 3),
        _i('lights', 0, 0, 4, 3),
        _i('camera', 4, 0, 4, 6),
      ];

      final after = writeArrangement(
        layouts: before,
        items: desktopItems,
        edited: DashboardBreakpoint.desktop,
      );

      for (final b in [
        DashboardBreakpoint.mobile,
        DashboardBreakpoint.tablet,
        DashboardBreakpoint.tv,
      ]) {
        final was = before.firstWhere((l) => l.breakpoint == b);
        final now = after.firstWhere((l) => l.breakpoint == b);
        expect(_shape(now), _shape(was), reason: '$b must not have moved');
        expect(now.columns, was.columns);
        expect(now.rowHeight, was.rowHeight);
        expect(now.gap, was.gap);
      }
    });

    test('the edited breakpoint does take the new arrangement', () {
      final after = writeArrangement(
        layouts: _fourDistinctLayouts(),
        items: [
          _i('lights', 0, 0, 4, 3),
          _i('thermostat', 4, 0, 4, 3),
          _i('camera', 8, 0, 4, 6),
        ],
        edited: DashboardBreakpoint.desktop,
      );
      final desktop =
          after.firstWhere((l) => l.breakpoint == DashboardBreakpoint.desktop);
      expect(
        _shape(desktop),
        ['lights@0,0 4x3', 'thermostat@4,0 4x3', 'camera@8,0 4x6'],
      );
    });

    test('editing each breakpoint in turn only ever moves that one', () {
      for (final edited in DashboardBreakpoint.values) {
        final before = _fourDistinctLayouts();
        final items = [
          for (final p
              in before.firstWhere((l) => l.breakpoint == edited).placements)
            _i(p.widgetId, p.x, p.y, p.w, p.h),
        ];
        final after = writeArrangement(
          layouts: before,
          items: items,
          edited: edited,
        );
        for (final b in DashboardBreakpoint.values) {
          expect(
            _shape(after.firstWhere((l) => l.breakpoint == b)),
            _shape(before.firstWhere((l) => l.breakpoint == b)),
            reason: 'editing $edited changed $b',
          );
        }
      }
    });

    test('a widget added on one breakpoint reaches every other', () {
      final before = _fourDistinctLayouts();
      final after = writeArrangement(
        layouts: before,
        items: [
          _i('thermostat', 0, 0, 4, 3),
          _i('lights', 4, 0, 4, 3),
          _i('camera', 8, 0, 4, 6),
          _i('doorbell', 0, 3, 4, 3),
        ],
        edited: DashboardBreakpoint.desktop,
      );
      for (final l in after) {
        expect(
          l.placements.map((p) => p.widgetId),
          contains('doorbell'),
          reason: '${l.breakpoint} is missing the new widget',
        );
      }
    });

    test('a widget removed on one breakpoint is removed from every other', () {
      final after = writeArrangement(
        layouts: _fourDistinctLayouts(),
        items: [
          _i('thermostat', 0, 0, 4, 3),
          _i('lights', 4, 0, 4, 3),
        ],
        edited: DashboardBreakpoint.desktop,
      );
      for (final l in after) {
        expect(
          l.placements.map((p) => p.widgetId),
          isNot(contains('camera')),
          reason: '${l.breakpoint} still references a deleted widget',
        );
      }
    });

    test('adding a widget does not move the cards already placed', () {
      // Reconciliation must be additive. If placing a new card reflowed the
      // rest, this fix would just be the old bug on a longer fuse.
      final before = _fourDistinctLayouts();
      final after = writeArrangement(
        layouts: before,
        items: [
          _i('thermostat', 0, 0, 4, 3),
          _i('lights', 4, 0, 4, 3),
          _i('camera', 8, 0, 4, 6),
          _i('doorbell', 0, 6, 4, 3),
        ],
        edited: DashboardBreakpoint.desktop,
      );
      final mobileBefore =
          before.firstWhere((l) => l.breakpoint == DashboardBreakpoint.mobile);
      final mobileAfter =
          after.firstWhere((l) => l.breakpoint == DashboardBreakpoint.mobile);
      for (final p in mobileBefore.placements) {
        final now =
            mobileAfter.placements.firstWhere((q) => q.widgetId == p.widgetId);
        expect([now.x, now.y, now.w, now.h], [p.x, p.y, p.w, p.h],
            reason: '${p.widgetId} moved on mobile when doorbell was added');
      }
    });

    test('every layout stays legal for its own column count', () {
      final after = writeArrangement(
        layouts: _fourDistinctLayouts(),
        items: [
          _i('thermostat', 0, 0, 4, 3),
          _i('lights', 4, 0, 4, 3),
          _i('camera', 8, 0, 4, 6),
          _i('wide', 0, 6, 12, 3),
        ],
        edited: DashboardBreakpoint.desktop,
      );
      for (final l in after) {
        final items = [
          for (final p in l.placements) _i(p.widgetId, p.x, p.y, p.w, p.h),
        ];
        expect(
          GridEngine(columns: l.columns).isLegal(items),
          isTrue,
          reason: '${l.breakpoint} is illegal at ${l.columns} columns',
        );
      }
    });

    test('every layout carries every widget, and nothing else', () {
      // What core 400s on, asserted directly: placements and widgets are the
      // same set, on every breakpoint.
      final after = writeArrangement(
        layouts: _fourDistinctLayouts(),
        items: [
          _i('thermostat', 0, 0, 4, 3),
          _i('doorbell', 4, 0, 4, 3),
        ],
        edited: DashboardBreakpoint.tablet,
      );
      for (final l in after) {
        expect(
          l.placements.map((p) => p.widgetId).toSet(),
          {'thermostat', 'doorbell'},
          reason: '${l.breakpoint} widget set diverged',
        );
      }
    });
  });

  group('reconcileWidgetSet', () {
    test('returns the same object when nothing changed', () {
      final l = _layout(DashboardBreakpoint.mobile, 4, [
        _p('a', 0, 0, 4, 2),
        _p('b', 0, 2, 4, 2),
      ]);
      final out =
          reconcileWidgetSet(l, [_i('a', 0, 0, 4, 2), _i('b', 0, 2, 4, 2)]);
      expect(identical(out, l), isTrue,
          reason: 'an unchanged layout should not even be rebuilt');
    });

    test('repairs a zero column count without touching placements', () {
      final l = _layout(DashboardBreakpoint.desktop, 0, [_p('a', 0, 0, 4, 2)]);
      final out = reconcileWidgetSet(l, [_i('a', 0, 0, 4, 2)]);
      expect(out.columns, kDefaultColumns);
      expect(_shape(out), _shape(l));
    });
  });
}
