import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/pages/breakpoint_bar.dart';

/// What the bar says about a layout that follows a composition.
///
/// A composed layout is not inherited as a composition — it is repacked into
/// the follower's cells, because a rectangle stated on a 1600-wide canvas means
/// nothing on a four-column phone. That is the right behaviour and it is also
/// completely invisible, which is the problem: somebody who has just placed
/// forty things exactly opens the phone, finds a plain grid, and reasonably
/// concludes the editor threw the work away.
///
/// So the bar says so. These pin that it says so exactly when it is true —
/// a note that showed up on ordinary pages would be noise on every page in the
/// house, and one that never showed up would leave the original problem.

DashboardLayout _layout(
  DashboardBreakpoint b, {
  DashboardBreakpoint? derivedFrom,
  DashboardFrame? frame,
}) =>
    DashboardLayout(
      breakpoint: b,
      columns: b == DashboardBreakpoint.mobile ? 4 : 12,
      rowHeight: 120,
      gap: 12,
      placements: const [],
      derivedFrom: derivedFrom,
      frame: frame,
    );

const _frame = DashboardFrame(width: 1600, height: 900);

Future<void> _pump(
  WidgetTester tester,
  List<DashboardLayout> layouts,
  DashboardBreakpoint selected,
) async {
  await tester.pumpWidget(MaterialApp(
    theme: hcTheme(HcSkin.midnight, reduceMotion: true),
    home: Scaffold(
      body: BreakpointBar(
        layouts: layouts,
        selected: selected,
        source: DashboardBreakpoint.desktop,
        onSelect: (_) {},
        onRevert: null,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder get _note => find.textContaining('packed from it');

void main() {
  testWidgets('a follower of a composed layout is told what it inherited',
      (tester) async {
    await _pump(
        tester,
        [
          _layout(DashboardBreakpoint.desktop, frame: _frame),
          _layout(DashboardBreakpoint.mobile,
              derivedFrom: DashboardBreakpoint.desktop),
        ],
        DashboardBreakpoint.mobile);

    expect(_note, findsOneWidget);
    // Names the layout it came from, because "a composition" is not actionable
    // and "Desktop" is — that is where to go and change it.
    expect(find.textContaining('Desktop is composed'), findsOneWidget);
  });

  testWidgets('an ordinary follower is told nothing', (tester) async {
    // The common case, and by far. A note on every page in the house would be
    // noise, and noise is how a real message stops being read.
    await _pump(
        tester,
        [
          _layout(DashboardBreakpoint.desktop),
          _layout(DashboardBreakpoint.mobile,
              derivedFrom: DashboardBreakpoint.desktop),
        ],
        DashboardBreakpoint.mobile);

    expect(_note, findsNothing);
  });

  testWidgets('the composed layout itself says nothing', (tester) async {
    // Standing on the composition, there is nothing to explain: what you drew
    // is what is on screen.
    await _pump(
        tester,
        [
          _layout(DashboardBreakpoint.desktop, frame: _frame),
          _layout(DashboardBreakpoint.mobile,
              derivedFrom: DashboardBreakpoint.desktop),
        ],
        DashboardBreakpoint.desktop);

    expect(_note, findsNothing);
  });

  testWidgets('a layout somebody arranged by hand says nothing',
      (tester) async {
    // It is not following anything, so it inherited nothing and lost nothing.
    await _pump(
        tester,
        [
          _layout(DashboardBreakpoint.desktop, frame: _frame),
          _layout(DashboardBreakpoint.mobile),
        ],
        DashboardBreakpoint.mobile);

    expect(_note, findsNothing);
  });

  testWidgets('it names the layout actually followed, not the source',
      (tester) async {
    // `derivedFrom` need not be the bar's `source`. A tablet following the
    // wall must be told about the WALL, or the note points at the wrong place
    // to go and fix it.
    await _pump(
        tester,
        [
          _layout(DashboardBreakpoint.desktop),
          _layout(DashboardBreakpoint.tv, frame: _frame),
          _layout(DashboardBreakpoint.tablet,
              derivedFrom: DashboardBreakpoint.tv),
        ],
        DashboardBreakpoint.tablet);

    expect(find.textContaining('Wall is composed'), findsOneWidget);
  });
}
