import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/dashboard/layout_write.dart';
import 'package:hc_web/core/models/dashboard.dart';

/// The derive/override model.
///
/// `writeArrangement` already refuses to touch layouts it was not asked to
/// edit. Deriving is the deliberate opt-out from that refusal: a layout that
/// names `derivedFrom` is *asking* to follow another one, and stops asking the
/// moment a person edits it. What is pinned here is that the opt-out stays
/// explicit in both directions — nothing recomputes a layout that did not
/// declare it, and nothing keeps recomputing one after a person has taken it
/// over.

DashboardWidgetPlacement _p(String id, int x, int y, int w, int h) =>
    DashboardWidgetPlacement(widgetId: id, x: x, y: y, w: w, h: h);

GridItem _i(String id, int x, int y, int w, int h) =>
    GridItem(id: id, x: x, y: y, w: w, h: h);

DashboardLayout _layout(
  DashboardBreakpoint b,
  int columns,
  List<DashboardWidgetPlacement> placements, {
  DashboardBreakpoint? derivedFrom,
  List<GroupBox> groups = const [],
}) =>
    DashboardLayout(
      breakpoint: b,
      columns: columns,
      rowHeight: 120,
      gap: 12,
      placements: placements,
      derivedFrom: derivedFrom,
      groups: groups,
    );

List<String> _shape(DashboardLayout l) =>
    [for (final p in l.placements) '${p.widgetId}@${p.x},${p.y} ${p.w}x${p.h}'];

/// Desktop authored, tablet and tv following it, mobile taken over by hand.
List<DashboardLayout> _mixed() => [
      _layout(DashboardBreakpoint.mobile, 4, [
        _p('c', 0, 0, 4, 2),
        _p('b', 0, 2, 4, 2),
        _p('a', 0, 4, 4, 2),
      ]),
      _layout(
          DashboardBreakpoint.tablet,
          8,
          [
            _p('a', 0, 0, 4, 3),
            _p('b', 4, 0, 4, 3),
            _p('c', 0, 3, 4, 3),
          ],
          derivedFrom: DashboardBreakpoint.desktop),
      _layout(DashboardBreakpoint.desktop, 12, [
        _p('a', 0, 0, 4, 3),
        _p('b', 4, 0, 4, 3),
        _p('c', 8, 0, 4, 3),
      ]),
      _layout(
          DashboardBreakpoint.tv,
          12,
          [
            _p('a', 0, 0, 4, 3),
            _p('b', 4, 0, 4, 3),
            _p('c', 8, 0, 4, 3),
          ],
          derivedFrom: DashboardBreakpoint.desktop),
    ];

final _newDesktop = [
  _i('c', 0, 0, 6, 3),
  _i('a', 6, 0, 6, 3),
  _i('b', 0, 3, 12, 2),
];

