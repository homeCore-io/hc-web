import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/skin_document.dart';
import 'package:hc_web/design/skin_resolve.dart';
import 'package:hc_web/design/skin_seeds.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/design/tokens.dart';

/// The chain that turns a stored choice into tokens.
///
/// Step 4 of `theme-editor-plan.md`. The property worth having is not that it
/// resolves correctly — it is that it **cannot fail**. A house is never one bad
/// row in a database away from an unstyled app, and every test below is really
/// asking the same question from a different angle: what dresses the app when
/// this particular thing has gone wrong?

/// A valid skin document, as core would return it.
Map<String, dynamic> seedJson({Map<String, dynamic> changes = const {}}) => {
      'brightness': 'dark',
      'ground': '#0B0E13',
      'raised': '#141922',
      'sunken': '#0D1116',
      'overlay': '#1A202A',
      'ink': '#E9EDF2',
      'ink_muted': '#8B95A4',
      'accent': '#7CC4FF',
      'on_accent': '#06131F',
      'active': '#FFB661',
      'inactive': '#2A313B',
      'success': '#6FD1A6',
      'warn': '#FFC978',
      'danger': '#FF7B72',
      'offline': '#AA737A',
      'hairline': '#262D38',
      'corners': [4, 8, 14, 22],
      'space_unit': 8,
      'type_scale': 1.0,
      'glow_strength': 1.0,
      'glow_radius': 34,
      'density': 'comfortable',
      'motion': 'standard',
      ...changes,
    };

SkinDocument doc({
  String id = 'hallway',
  String base = 'midnight',
  Map<String, dynamic> changes = const {},
  Map<String, String> overrides = const {},
}) =>
    SkinDocument.fromJson({
      'id': id,
      'name': 'Hallway',
      'base': base,
      'seeds': seedJson(changes: changes),
      'overrides': overrides,
    });

