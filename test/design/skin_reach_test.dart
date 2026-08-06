import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/design/tokens.dart';
import 'package:hc_web/shared/widgets/section_scaffold.dart';
import 'package:hc_web/shared/widgets/skeleton.dart';
import 'package:hc_web/shell/hc_sheet.dart';

/// A skin has to reach the whole app, not just the chrome.
///
/// Several surfaces used to pin `hcTheme(HcSkin.midnight)` on themselves —
/// SectionScaffold, the plugin sheets, the discovery dialog, the plugin studio.
/// That made a chosen skin stop at the shell: the rail and the bars changed,
/// and every page inside them stayed Midnight. It also silently dropped
/// reduced motion, because `hcTheme(skin)` defaults `reduceMotion` to false and
/// only ShellScope was passing it.
///
/// `skins_test.dart` could not catch either problem: it calls
/// `hcTheme(skin, reduceMotion: …)` directly and never renders one of these
/// surfaces, so it was testing the function rather than the path. These tests
/// go through the widgets instead.

/// Reports the tokens it actually resolved, which is the only thing that
/// settles whether a skin reached this far.
class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Text('skin=${t.name} motion=${t.motion.enabled}');
  }
}

Widget _host(HcSkin skin, Widget child, {bool reduceMotion = false}) =>
    MaterialApp(
      theme: hcTheme(skin, reduceMotion: reduceMotion),
      home: child,
    );