void main() {
  group('derived layouts follow the one they name', () {
    test('editing desktop recomputes tablet and tv', () {
      final after = writeArrangement(
        layouts: _mixed(),
        items: _newDesktop,
        edited: DashboardBreakpoint.desktop,
      );
      final tablet =
          after.firstWhere((l) => l.breakpoint == DashboardBreakpoint.tablet);
      final tv =
          after.firstWhere((l) => l.breakpoint == DashboardBreakpoint.tv);

      // Reading order of the new desktop arrangement: c, a, then b below.
      expect(
          tablet.placements.map((p) => p.widgetId).toList(), ['c', 'a', 'b']);
      expect(tv.placements.map((p) => p.widgetId).toList(), ['c', 'a', 'b']);
      // And they are still derived — recomputing does not take them over.
      expect(tablet.derivedFrom, DashboardBreakpoint.desktop);
      expect(tv.derivedFrom, DashboardBreakpoint.desktop);
    });

    test('a derived layout is packed for its own column count', () {
      final after = writeArrangement(
        layouts: _mixed(),
        items: _newDesktop,
        edited: DashboardBreakpoint.desktop,
      );
      final tablet =
          after.firstWhere((l) => l.breakpoint == DashboardBreakpoint.tablet);
      expect(tablet.columns, 8);
      for (final p in tablet.placements) {
        expect(p.x + p.w, lessThanOrEqualTo(8),
            reason: '${p.widgetId} overflows an 8-column grid');
      }
      // The 12-wide card is clamped to the grid, not dropped.
      expect(tablet.placements.map((p) => p.widgetId), contains('b'));
    });

    test('the overridden layout is left completely alone', () {
      final before = _mixed();
      final after = writeArrangement(
        layouts: before,
        items: _newDesktop,
        edited: DashboardBreakpoint.desktop,
      );
      final was =
          before.firstWhere((l) => l.breakpoint == DashboardBreakpoint.mobile);
      final now =
          after.firstWhere((l) => l.breakpoint == DashboardBreakpoint.mobile);
      expect(_shape(now), _shape(was));
      expect(now.derivedFrom, isNull);
    });

    test('a layout derived from something else is not recomputed', () {
      // tv follows mobile here, so editing desktop must not reach it.
      final before = [
        _layout(DashboardBreakpoint.desktop, 12, [_p('a', 0, 0, 4, 3)]),
        _layout(DashboardBreakpoint.mobile, 4, [_p('a', 0, 0, 4, 2)]),
        _layout(DashboardBreakpoint.tv, 12, [_p('a', 8, 4, 4, 3)],
            derivedFrom: DashboardBreakpoint.mobile),
      ];
      final after = writeArrangement(
        layouts: before,
        items: [_i('a', 0, 0, 12, 6)],
        edited: DashboardBreakpoint.desktop,
      );
      final tv =
          after.firstWhere((l) => l.breakpoint == DashboardBreakpoint.tv);
      expect(_shape(tv), ['a@8,4 4x3']);
      expect(tv.derivedFrom, DashboardBreakpoint.mobile);
    });
  });

  group('editing a derived layout takes it over', () {
    test('the edited breakpoint stops being derived', () {
      final after = writeArrangement(
        layouts: _mixed(),
        items: [_i('a', 0, 0, 8, 3), _i('b', 0, 3, 8, 3), _i('c', 0, 6, 8, 3)],
        edited: DashboardBreakpoint.tablet,
      );
      final tablet =
          after.firstWhere((l) => l.breakpoint == DashboardBreakpoint.tablet);
      expect(tablet.derivedFrom, isNull,
          reason: 'a person just arranged this one');
      expect(
          tablet.placements.map((p) => p.widgetId).toList(), ['a', 'b', 'c']);
    });

    test('and desktop edits no longer reach it', () {
      // The whole point of the override: take tablet over, then edit desktop,
      // and tablet must hold still. This is the two rules composing, which is
      // where a model like this usually goes wrong.
      var layouts = writeArrangement(
        layouts: _mixed(),
        items: [_i('a', 0, 0, 8, 3), _i('b', 0, 3, 8, 3), _i('c', 0, 6, 8, 3)],
        edited: DashboardBreakpoint.tablet,
      );
      final taken =
          layouts.firstWhere((l) => l.breakpoint == DashboardBreakpoint.tablet);

      layouts = writeArrangement(
        layouts: layouts,
        items: _newDesktop,
        edited: DashboardBreakpoint.desktop,
      );
      final now =
          layouts.firstWhere((l) => l.breakpoint == DashboardBreakpoint.tablet);
      expect(_shape(now), _shape(taken));
      expect(now.derivedFrom, isNull);
    });

    test('editing an authored layout leaves it authored', () {
      final after = writeArrangement(
        layouts: _mixed(),
        items: [_i('a', 0, 0, 4, 2)],
        edited: DashboardBreakpoint.mobile,
      );
      expect(
        after
            .firstWhere((l) => l.breakpoint == DashboardBreakpoint.mobile)
            .derivedFrom,
        isNull,
      );
    });
  });

  group('revertToDerived', () {
    test('reproduces exactly what deriving would have produced', () {
      // The guarantee that makes revert safe to offer: it is not an undo stack,
      // it is the same pure function the derived layouts already run.
      final overridden = _mixed()
          .firstWhere((l) => l.breakpoint == DashboardBreakpoint.mobile);

      final reverted =
          revertToDerived(overridden, DashboardBreakpoint.desktop, _newDesktop);
      final asIfAlwaysDerived = deriveLayout(
        overridden.copyWith(derivedFrom: DashboardBreakpoint.desktop),
        _newDesktop,
      );

      expect(_shape(reverted), _shape(asIfAlwaysDerived));
      expect(reverted.derivedFrom, DashboardBreakpoint.desktop);
    });

    test('a reverted layout then follows desktop again', () {
      var layouts = _mixed();
      final desktopItems = _newDesktop;

      final mobile =
          layouts.firstWhere((l) => l.breakpoint == DashboardBreakpoint.mobile);
      layouts = [
        for (final l in layouts)
          if (l.breakpoint == DashboardBreakpoint.mobile)
            revertToDerived(mobile, DashboardBreakpoint.desktop, desktopItems)
          else
            l,
      ];

      final next = [
        _i('b', 0, 0, 12, 4),
        _i('a', 0, 4, 6, 3),
        _i('c', 6, 4, 6, 3),
      ];
      layouts = writeArrangement(
        layouts: layouts,
        items: next,
        edited: DashboardBreakpoint.desktop,
      );
      final now =
          layouts.firstWhere((l) => l.breakpoint == DashboardBreakpoint.mobile);
      expect(now.placements.map((p) => p.widgetId).toList(), ['b', 'a', 'c']);
      expect(now.derivedFrom, DashboardBreakpoint.desktop);
    });
  });

  group('the widget set still holds across every case', () {
    test('a removal reaches every layout, following or not', () {
      final after = writeArrangement(
        layouts: _mixed(),
        // 'b' dropped, 'd' added.
        items: [_i('a', 0, 0, 4, 3), _i('c', 4, 0, 4, 3), _i('d', 8, 0, 4, 3)],
        edited: DashboardBreakpoint.desktop,
      );
      for (final l in after) {
        expect(
          l.placements.map((p) => p.widgetId),
          isNot(contains('b')),
          reason: '${l.breakpoint} still references a deleted widget',
        );
      }
    });

    test('an addition reaches following layouts but not hand-made ones', () {
      // The asymmetry is the point. A following layout has no arrangement of
      // its own to protect, so a new card just appears. A hand-made one does,
      // so it is asked rather than reflowed.
      final after = writeArrangement(
        layouts: _mixed(),
        items: [_i('a', 0, 0, 4, 3), _i('c', 4, 0, 4, 3), _i('d', 8, 0, 4, 3)],
        edited: DashboardBreakpoint.desktop,
      );
      for (final b in [DashboardBreakpoint.tablet, DashboardBreakpoint.tv]) {
        expect(
          after
              .firstWhere((l) => l.breakpoint == b)
              .placements
              .map((p) => p.widgetId),
          contains('d'),
          reason: '$b follows desktop and should have gained the card',
        );
      }
      expect(
        after
            .firstWhere((l) => l.breakpoint == DashboardBreakpoint.mobile)
            .placements
            .map((p) => p.widgetId),
        isNot(contains('d')),
        reason: 'mobile was arranged by hand and must not be reflowed',
      );
    });

    test('a card left off a hand-made layout stays off across saves', () {
      // Without this, "leave it off the phone" is undone by the next save and
      // the choice is not a choice at all. Repeated because the failure mode is
      // a slow one: the card creeps back on some later save, not the first.
      var layouts = [
        _layout(DashboardBreakpoint.desktop, 12, [
          _p('a', 0, 0, 4, 3),
          _p('b', 4, 0, 4, 3),
        ]),
        // Deliberately without 'b' — someone left it off the phone.
        _layout(DashboardBreakpoint.mobile, 4, [_p('a', 0, 0, 4, 2)]),
      ];
      final items = [_i('a', 0, 0, 4, 3), _i('b', 4, 0, 4, 3)];
      for (var i = 0; i < 5; i++) {
        layouts = writeArrangement(
          layouts: layouts,
          items: items,
          edited: DashboardBreakpoint.desktop,
        );
      }
      final mobile =
          layouts.firstWhere((l) => l.breakpoint == DashboardBreakpoint.mobile);
      expect(mobile.placements.map((p) => p.widgetId), isNot(contains('b')),
          reason: 'b was left off the phone and must stay off');
      expect(mobile.placements.map((p) => p.widgetId), contains('a'),
          reason: 'and everything else on the phone is untouched');
    });

    test('every layout stays legal for its own column count', () {
      final after = writeArrangement(
        layouts: _mixed(),
        items: _newDesktop,
        edited: DashboardBreakpoint.desktop,
      );
      for (final l in after) {
        final items = [
          for (final p in l.placements) _i(p.widgetId, p.x, p.y, p.w, p.h),
        ];
        expect(GridEngine(columns: l.columns).isLegal(items), isTrue,
            reason: '${l.breakpoint} is illegal at ${l.columns} columns');
      }
    });
  });

  group('the model carries the flag', () {
    test('derivedFrom round-trips through JSON', () {
      final l = _layout(DashboardBreakpoint.tv, 12, [_p('a', 0, 0, 4, 3)],
          derivedFrom: DashboardBreakpoint.desktop);
      final back = DashboardLayout.fromJson(l.toJson());
      expect(back.derivedFrom, DashboardBreakpoint.desktop);
      expect(back.isDerived, isTrue);
    });

    test('an authored layout omits the key rather than writing null', () {
      final l = _layout(DashboardBreakpoint.tv, 12, [_p('a', 0, 0, 4, 3)]);
      expect(l.toJson().containsKey('derived_from'), isFalse);
    });

    test('a breakpoint this build does not know reads as authored', () {
      // Not coerced to desktop. Deriving from the wrong source would silently
      // rearrange a layout; reading it as authored just leaves it alone.
      final back = DashboardLayout.fromJson({
        'breakpoint': 'desktop',
        'columns': 12,
        'row_height': 120.0,
        'gap': 12.0,
        'placements': const [],
        'derived_from': 'watch',
      });
      expect(back.derivedFrom, isNull);
    });

    test('a layout from before the field existed reads as authored', () {
      final back = DashboardLayout.fromJson({
        'breakpoint': 'desktop',
        'columns': 12,
        'row_height': 120.0,
        'gap': 12.0,
        'placements': [
          {'widget_id': 'a', 'x': 0, 'y': 0, 'w': 4, 'h': 3}
        ],
      });
      expect(back.derivedFrom, isNull);
      expect(back.isDerived, isFalse);
    });

    test('copyWith can actually clear it', () {
      // Null is a meaningful value here, so the usual `?? this.field` idiom
      // would make "take this layout over" a silent no-op.
      final derived = _layout(DashboardBreakpoint.tv, 12, const [],
          derivedFrom: DashboardBreakpoint.desktop);
      expect(derived.copyWith(derivedFrom: null).derivedFrom, isNull);
      expect(derived.copyWith(columns: 8).derivedFrom,
          DashboardBreakpoint.desktop);
    });
  });

  group('containers on a derived layout', () {
    // A derived layout has no opinions of its own. It was already true of the
    // arrangement; it has to be true of the containers too, or a group given a
    // body on the desktop shows up as a bare group on the phone that is
    // explicitly following the desktop.
    const styled = GroupBox(
      path: 'Wall',
      rect: DashboardRect(x: 100, y: 40, w: 600, h: 300),
      padding: 16,
      radius: 18,
      clip: true,
    );

    test('a following layout takes the source containers', () {
      final out = writeArrangement(
        layouts: [
          _layout(DashboardBreakpoint.desktop, 12, [_p('a', 0, 0, 4, 2)],
              groups: const [styled]),
          _layout(DashboardBreakpoint.mobile, 4, const [],
              derivedFrom: DashboardBreakpoint.desktop),
        ],
        items: [const GridItem(id: 'a', x: 0, y: 0, w: 4, h: 2)],
        edited: DashboardBreakpoint.desktop,
      );
      final mobile =
          out.firstWhere((l) => l.breakpoint == DashboardBreakpoint.mobile);
      expect(mobile.groups.map((g) => g.path), ['Wall']);
      expect(mobile.groupBox('Wall')!.padding, 16);
      expect(mobile.groupBox('Wall')!.clip, isTrue);
    });

    test('but NOT the box the source drew', () {
      // The rect is in the source's frame units. A box positioned for a
      // 1600-wide canvas means nothing on a four-column phone, and carrying it
      // would put the container somewhere its members are not — the same
      // reason the placements' rectangles are dropped.
      final out = writeArrangement(
        layouts: [
          _layout(DashboardBreakpoint.desktop, 12, [_p('a', 0, 0, 4, 2)],
              groups: const [styled]),
          _layout(DashboardBreakpoint.mobile, 4, const [],
              derivedFrom: DashboardBreakpoint.desktop),
        ],
        items: [const GridItem(id: 'a', x: 0, y: 0, w: 4, h: 2)],
        edited: DashboardBreakpoint.desktop,
      );
      final mobile =
          out.firstWhere((l) => l.breakpoint == DashboardBreakpoint.mobile);
      expect(mobile.groupBox('Wall')!.rect, isNull,
          reason: 'a derived container fits its own members');
    });

    test('an authored layout keeps its own containers', () {
      // The whole rule this file exists for, applied to containers: an editor
      // writes back only the region it read. Styling a group on the desktop
      // must not reach into a phone layout somebody arranged by hand.
      final out = writeArrangement(
        layouts: [
          _layout(DashboardBreakpoint.desktop, 12, [_p('a', 0, 0, 4, 2)],
              groups: const [styled]),
          _layout(DashboardBreakpoint.mobile, 4, [_p('a', 0, 0, 4, 2)],
              groups: const [GroupBox(path: 'Wall', padding: 4)]),
        ],
        items: [const GridItem(id: 'a', x: 0, y: 0, w: 4, h: 2)],
        edited: DashboardBreakpoint.desktop,
      );
      final mobile =
          out.firstWhere((l) => l.breakpoint == DashboardBreakpoint.mobile);
      expect(mobile.groupBox('Wall')!.padding, 4);
    });

    test('a group with no body is not carried across as a row', () {
      // Same rule the save path follows: naming a group must not make every
      // layout carry an entry that changes nothing.
      final out = writeArrangement(
        layouts: [
          _layout(DashboardBreakpoint.desktop, 12, [_p('a', 0, 0, 4, 2)],
              groups: const [GroupBox(path: 'Wall')]),
          _layout(DashboardBreakpoint.mobile, 4, const [],
              derivedFrom: DashboardBreakpoint.desktop),
        ],
        items: [const GridItem(id: 'a', x: 0, y: 0, w: 4, h: 2)],
        edited: DashboardBreakpoint.desktop,
      );
      expect(
          out
              .firstWhere((l) => l.breakpoint == DashboardBreakpoint.mobile)
              .groups,
          isEmpty);
    });
  });
}
