import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/design/components/hc_device_tile.dart';
import 'package:hc_web/design/components/hc_surface.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/design/tokens.dart';

Widget _host(HcSkin skin, Widget child, {bool reduceMotion = false}) =>
    MaterialApp(
      theme: hcTheme(skin, reduceMotion: reduceMotion),
      home: Scaffold(body: Center(child: SizedBox(width: 320, child: child))),
    );

void main() {
  group('tokens', () {
    test('every skin exposes a complete, attached token set', () {
      for (final skin in HcSkin.values) {
        final theme = hcTheme(skin);
        final t = theme.extension<HcTokens>();
        expect(t, isNotNull, reason: '${skin.name} lost its tokens');
        expect(t!.name, isNotEmpty);
        // Material's palette must be derived from the tokens, not seeded on its
        // own — otherwise stray stock widgets show up in default indigo.
        expect(theme.colorScheme.primary, t.accent.primary);
        expect(theme.scaffoldBackgroundColor, t.surface.base);
      }
    });

    test('each shell has a distinct default skin', () {
      final skins = {
        for (final s in HcShell.values) s: HcSkin.defaultFor(s),
      };
      expect(skins[HcShell.wall], HcSkin.ambientGlass);
      // Dark by default: a warm halo on a light ground has nothing to bleed
      // into, and the glow is the whole language.
      expect(skins[HcShell.touch], HcSkin.midnight);
      // Two surfaces, two defaults. Control Room is still a skin anyone can
      // choose through skinOverrideProvider; it is no longer a *default*,
      // because the admin portal it was the default for is now part of the app.
      expect(skins.values.toSet(), hasLength(2));
    });

    test('only the wall skin frosts; the flat skins opt out via blur = 0', () {
      // This is the mechanism that keeps one widget serving every skin: a flat
      // skin sets glassBlur to 0 and HcSurface skips the BackdropFilter.
      expect(HcSkin.ambientGlass.tokens.surface.isGlass, isTrue);
      expect(HcSkin.controlRoom.tokens.surface.isGlass, isFalse);
      expect(HcSkin.softHome.tokens.surface.isGlass, isFalse);
      // Midnight exists precisely BECAUSE it must not frost: the device list
      // renders 167 surfaces, and a BackdropFilter behind each one is a
      // frame-rate cliff. It is Ambient Glass with the glass taken out.
      expect(HcSkin.midnight.tokens.surface.isGlass, isFalse);
    });

    test('Midnight still glows — a dark ground is what a halo needs', () {
      expect(HcSkin.midnight.tokens.glow.enabled, isTrue);
      expect(HcSkin.midnight.tokens.brightness, Brightness.dark);
      expect(HcSkin.midnight.tokens.accent.active,
          HcSkin.ambientGlass.tokens.accent.active);
    });

    test('glow is full on the wall, absent in the admin portal', () {
      expect(HcSkin.ambientGlass.tokens.glow.enabled, isTrue);
      expect(HcSkin.controlRoom.tokens.glow.enabled, isFalse);
    });

    test('admin is denser than the wall panel', () {
      expect(
        HcSkin.controlRoom.tokens.density.rowHeight,
        lessThan(HcSkin.ambientGlass.tokens.density.rowHeight),
      );
      // A wall panel is touched from arm's length; keep targets thumb-sized.
      expect(
        HcSkin.ambientGlass.tokens.density.minTapTarget,
        greaterThanOrEqualTo(48),
      );
    });

    test('reduced motion collapses every duration to zero', () {
      final t =
          hcTheme(HcSkin.softHome, reduceMotion: true).extension<HcTokens>()!;
      expect(t.motion.enabled, isFalse);
      expect(t.motion.d(t.motion.base), Duration.zero);
      expect(t.motion.d(t.motion.slow), Duration.zero);
    });

    test('offline is never merely "off" — it has its own colour', () {
      for (final skin in HcSkin.values) {
        final a = skin.tokens.accent;
        expect(a.offline, isNot(a.inactive), reason: skin.name);
        expect(a.offline, isNot(a.active), reason: skin.name);
      }
    });

    test('skins lerp, so switching shells can crossfade', () {
      final mid = HcSkin.softHome.tokens.lerp(HcSkin.controlRoom.tokens, 0.5);
      expect(mid.radius.md, isNot(HcSkin.softHome.tokens.radius.md));
      expect(mid.space.unit, greaterThan(0));
    });
  });

  group('components', () {
    testWidgets('a tile renders in every skin', (tester) async {
      for (final skin in HcSkin.values) {
        await tester.pumpWidget(_host(
          skin,
          const HcDeviceTile(
            name: 'Kitchen Ceiling',
            icon: Icons.light_mode,
            subtitle: '82%',
            on: true,
            intensity: 0.82,
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Kitchen Ceiling'), findsOneWidget,
            reason: 'failed in ${skin.name}');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('an offline device reads as offline, not as off',
        (tester) async {
      await tester.pumpWidget(_host(
        HcSkin.softHome,
        const HcDeviceTile(
          name: 'Garage',
          icon: Icons.garage,
          subtitle: 'ignored while offline',
          on: true,
          offline: true,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsOneWidget);
      // The subtitle is replaced, so a stale value can't masquerade as live.
      expect(find.text('ignored while offline'), findsNothing);
    });

    testWidgets('brightness glides rather than snapping', (tester) async {
      Widget at(double v) => _host(
            HcSkin.ambientGlass,
            HcDeviceTile(
              name: 'Lamp',
              icon: Icons.light_mode,
              on: true,
              intensity: v,
            ),
          );

      await tester.pumpWidget(at(0.1));
      await tester.pumpAndSettle();

      // A WS frame lands: 10% → 100%.
      await tester.pumpWidget(at(1.0));
      await tester.pump(const Duration(milliseconds: 40));

      // Mid-flight the animation is still running — i.e. it did not snap.
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a pulse flashes the tile without disturbing content',
        (tester) async {
      Widget at(int pulse) => _host(
            HcSkin.ambientGlass,
            HcDeviceTile(
              name: 'Lamp',
              icon: Icons.light_mode,
              on: true,
              pulse: pulse,
            ),
          );

      await tester.pumpWidget(at(0));
      await tester.pumpAndSettle();

      await tester.pumpWidget(at(1)); // a remote change arrived
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpAndSettle();
      expect(find.text('Lamp'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('HcValue keeps digits from reflowing the layout',
        (tester) async {
      await tester.pumpWidget(
        _host(HcSkin.controlRoom, const HcValue('72.4', unit: '°F')),
      );
      await tester.pumpAndSettle();

      final rich = tester.widget<RichText>(find.byType(RichText).first);
      final style = (rich.text as TextSpan).style!;
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    testWidgets('a glass surface actually frosts, a flat one does not',
        (tester) async {
      await tester.pumpWidget(
        _host(HcSkin.ambientGlass, const HcSurface(child: Text('x'))),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);

      await tester.pumpWidget(
        _host(HcSkin.controlRoom, const HcSurface(child: Text('x'))),
      );
      await tester.pumpAndSettle();
      // The flat skin must not pay for a blur it never shows.
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('reduced motion really does stop the animations',
        (tester) async {
      await tester.pumpWidget(_host(
        HcSkin.ambientGlass,
        const HcDeviceTile(name: 'Lamp', icon: Icons.light_mode, on: true),
        reduceMotion: true,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
