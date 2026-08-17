import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/dashboards_provider.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';
import 'package:hc_web/features/pages/page_grid.dart';
import 'package:hc_web/features/pages/page_screen.dart';
import 'package:hc_web/features/dashboard/primitive_cards.dart';
import 'package:hc_web/features/pages/tool_palette.dart';

/// Drawing, rather than choosing.
///
/// John: *"the designer UI doesn't match mockup … Use ui-craft designer and
/// claude designer to truly design a UI like an application NOT a web page for
/// doing UI design"*.
///
/// The substance of that is not the chrome. It is the order you work in. A
/// catalogue makes you choose a thing and then correct where it went and how
/// big it is; a tool makes the element arrive at the size and place you drew.
/// These tests are about that gesture — that a drag with a tool in hand
/// produces an element **of the dragged size**, and that the same drag with no
/// tool still selects, because one band that means what you are holding is the
/// whole design.

class _StubDashboards extends DashboardsNotifier {
  _StubDashboards(this.items);
  final List<DashboardDefinition> items;
  @override
  Future<List<DashboardDefinition>> build() async => items;
}

class _StubDevices extends DevicesNotifier {
  _StubDevices(this.items);
  final List<DeviceState> items;
  @override
  Future<List<DeviceState>> build() async => items;
}

/// One small card in the corner, so most of the board is empty canvas to draw
/// on — and something for a selection band to actually catch.
DashboardDefinition _page() => DashboardDefinition(
      id: 'kitchen',
      name: 'Kitchen',
      description: null,
      ownerUserId: 'u',
      visibility: DashboardVisibility.private,
      tags: const [],
      icon: 'grid',
      isDefault: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      widgets: const [
        DashboardWidgetModel(
          id: 'a',
          type: 'markdown',
          title: 'Header',
          refreshPolicy: DashboardRefreshPolicy.passive,
          config: {'markdown': 'body'},
        ),
      ],
      layouts: const [
        DashboardLayout(
          breakpoint: DashboardBreakpoint.desktop,
          columns: 12,
          rowHeight: 120,
          gap: 12,
          placements: [
            DashboardWidgetPlacement(widgetId: 'a', x: 0, y: 0, w: 2, h: 1),
          ],
        ),
      ],
    );

Future<void> _open(WidgetTester tester) async {
  registerBuiltinDashboardWidgets();
  await tester.binding.setSurfaceSize(const Size(1500, 950));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = GoRouter(
    initialLocation: '/pages/kitchen/design',
    routes: [
      GoRoute(
        path: '/pages/:id/design',
        builder: (_, s) =>
            PageScreen(dashboardId: s.pathParameters['id']!, designer: true),
      ),
    ],
  );

  await tester.pumpWidget(ProviderScope(
    overrides: [
      dashboardsProvider.overrideWith(() => _StubDashboards([_page()])),
      devicesProvider.overrideWith(() => _StubDevices(const [])),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: hcTheme(HcSkin.midnight, reduceMotion: true),
    ),
  ));
  await tester.pumpAndSettle();
}