void main() {
  group('SectionScaffold', () {
    testWidgets('renders in the skin around it, not a pinned one',
        (tester) async {
      // Soft Home is the light skin — if the page were still pinning Midnight
      // this would be a dark page inside a light app, which is exactly the bug.
      await tester.pumpWidget(_host(
        HcSkin.softHome,
        const SectionScaffold(title: 'Devices', child: _Probe()),
      ));
      expect(find.text('skin=soft_home motion=true'), findsOneWidget);
    });

    testWidgets('carries reduced motion through', (tester) async {
      await tester.pumpWidget(_host(
        HcSkin.midnight,
        const SectionScaffold(title: 'Devices', child: _Probe()),
        reduceMotion: true,
      ));
      // Same skin, motion off. A pinned `hcTheme(HcSkin.midnight)` would have
      // looked identical and quietly turned the animations back on.
      expect(find.text('skin=midnight motion=false'), findsOneWidget);
    });

    testWidgets('every skin reaches it', (tester) async {
      for (final skin in HcSkin.values) {
        await tester.pumpWidget(_host(
          skin,
          const SectionScaffold(title: 'Devices', child: _Probe()),
        ));
        // MaterialApp cross-fades between themes over themeAnimationDuration,
        // and HcTokens.lerp flips the discrete values at the halfway point — so
        // one frame after a *change* of skin is still the old one. Settle first
        // or this reads as "the skin never arrived".
        await tester.pumpAndSettle();
        expect(
            find.text('skin=${skin.tokens.name} motion=true'), findsOneWidget,
            reason: '${skin.name} did not reach the page');
      }
    });
  });

  group('type', () {
    testWidgets('the tokens survive being filed under a ThemeExtension key',
        (tester) async {
      // `ThemeExtension` defines `type` as the key ThemeData files each
      // extension under. Naming the ramp `HcTokens.type` re-keys the map by an
      // HcType, `extension<HcTokens>()` returns null, and every HcTokens.of in
      // the app throws — from one field name, with the analyzer offering only
      // an `annotate_overrides` info. Hence `text`, and hence this test.
      await tester.pumpWidget(_host(HcSkin.midnight, const _Probe()));
      expect(find.text('skin=midnight motion=true'), findsOneWidget);
      final ctx = tester.element(find.byType(_Probe));
      expect(Theme.of(ctx).extension<HcTokens>(), isNotNull,
          reason: 'HcTokens is no longer reachable as a theme extension');
    });

    testWidgets('every skin puts a ramp on the Material text slots',
        (tester) async {
      // hcTheme set no textTheme at all, so the 33 `textTheme.*` readers and
      // every self-styling Material widget were sized by Material's defaults —
      // the one part of the app a skin could not touch.
      for (final skin in HcSkin.values) {
        await tester.pumpWidget(_host(skin, const _Probe()));
        await tester.pumpAndSettle();
        final theme = Theme.of(tester.element(find.byType(_Probe)));
        final t = theme.extension<HcTokens>()!;
        expect(theme.textTheme.bodySmall?.fontSize,
            t.text.bodySmall.size * t.text.scale,
            reason: '${skin.name} bodySmall slot is not on the ramp');
        expect(theme.textTheme.titleLarge?.fontSize,
            t.text.title.size * t.text.scale,
            reason: '${skin.name} title slot is not on the ramp');
        expect(
            theme.textTheme.labelSmall?.letterSpacing, t.text.overline.tracking,
            reason: '${skin.name} lost the overline tracking');

        // The ambient default — what every unstyled Text inherits. Pinned at
        // the ramp's 14 through phases 1 and 2 because the text relying on it
        // had been written against Material's 14; phase 3 gave that text
        // explicit roles, so it is body now.
        expect(theme.textTheme.bodyMedium?.fontSize,
            t.text.body.size * t.text.scale,
            reason: '${skin.name} ambient default is off the ramp');
        expect(theme.textTheme.bodyMedium?.fontWeight, t.text.body.weight,
            reason: '${skin.name} would render all inherited text semibold');
      }
    });

    test('the skins actually differ in type', () {
      // The point of the whole exercise. Before this, a skin could change
      // colour, spacing, radius, motion, glow, density and elevation — and not
      // one letter. `wall_chrome` drew its clock at 96 while every page inside
      // that wall shell drew its content at the same size as the phone.
      double body(HcSkin s) => s.tokens.text.body.size * s.tokens.text.scale;

      // The wall panel is read from across a dark room; the admin portal packs
      // rows 34px high. They must not land on the same number.
      expect(body(HcSkin.ambientGlass), greaterThan(body(HcSkin.midnight)));
      expect(body(HcSkin.controlRoom), lessThan(body(HcSkin.midnight)));

      // ...but the floor still has to be legible. At `density.rowHeight`'s own
      // ratio (0.65) the overline role would land at 6.5px.
      for (final s in HcSkin.values) {
        final t = s.tokens.text;
        expect(t.overline.size * t.scale, greaterThanOrEqualTo(9),
            reason: '${s.name} scales its smallest role below legibility');
      }
    });

    test('the ramp has no half-point steps left in it', () {
      // The 8 sizes the app used (13/13.5, 12/12.5, 11/11.5, 10/10.5) collapse
      // to 4. If a later edit reintroduces a half step, the reason for the ramp
      // is already half gone.
      final t = HcSkin.midnight.tokens.text;
      for (final role in [
        t.display,
        t.title,
        t.subtitle,
        t.body,
        t.caption,
        t.overline
      ]) {
        expect(role.size, role.size.roundToDouble(),
            reason: '${role.size} is a half step');
      }
      // bodySmall is the one deliberate exception: 12.5 is where 266 sites
      // already are, and rounding it moves more text than it tidies.
      expect(t.bodySmall.size, 12.5);
    });
  });

  group('tap targets', () {
    testWidgets('every skin gets the target size it asks for', (tester) async {
      // `minTapTarget` was declared by all four skins and read by none of them.
      // Every icon button in every skin rendered at Material's default 48 — so
      // Ambient Glass, the skin whose whole reason for existing is a panel
      // pressed from across a room, asked for 56 and got the same 48 as the
      // admin portal. The same shape as the type sizes: a dimension the skin
      // was allowed an opinion about, with no way for the opinion to arrive.
      for (final skin in HcSkin.values) {
        await tester.pumpWidget(_host(
          skin,
          Scaffold(
            body: IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
          ),
        ));
        // Settle, or every skin measures as the first one — MaterialApp
        // cross-fades themes and the size is read mid-transition.
        await tester.pumpAndSettle();

        final t = skin.tokens;
        final size = tester.getSize(find.byType(IconButton));
        expect(size.height, greaterThanOrEqualTo(t.density.minTapTarget),
            reason: '${skin.name} asks for ${t.density.minTapTarget} and '
                'renders ${size.height}');
        expect(size.width, greaterThanOrEqualTo(t.density.minTapTarget),
            reason: skin.name);
      }
    });

    testWidgets('nothing falls under the 24px floor, even when compacted',
        (tester) async {
      // `VisualDensity.compact` appears on 17 widgets, and on a skin whose
      // theme is already compact — Control Room, whose rows are 34 high — the
      // two compound. That is the smallest interactive thing in the app, so it
      // is the one worth pinning: WCAG 2.5.8 puts the floor at 24x24.
      for (final skin in HcSkin.values) {
        await tester.pumpWidget(_host(
          skin,
          Scaffold(
            body: IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () {},
              icon: const Icon(Icons.add),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        final size = tester.getSize(find.byType(IconButton));
        expect(size.shortestSide, greaterThanOrEqualTo(24.0),
            reason: '${skin.name} compacts a target to ${size.shortestSide}, '
                'under the WCAG 2.5.8 floor');
      }
    });
  });

  group('loading states', () {
    // The skeletons carried their own shimmer for a while: a second animation
    // controller, colours read off `colorScheme` rather than the tokens, and a
    // `repeat()` in `initState` with nothing guarding it. So the one moment
    // every page has in common — before its data arrives — was also the one
    // moment reduced motion was ignored. They are built on HcShimmer now, which
    // is where the guard lives.

    testWidgets('a skeleton does not animate under reduced motion',
        (tester) async {
      await tester.pumpWidget(_host(
        HcSkin.midnight,
        const SizedBox(height: 400, child: SkeletonList(count: 3)),
        reduceMotion: true,
      ));
      await tester.pump();
      // A repeating ticker keeps a transient frame callback registered forever.
      // If this is non-zero the sheen is still travelling.
      expect(tester.binding.transientCallbackCount, 0,
          reason: 'the shimmer kept running with motion disabled');
    });

    testWidgets('and does animate when the skin allows motion', (tester) async {
      await tester.pumpWidget(_host(
        HcSkin.midnight,
        const SizedBox(height: 400, child: SkeletonList(count: 3)),
      ));
      await tester.pump();
      // The inverse, so the test above cannot pass by the shimmer being broken.
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('every skin reaches the card skeletons too', (tester) async {
      for (final skin in HcSkin.values) {
        await tester.pumpWidget(_host(
          skin,
          const SizedBox(
            height: 400,
            child: Column(children: [
              Expanded(child: SkeletonCardList(count: 2)),
              _Probe(),
            ]),
          ),
          reduceMotion: true, // so pumpAndSettle is not waiting on a loop
        ));
        await tester.pumpAndSettle();
        expect(
            find.text('skin=${skin.tokens.name} motion=false'), findsOneWidget,
            reason: '${skin.name} did not reach the loading state');
      }
    });
  });

  group('showHcSheet', () {
    // Sheets go through showGeneralDialog, which — unlike showDialog — does not
    // capture the inherited theme on its way to the root navigator.
    //
    // The topology matters and the test has to reproduce it: app.dart puts a
    // base theme *above* the navigator and ShellScope applies the resolved skin
    // *below* it, inside the route. A sheet pushed onto the root navigator
    // therefore sits outside ShellScope's Theme and falls back to the base one,
    // so the house and the sheet over it end up in different skins. Hosting the
    // sheet under a single MaterialApp theme would pass with or without the
    // capture and prove nothing.
    Widget opener(HcSkin skin,
            {HcSkin base = HcSkin.midnight, bool reduceMotion = false}) =>
        MaterialApp(
          theme: hcTheme(base),
          home: Theme(
            data: hcTheme(skin, reduceMotion: reduceMotion),
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showHcSheet(
                      context,
                      title: 'Detail',
                      child: const _Probe(),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('a sheet keeps the skin of the house behind it',
        (tester) async {
      await tester.pumpWidget(opener(HcSkin.softHome));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('skin=soft_home motion=true'), findsOneWidget,
          reason: 'the sheet fell back to the base theme');
    });

    testWidgets('a sheet keeps reduced motion too', (tester) async {
      await tester.pumpWidget(
          opener(HcSkin.midnight, base: HcSkin.softHome, reduceMotion: true));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('skin=midnight motion=false'), findsOneWidget);
    });

    testWidgets('every skin reaches a sheet', (tester) async {
      for (final skin in HcSkin.values) {
        // Always host under a *different* base, or midnight-under-midnight
        // would pass without the capture and quietly weaken the loop.
        final base =
            skin == HcSkin.midnight ? HcSkin.softHome : HcSkin.midnight;
        await tester.pumpWidget(opener(skin, base: base));
        await tester.pumpAndSettle(); // see the note above about theme lerping
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(
            find.text('skin=${skin.tokens.name} motion=true'), findsOneWidget,
            reason: '${skin.name} did not reach the sheet');
        // Dismiss so the next skin starts from a closed sheet.
        Navigator.of(tester.element(find.text('open'))).pop();
        await tester.pumpAndSettle();
      }
    });
  });
}
