import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/design/builtin_seeds.dart';
import 'package:hc_web/design/skin_seeds.dart';
import 'package:hc_web/design/tokens.dart';

/// Can the four shipped skins be rebuilt from seeds?
///
/// This is the question step 1 of `theme-editor-plan.md` exists to answer, and
/// the reason it is worth answering first: a seed set that cannot express the
/// skins already on screen is not a seed set, it is a guess. Every later piece
/// — skins in core, an editor, a live validator — is built on the assumption
/// that a handful of decisions determines a skin, and this is where that
/// assumption is either true or gets corrected.
///
/// None of the token classes implement `==`, which turns out to be the better
/// situation: the diff below names the field that failed rather than saying
/// "not equal", and that name is what makes the derivation improvable.

/// Every field of a skin, flattened to `path -> value`, so two skins can be
/// compared by what actually differs.
Map<String, Object?> flatten(HcTokens t) => {
      'name': t.name,
      'brightness': t.brightness,
      'surface.base': t.surface.base,
      'surface.raised': t.surface.raised,
      'surface.sunken': t.surface.sunken,
      'surface.overlay': t.surface.overlay,
      'surface.glassTint': t.surface.glassTint,
      'surface.glassBlur': t.surface.glassBlur,
      'surface.onBase': t.surface.onBase,
      'surface.onBaseMuted': t.surface.onBaseMuted,
      'accent.primary': t.accent.primary,
      'accent.onPrimary': t.accent.onPrimary,
      'accent.active': t.accent.active,
      'accent.inactive': t.accent.inactive,
      'accent.success': t.accent.success,
      'accent.warn': t.accent.warn,
      'accent.danger': t.accent.danger,
      'accent.onDanger': t.accent.onDanger,
      'accent.offline': t.accent.offline,
      'stroke.hairline': t.stroke.hairline,
      'stroke.width': t.stroke.width,
      'stroke.focus': t.stroke.focus,
      'radius.xs': t.radius.xs,
      'radius.sm': t.radius.sm,
      'radius.md': t.radius.md,
      'radius.lg': t.radius.lg,
      'radius.pill': t.radius.pill,
      'space.unit': t.space.unit,
      'motion.fast': t.motion.fast,
      'motion.base': t.motion.base,
      'motion.slow': t.motion.slow,
      'motion.curve': t.motion.curve,
      'motion.emphasized': t.motion.emphasized,
      'motion.enabled': t.motion.enabled,
      'glow.strength': t.glow.strength,
      'glow.radius': t.glow.radius,
      'density.rowHeight': t.density.rowHeight,
      'density.controlHeight': t.density.controlHeight,
      'density.minTapTarget': t.density.minTapTarget,
      'density.cardPadding': t.density.cardPadding,
      'elevation.card': _shadows(t.elevation.card),
      'elevation.overlay': _shadows(t.elevation.overlay),
      'metric.temperature': t.metric.temperature,
      'metric.humidity': t.metric.humidity,
      'metric.illuminance': t.metric.illuminance,
      'metric.co2': t.metric.co2,
      'metric.power': t.metric.power,
      'metric.reading': t.metric.reading,
      'text.scale': t.text.scale,
      'text.family': t.text.family,
      'text.monoFamily': t.text.monoFamily,
    };

String _shadows(List<BoxShadow> s) => s
    .map((b) =>
        '${b.color.toARGB32().toRadixString(16)}/${b.blurRadius}/${b.offset.dy}')
    .join(' ');

/// Field paths where derived and shipped disagree, with both values — the
/// output that tells you what to fix.
List<String> diff(HcTokens derived, HcTokens shipped) {
  final a = flatten(derived), b = flatten(shipped);
  return [
    for (final k in b.keys)
      if (a[k].toString() != b[k].toString())
        '$k: derived ${a[k]} != shipped ${b[k]}',
  ];
}

final seeds = builtInSeeds;

void main() {
  group('the derivation is a real function of its seeds', () {
    test('same seeds, same tokens — no hidden state anywhere', () {
      for (final s in seeds.values) {
        expect(diff(deriveTokens(s), deriveTokens(s)), isEmpty,
            reason: '${s.name} does not derive deterministically');
      }
    });

    test('the shape groups fall out of one number each', () {
      // The claim that makes twelve controls able to drive seventy-four
      // tokens. If any of these needed hand values, the seed set would not be
      // a seed set.
      for (final entry in seeds.entries) {
        final d = deriveTokens(entry.value);
        final shipped = entry.key.tokens;
        for (final field in [
          'radius.xs',
          'radius.sm',
          'radius.md',
          'radius.lg',
          'radius.pill',
          'space.unit',
          'density.rowHeight',
          'density.controlHeight',
          'density.minTapTarget',
          'density.cardPadding',
          'motion.fast',
          'motion.base',
          'motion.slow',
          'motion.curve',
          'motion.emphasized',
          'motion.enabled',
          'glow.strength',
          'text.scale',
          'surface.base',
          'surface.onBase',
          'accent.primary',
          'accent.active',
          'accent.success',
          'accent.warn',
          'accent.danger',
          'accent.offline',
          'stroke.width',
        ]) {
          expect(
              flatten(d)[field].toString(), flatten(shipped)[field].toString(),
              reason: '${entry.value.name}: $field should derive');
        }
      }
    });
  });

  group('every shipped skin is reachable from seeds', () {
    // The measure that matters. A field the derivation cannot reach is either
    // a rule not written yet or a value that is genuinely a choice — and the
    // list below says which, per skin, so it can be argued with.
    for (final entry in seeds.entries) {
      test(entry.value.name, () {
        final d = diff(deriveTokens(entry.value), entry.key.tokens);
        expect(d, isEmpty,
            reason: '${entry.value.name} cannot be rebuilt from its seeds:\n'
                '  ${d.join('\n  ')}');
      });
    }
  });
}
