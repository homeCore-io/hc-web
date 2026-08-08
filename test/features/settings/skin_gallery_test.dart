import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/skin_document.dart';
import 'package:hc_web/design/builtin_seeds.dart';
import 'package:hc_web/design/skin_resolve.dart';
import 'package:hc_web/design/skins.dart';

/// The gallery's substance: forking a built-in.
///
/// Step 5 of `theme-editor-plan.md`. The arrangement is the page's business,
/// but the promise underneath is testable and worth pinning — **a duplicate of
/// a built-in is that built-in**. A fork that quietly differed from its parent
/// would be the sort of bug you only notice by putting the two side by side and
/// squinting, which is to say never.

void main() {
  group('forking a built-in', () {
    test('a fork of each built-in is pixel-identical to its parent', () {
      for (final entry in builtInSeeds.entries) {
        final skin = entry.key;

        // Exactly what the gallery does: write the parent's seeds out as the
        // new skin's document, then read it back the way the app would.
        final doc = SkinDocument(
          id: 'fork',
          name: 'Fork',
          base: skin.name,
          seeds: seedsToJson(entry.value),
          overrides: metricOverrides(entry.value),
        );
        final forked = resolveSkin(
          choice: const SkinChoice.data('fork'),
          shell: HcShell.touch,
          skins: [doc],
        );

        final parent = skin.tokens;
        expect(forked.surface.base, parent.surface.base, reason: skin.name);
        expect(forked.surface.raised, parent.surface.raised, reason: skin.name);
        expect(forked.surface.onBase, parent.surface.onBase, reason: skin.name);
        expect(forked.surface.glassBlur, parent.surface.glassBlur,
            reason: skin.name);
        expect(forked.accent.active, parent.accent.active, reason: skin.name);
        expect(forked.accent.primary, parent.accent.primary, reason: skin.name);
        expect(forked.accent.warn, parent.accent.warn, reason: skin.name);
        expect(forked.stroke.hairline, parent.stroke.hairline,
            reason: skin.name);
        expect(forked.stroke.focus, parent.stroke.focus, reason: skin.name);
        expect(forked.radius.md, parent.radius.md, reason: skin.name);
        expect(forked.radius.lg, parent.radius.lg, reason: skin.name);
        expect(forked.space.unit, parent.space.unit, reason: skin.name);
        expect(forked.glow.strength, parent.glow.strength, reason: skin.name);
        expect(forked.glow.radius, parent.glow.radius, reason: skin.name);
        expect(forked.text.scale, parent.text.scale, reason: skin.name);
        expect(forked.metric.temperature, parent.metric.temperature,
            reason: skin.name);
        expect(forked.metric.co2, parent.metric.co2, reason: skin.name);
      }
    });

    test('a fork takes the nearest preset for density and motion', () {
      // The one thing a fork does NOT carry, and it is worth stating rather
      // than quietly asserting around.
      //
      // Soft Home is the only skin affected: it predates the presets and holds
      // hand-tuned values (56/48/48/18, and timings that are `standard` off by
      // 10ms and 40ms). Those live in client-side override fields the seed wire
      // format has no room for — deliberately, because a preset invented for
      // one skin compresses nothing. A fork therefore lands on `comfortable`.
      //
      // Four pixels and forty milliseconds. If that ever matters, the fix is a
      // `roomy` preset in the vocabulary, not a wider wire format.
      final fork = resolveSkin(
        choice: const SkinChoice.data('fork'),
        shell: HcShell.touch,
        skins: [
          SkinDocument(
            id: 'fork',
            name: 'Fork',
            base: 'soft_home',
            seeds: seedsToJson(builtInSeeds[HcSkin.softHome]!),
            overrides: metricOverrides(builtInSeeds[HcSkin.softHome]!),
          )
        ],
      );
      expect(fork.density.minTapTarget, 44,
          reason: 'the comfortable preset, not Soft Home\'s tuned 48');
      expect(HcSkin.softHome.tokens.density.minTapTarget, 48,
          reason: 'and the parent still has its own');

      // Every other built-in forks exactly, because they use the presets.
      for (final skin in [
        HcSkin.midnight,
        HcSkin.ambientGlass,
        HcSkin.controlRoom
      ]) {
        final t = resolveSkin(
          choice: const SkinChoice.data('f'),
          shell: HcShell.touch,
          skins: [
            SkinDocument(
              id: 'f',
              name: 'F',
              base: 'x',
              seeds: seedsToJson(builtInSeeds[skin]!),
              overrides: metricOverrides(builtInSeeds[skin]!),
            )
          ],
        );
        expect(t.density.minTapTarget, skin.tokens.density.minTapTarget,
            reason: skin.name);
        expect(t.motion.base, skin.tokens.motion.base, reason: skin.name);
      }
    });

    test('seeds survive the trip out to JSON and back', () {
      for (final entry in builtInSeeds.entries) {
        final back = SkinDocument(
          id: entry.value.name,
          name: 'x',
          base: 'midnight',
          seeds: seedsToJson(entry.value),
        ).toSeeds();

        expect(back, isNotNull, reason: '${entry.key.name} did not survive');
        expect(back!.ground, entry.value.ground);
        expect(back.corners, entry.value.corners);
        expect(back.glass, entry.value.glass);
        expect(back.focus, entry.value.focus);
        expect(back.density, entry.value.density);
        expect(back.motion, entry.value.motion);
      }
    });

    test('a translucent seed keeps its alpha', () {
      // Ambient Glass's hairline is #1FFFFFFF. Writing it as #RRGGBB would
      // turn a barely-there line into a solid white one.
      final json = seedsToJson(builtInSeeds[HcSkin.ambientGlass]!);
      expect(json['hairline'], '#1FFFFFFF');
      expect(
          SkinDocument(id: 'x', name: 'x', base: 'm', seeds: json)
              .toSeeds()!
              .hairline,
          const Color(0x1FFFFFFF));
    });

    test('an opaque seed is written in the short form', () {
      // Not correctness, legibility: these end up in a JSON file someone reads.
      final json = seedsToJson(builtInSeeds[HcSkin.midnight]!);
      expect(json['ground'], '#0B0E13');
    });
  });

  group('what a fork inherits', () {
    test('a fork of a fork keeps the overrides', () {
      final parent = SkinDocument(
        id: 'a',
        name: 'A',
        base: 'midnight',
        seeds: seedsToJson(builtInSeeds[HcSkin.midnight]!),
        overrides: const {'accent.warn': '#FF4FD8'},
      );
      // The gallery copies both maps; this is what makes "duplicate" mean the
      // same thing for a user skin as for a built-in.
      final fork = SkinDocument(
        id: 'b',
        name: 'B',
        base: parent.base,
        seeds: Map<String, dynamic>.from(parent.seeds),
        overrides: Map<String, String>.from(parent.overrides),
      );
      final t = resolveSkin(
        choice: const SkinChoice.data('b'),
        shell: HcShell.touch,
        skins: [parent, fork],
      );
      expect(t.accent.warn, const Color(0xFFFF4FD8));
    });

    test('a fork names the built-in it descends from, not its sibling', () {
      // `base` is the fallback. A fork-of-a-fork whose base pointed at another
      // user skin would fall back to something that can itself be deleted.
      final parent = SkinDocument(
        id: 'a',
        name: 'A',
        base: 'soft_home',
        seeds: seedsToJson(builtInSeeds[HcSkin.softHome]!),
      );
      final fork = SkinDocument(
        id: 'b',
        name: 'B',
        base: parent.base,
        seeds: Map<String, dynamic>.from(parent.seeds),
      );
      expect(fork.base, 'soft_home');
      expect(builtInNamed(fork.base), HcSkin.softHome);
    });
  });

  group('the built-in seed table', () {
    test('every built-in has seeds, or the gallery cannot fork it', () {
      for (final skin in HcSkin.values) {
        expect(builtInSeeds[skin], isNotNull,
            reason: '${skin.name} has no seeds — Duplicate would do nothing');
      }
    });
  });
}
