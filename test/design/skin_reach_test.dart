import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/design/tokens.dart';
import 'package:hc_web/shared/widgets/section_scaffold.dart';
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
