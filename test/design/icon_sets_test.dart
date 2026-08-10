import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/devices/presentation.dart';
import 'package:hc_web/core/models/skin_document.dart';
import 'package:hc_web/design/hc_icons.dart';
import 'package:hc_web/design/icon_sets.dart';
import 'package:hc_web/design/skin_resolve.dart';
import 'package:hc_web/design/skins.dart';

/// Which glyphs the house wears.
///
/// The app's icon vocabulary is **facet → glyph**, not a list of icon names —
/// every icon a device wears is chosen by what the device *is*. So a set is an
/// alternative answer to that one question, which is what makes this possible
/// without a per-font mapping table: a set has to cover thirty-odd facets and
/// nothing else.

void main() {
  setUp(IconSets.reset);
  tearDown(IconSets.reset);

  group('the sets', () {
    test('every set answers for every facet', () {
      // A set with a hole in it would draw one device as a blank square, and
      // which device would depend on the house.
      for (final set in IconSets.builtIn) {
        for (final facet in DeviceFacet.values) {
          expect(() => set.forFacet(facet), returnsNormally,
              reason: '${set.key} has no answer for ${facet.name}');
          expect(() => set.forFacet(facet, on: true), returnsNormally,
              reason: '${set.key} has no lit answer for ${facet.name}');
        }
      }
    });

    test('keys are stable and distinct, because a skin stores them', () {
      final keys = IconSets.builtIn.map((s) => s.key).toList();
      expect(keys.toSet().length, keys.length);
      expect(keys, contains('phosphor'));
    });

    test('Phosphor still fills when a device is on', () {
      const phosphor = PhosphorIconSet();
      final off = phosphor.forFacet(DeviceFacet.light);
      final on = phosphor.forFacet(DeviceFacet.light, on: true);
      expect(off.fontFamily, isNot(on.fontFamily),
          reason: 'a lit lamp is the same glyph, solid — the entire point of '
              'the two weights');
    });

    test('a single-weight set returns the same glyph rather than nothing', () {
      const material = MaterialIconSet();
      expect(material.forFacet(DeviceFacet.light, on: true),
          material.forFacet(DeviceFacet.light),
          reason: 'reads as "this set does not distinguish", not as a missing '
              'icon');
    });
  });

  group('choosing', () {
    test('the default is what the app has always drawn', () {
      expect(IconSets.active.key, 'phosphor');
      expect(HcIcons.forFacet(DeviceFacet.lock),
          const PhosphorIconSet().forFacet(DeviceFacet.lock));
    });

    test('selecting one changes what every icon resolves to', () {
      IconSets.select('material');
      expect(HcIcons.forFacet(DeviceFacet.lock),
          const MaterialIconSet().forFacet(DeviceFacet.lock));
    });

    test('null and unknown both land on the default', () {
      // Not "keep whatever was active", which was the first version and wrong
      // twice: a skin with no choice would silently inherit the previous
      // skin's icons, and the result would depend on which skins you had
      // looked at first.
      IconSets.select('material');
      IconSets.select(null);
      expect(IconSets.active.key, 'phosphor');

      IconSets.select('material');
      IconSets.select('a_set_from_a_newer_client');
      expect(IconSets.active.key, 'phosphor',
          reason: 'and it is a real set, not a blank one');
    });

    test('it repaints when it changes, and only then', () {
      final before = IconSets.revision.value;
      IconSets.select('material');
      expect(IconSets.revision.value, greaterThan(before));

      final after = IconSets.revision.value;
      IconSets.select('material');
      expect(IconSets.revision.value, after,
          reason: 'selecting the same set again is not a change');
    });
  });

  group('on a skin', () {
    const doc = SkinDocument(
      id: 's',
      name: 'S',
      base: 'midnight',
      seeds: {},
      overrides: {iconSetOverrideKey: 'material'},
    );

    test('the choice survives a round trip through core', () {
      // Overrides is a free-form map, which is why this needs no core change
      // and works against the core already deployed.
      final back = SkinDocument.fromJson(doc.toJson());
      expect(back.overrides[iconSetOverrideKey], 'material');
    });

    test('the active skin is the one that decides', () {
      final overrides = activeSkinOverrides(
          choice: const SkinChoice.data('s'), skins: const [doc]);
      expect(overrides[iconSetOverrideKey], 'material');
    });

    test('a built-in skin brings no overrides, so it takes the default', () {
      final overrides = activeSkinOverrides(
          choice: const SkinChoice.builtIn(HcSkin.midnight),
          skins: const [doc]);
      expect(overrides, isEmpty);
      IconSets.select(overrides[iconSetOverrideKey]);
      expect(IconSets.active.key, 'phosphor');
    });
  });
}