void main() {
  group('a stored choice round-trips', () {
    test('a built-in stores its enum name', () {
      const choice = SkinChoice.builtIn(HcSkin.softHome);
      expect(choice.stored, 'softHome');
      expect(SkinChoice.fromStored('softHome'), choice);
    });

    test('a data skin stores its id', () {
      expect(const SkinChoice.data('hallway').stored, 'hallway');
      expect(
          SkinChoice.fromStored('hallway'), const SkinChoice.data('hallway'));
    });

    test('no choice stores nothing, and nothing reads back as no choice', () {
      expect(const SkinChoice.none().stored, isNull);
      expect(SkinChoice.fromStored(null).isNone, isTrue);
      expect(SkinChoice.fromStored('').isNone, isTrue);
    });

    test('a built-in name wins over a data skin that stole it', () {
      // They share one key. A data skin called `midnight` is shadowed rather
      // than shadowing — the safe way round, since the built-in always exists.
      expect(SkinChoice.fromStored('midnight').builtIn, HcSkin.midnight);
    });
  });

  group('the chain always dresses the app', () {
    test('no choice takes the shell its own default', () {
      for (final shell in HcShell.values) {
        expect(
          resolveSkin(
              choice: const SkinChoice.none(),
              shell: shell,
              skins: const []).name,
          HcSkin.defaultFor(shell).tokens.name,
        );
      }
    });

    test('a chosen built-in is that built-in on every shell', () {
      for (final shell in HcShell.values) {
        expect(
          resolveSkin(
            choice: const SkinChoice.builtIn(HcSkin.controlRoom),
            shell: shell,
            skins: const [],
          ).name,
          'control_room',
        );
      }
    });

    test('a data skin is derived from its seeds', () {
      final t = resolveSkin(
        choice: const SkinChoice.data('hallway'),
        shell: HcShell.touch,
        skins: [doc()],
      );
      expect(t.name, 'hallway');
      expect(t.surface.base, const Color(0xFF0B0E13));
      expect(t.radius.md, 14);
      // Derived, not stored: proof the seeds went through deriveTokens.
      expect(t.density.minTapTarget, 44);
      expect(t.accent.onDanger, t.accent.onPrimary);
    });

    test('a skin that will not parse falls back to the base it names', () {
      // Every kind of malformed seed, one at a time. The response is the same
      // for all of them, which is why the parser returns null rather than
      // distinguishing them.
      for (final broken in [
        {'ground': 'not a colour'},
        {'brightness': 'twilight'},
        {
          'corners': <int>[4, 8]
        },
        {'density': 'roomy'},
        {'space_unit': 'eight'},
      ]) {
        final t = resolveSkin(
          choice: const SkinChoice.data('hallway'),
          shell: HcShell.touch,
          skins: [doc(base: 'soft_home', changes: broken)],
        );
        expect(t.name, 'soft_home', reason: 'broken by $broken');
      }
    });

    test('an unknown base falls back to Midnight', () {
      final t = resolveSkin(
        choice: const SkinChoice.data('hallway'),
        shell: HcShell.touch,
        skins: [
          doc(base: 'art_deco', changes: {'ground': 'nope'})
        ],
      );
      expect(t.name, 'midnight');
    });

    test('a chosen skin that is not there takes the shell default', () {
      // Deleted while a panel was showing it, or the /skins call failed — the
      // empty list covers both, because the answer is the same.
      for (final shell in HcShell.values) {
        expect(
          resolveSkin(
            choice: const SkinChoice.data('deleted'),
            shell: shell,
            skins: const [],
          ).name,
          HcSkin.defaultFor(shell).tokens.name,
        );
      }
    });

    test('nothing in the chain ever throws', () {
      // The property the whole design rests on, swept rather than argued.
      final choices = [
        const SkinChoice.none(),
        const SkinChoice.data(''),
        const SkinChoice.data('missing'),
        const SkinChoice.builtIn(HcSkin.midnight),
      ];
      final skinSets = <List<SkinDocument>>[
        const [],
        [doc()],
        [
          doc(changes: {'ground': 'x'})
        ],
        [SkinDocument.fromJson(const {})],
        [
          SkinDocument.fromJson(const {'id': 'hallway', 'seeds': 'nonsense'})
        ],
      ];
      for (final choice in choices) {
        for (final skins in skinSets) {
          for (final shell in HcShell.values) {
            expect(
              () => resolveSkin(choice: choice, shell: shell, skins: skins),
              returnsNormally,
            );
          }
        }
      }
    });
  });

  group('overrides', () {
    test('a named token is replaced and its neighbours are not', () {
      final t = resolveSkin(
        choice: const SkinChoice.data('hallway'),
        shell: HcShell.touch,
        skins: [
          doc(overrides: {'accent.warn': '#C8761F'})
        ],
      );
      expect(t.accent.warn, const Color(0xFFC8761F));
      expect(t.accent.danger, const Color(0xFFFF7B72),
          reason: 'an override reached a token it was not aimed at');
    });

    test('a misspelled path does nothing at all', () {
      // Deliberately not fuzzy: a setting that appears to save and never
      // applies is worse than one that visibly does nothing.
      final base = deriveTokens(doc().toSeeds()!);
      final t = applySkinOverrides(base, {'acccent.warn': '#C8761F'});
      expect(t.accent.warn, base.accent.warn);
    });

    test('an unparseable override value is ignored, not fatal', () {
      final base = deriveTokens(doc().toSeeds()!);
      final t = applySkinOverrides(base, {'accent.warn': 'burnt sienna'});
      expect(t.accent.warn, base.accent.warn);
    });

    test('every documented path actually reaches its token', () {
      // A path that silently did nothing would be an editor control with no
      // effect, discovered only by someone wondering why their change did not
      // take.
      final base = deriveTokens(doc().toSeeds()!);
      const probe = '#123456';
      const expected = Color(0xFF123456);
      final cases = <String, Color Function(HcTokens)>{
        'surface.base': (t) => t.surface.base,
        'surface.raised': (t) => t.surface.raised,
        'surface.sunken': (t) => t.surface.sunken,
        'surface.overlay': (t) => t.surface.overlay,
        'surface.onBase': (t) => t.surface.onBase,
        'surface.onBaseMuted': (t) => t.surface.onBaseMuted,
        'accent.primary': (t) => t.accent.primary,
        'accent.onPrimary': (t) => t.accent.onPrimary,
        'accent.active': (t) => t.accent.active,
        'accent.inactive': (t) => t.accent.inactive,
        'accent.success': (t) => t.accent.success,
        'accent.warn': (t) => t.accent.warn,
        'accent.danger': (t) => t.accent.danger,
        'accent.onDanger': (t) => t.accent.onDanger,
        'accent.offline': (t) => t.accent.offline,
        'stroke.hairline': (t) => t.stroke.hairline,
        'stroke.focus': (t) => t.stroke.focus,
        'metric.temperature': (t) => t.metric.temperature,
        'metric.humidity': (t) => t.metric.humidity,
        'metric.illuminance': (t) => t.metric.illuminance,
        'metric.co2': (t) => t.metric.co2,
        'metric.power': (t) => t.metric.power,
        'metric.reading': (t) => t.metric.reading,
      };
      cases.forEach((path, read) {
        expect(read(applySkinOverrides(base, {path: probe})), expected,
            reason: '$path does not reach its token');
      });
    });
  });

  group('the document', () {
    test('an unknown seed field survives a round trip', () {
      // Seeds are kept unparsed so an edit-and-save through an older client
      // does not silently drop a field a newer one wrote.
      final d = SkinDocument.fromJson({
        'id': 'hallway',
        'name': 'Hallway',
        'base': 'midnight',
        'seeds': seedJson(changes: {'texture': 'linen'}),
      });
      expect(d.toJson()['seeds'], containsPair('texture', 'linen'));
    });

    test('absent glass reads as none rather than failing', () {
      final seeds = doc().toSeeds()!;
      expect(seeds.glass, SkinGlass.none);
    });

    test('both hex forms parse', () {
      final seeds = doc(changes: {'hairline': '#1FFFFFFF'}).toSeeds()!;
      expect(seeds.hairline, const Color(0x1FFFFFFF));
    });
  });
}