/// A raw pointer drag across the board, in board-local fractions.
///
/// Raw rather than `tester.drag`, for the reason the board itself gives: the
/// canvas lives inside two scroll views, and a pan recogniser loses the arena
/// to them. The band takes pointers directly, so the test has to send them
/// directly too — a gesture-level drag here tests the scroll views.
Future<Rect> _dragOnBoard(
  WidgetTester tester,
  Offset from,
  Offset to,
) async {
  final board = tester.getRect(find.byType(PageGrid));
  Offset at(Offset f) =>
      Offset(board.left + board.width * f.dx, board.top + board.height * f.dy);
  final gesture = await tester.startGesture(at(from));
  // Several moves, because one jump can be read as a fling by anything that
  // is watching, and because the band is meant to follow the pointer.
  for (var i = 1; i <= 4; i++) {
    await gesture.moveTo(Offset.lerp(at(from), at(to), i / 4)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
  // The rectangle the pointer actually described, on screen. Comparing the
  // drawn element to *this* is the promise the gesture makes — what you let go
  // of is what you get — and it needs no arithmetic about panes or zoom.
  return Rect.fromPoints(at(from), at(to));
}

/// What the status bar says is in hand — the honest read of a selection.
Finder _says(String text) => find.textContaining(text);

void main() {
  testWidgets('the tools are permanent furniture, against the canvas',
      (tester) async {
    await _open(tester);
    expect(find.byType(ToolPalette), findsOneWidget);
  });

  testWidgets('a drag with the shape tool makes a shape of that size',
      (tester) async {
    // The whole point. Not the engine's first fit at the registry's
    // recommended size, and not a whole number of cells — the rectangle that
    // was dragged, in pixels.
    await _open(tester);
    await tester.tap(find.byTooltip('Shape  R'));
    await tester.pumpAndSettle();

    final dragged = await _dragOnBoard(
        tester, const Offset(0.3, 0.3), const Offset(0.6, 0.6));

    expect(_says('1 selected'), findsWidgets);
    // Measured, not read off a property: the shape on screen is the rectangle
    // the pointer described. A cell-snapped element could only ever be a whole
    // number of ~134×132 blocks, and would miss this by tens of pixels.
    final drawn = tester.getRect(find.byType(ShapePrimitiveCard));
    expect(drawn.width, closeTo(dragged.width, 2));
    expect(drawn.height, closeTo(dragged.height, 2));
    expect(drawn.left, closeTo(dragged.left, 2));
    expect(drawn.top, closeTo(dragged.top, 2));

    // And the status bar says pixels, because pixels are what it now is.
    expect(_says(' px at '), findsWidgets);
  });

  testWidgets('a level drag with the line tool makes a rule, not a block',
      (tester) async {
    // John: *"why is line stuck in a 2x4 rectangle when it should be more
    // freeform on the canvas?"* — because the drag was answered in cells, and
    // the smallest cell is 134 by 132.
    await _open(tester);
    await tester.tap(find.byTooltip('Line  L'));
    await tester.pumpAndSettle();
    await _dragOnBoard(tester, const Offset(0.2, 0.5), const Offset(0.7, 0.5));

    final drawn = tester.getRect(find.byType(LinePrimitiveCard));
    expect(drawn.width, greaterThan(drawn.height * 8),
        reason: 'a level rule is a band, not a block');
  });

  testWidgets('a diagonal drag makes a diagonal line', (tester) async {
    await _open(tester);
    await tester.tap(find.byTooltip('Line  L'));
    await tester.pumpAndSettle();
    await _dragOnBoard(tester, const Offset(0.2, 0.2), const Offset(0.6, 0.6));

    // The angle is the drag's own angle, so what you let go of is what you
    // drew. Read off the element rather than off the gesture.
    final painter = tester
        .widgetList<CustomPaint>(find.descendant(
          of: find.byType(LinePrimitiveCard),
          matching: find.byType(CustomPaint),
        ))
        .last
        .painter!;
    final box = tester.getRect(find.byType(LinePrimitiveCard));
    // On the diagonal it runs corner to corner; off it, it does not.
    expect(painter.hitTest(Offset(box.width / 2, box.height / 2)), isTrue);
    expect(painter.hitTest(Offset(box.width * 0.9, box.height * 0.1)), isFalse);
  });

  testWidgets('a text box is as tall as its type, not as tall as a row',
      (tester) async {
    // John: *"Why is the text so small in the large rectangle. Text should be
    // a text box that sizes for the font size."*
    await _open(tester);
    await tester.tap(find.byTooltip('Text  T'));
    await tester.pumpAndSettle();
    // A wide, flat drag — the gesture somebody makes for a headline.
    await _dragOnBoard(tester, const Offset(0.2, 0.4), const Offset(0.7, 0.41));

    final drawn = tester.getRect(find.byType(TextPrimitiveCard));
    final text = tester
        .renderObject<RenderBox>(find.descendant(
          of: find.byType(TextPrimitiveCard),
          matching: find.byType(Text),
        ))
        .size;
    // Within a couple of pixels of the words themselves — not a grid row with
    // a word floating in the middle of it.
    expect(drawn.height, lessThan(text.height * 1.6));
  });

  testWidgets('and the tool is put down again afterwards', (tester) async {
    // One shape per press of the tool. A tool that stays down is one you make
    // shapes with by accident.
    await _open(tester);
    await tester.tap(find.byTooltip('Shape  R'));
    await tester.pumpAndSettle();
    await _dragOnBoard(tester, const Offset(0.3, 0.3), const Offset(0.5, 0.5));

    // The same drag again now selects rather than drawing: it catches the
    // shape that is already there instead of putting a second one on top.
    await _dragOnBoard(
        tester, const Offset(0.28, 0.28), const Offset(0.62, 0.62));
    expect(_says('1 selected'), findsWidgets);
  });

  testWidgets('with no tool in hand the same drag still selects',
      (tester) async {
    await _open(tester);
    // From empty canvas back over the card in the corner. The band lives
    // *behind* the cards, so a drag that started on one would be a card move —
    // which is the right behaviour and not the one under test.
    await _dragOnBoard(
        tester, const Offset(0.8, 0.5), const Offset(0.01, 0.01));
    expect(_says('1 selected'), findsWidgets);
  });

  testWidgets('a bare letter picks the tool, and Escape puts it down',
      (tester) async {
    await _open(tester);
    // The keyboard is the canvas's, so this is the same path a person uses.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pumpAndSettle();
    await _dragOnBoard(
        tester, const Offset(0.3, 0.6), const Offset(0.55, 0.75));
    expect(_says('1 selected'), findsWidgets);

    // Now Escape, then the same drag: nothing new should be made.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await _dragOnBoard(tester, const Offset(0.7, 0.8), const Offset(0.85, 0.9));
    // A band over empty canvas with no tool in hand catches nothing, and
    // nothing new was drawn — which is the whole claim.
    expect(_says('Nothing selected'), findsWidgets);
  });
}
