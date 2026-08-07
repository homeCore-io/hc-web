import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/design/skin_seeds.dart';
import 'package:hc_web/design/skins.dart';
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

/// The seeds each shipped skin is made of.
final seeds = <HcSkin, SkinSeeds>{
  HcSkin.midnight: const SkinSeeds(
    name: 'midnight',
    brightness: Brightness.dark,
    ground: Color(0xFF0B0E13),
    raised: Color(0xFF141922),
    sunken: Color(0xFF0D1116),
    overlay: Color(0xFF1A202A),
    ink: Color(0xFFE9EDF2),
    inkMuted: Color(0xFF8B95A4),
    accent: Color(0xFF7CC4FF),
    onAccent: Color(0xFF06131F),
    active: Color(0xFFFFB661),
    inactive: Color(0xFF2A313B),
    success: Color(0xFF6FD1A6),
    warn: Color(0xFFFFC978),
    danger: Color(0xFFFF7B72),
    offline: Color(0xFFAA737A),
    hairline: Color(0xFF262D38),
    corners: (4, 8, 14, 22),
    spaceUnit: 8,
    typeScale: 1,
    glowStrength: 1,
    glowRadius: 34,
    density: SkinDensity.comfortable,
    motion: SkinMotion.standard,
  ),
  HcSkin.ambientGlass: const SkinSeeds(
    name: 'ambient_glass',
    brightness: Brightness.dark,
    ground: Color(0xFF0B0D10),
    raised: Color(0xFF14181D),
    sunken: Color(0xFF080A0C),
    overlay: Color(0xFF161A20),
    ink: Color(0xFFF2F5F8),
    inkMuted: Color(0xFF8D97A3),
    accent: Color(0xFF7CC4FF),
    onAccent: Color(0xFF06131F),
    active: Color(0xFFFFB661),
    inactive: Color(0xFF3A424D),
    success: Color(0xFF5FD6A2),
    warn: Color(0xFFFFC978),
    danger: Color(0xFFFF7B72),
    offline: Color(0xFFA07680),
    hairline: Color(0x1FFFFFFF),
    corners: (5, 10, 18, 26),
    spaceUnit: 8,
    typeScale: 1.15,
    glowStrength: 1,
    glowRadius: 44,
    density: SkinDensity.wall,
    motion: SkinMotion.calm,
    glass: SkinGlass.frosted,
  ),
  HcSkin.controlRoom: const SkinSeeds(
    name: 'control_room',
    brightness: Brightness.dark,
    ground: Color(0xFF08090A),
    raised: Color(0xFF0F1114),
    sunken: Color(0xFF050607),
    overlay: Color(0xFF131619),
    ink: Color(0xFFE6E9ED),
    inkMuted: Color(0xFF7A828C),
    accent: Color(0xFF38BDF8),
    onAccent: Color(0xFF04141D),
    active: Color(0xFFFBBF24),
    inactive: Color(0xFF2A2F35),
    success: Color(0xFF34D399),
    warn: Color(0xFFD97706),
    danger: Color(0xFFF87171),
    offline: Color(0xFFB3666E),
    hairline: Color(0xFF1E2126),
    corners: (2, 3, 5, 8),
    spaceUnit: 6,
    typeScale: 0.92,
    glowStrength: 0,
    glowRadius: 0,
    density: SkinDensity.compact,
    motion: SkinMotion.crisp,
    // Control Room names its own sensor hues: the shared palette is tuned for
    // a bloom this skin does not have.
    metric: HcMetricTints(
      temperature: Color(0xFFFB923C),
      humidity: Color(0xFF22D3EE),
      illuminance: Color(0xFFFDE047),
      co2: Color(0xFF34D399),
      power: Color(0xFFFBBF24),
      reading: Color(0xFF38BDF8),
    ),
  ),
  HcSkin.softHome: const SkinSeeds(
    name: 'soft_home',
    brightness: Brightness.light,
    ground: Color(0xFFF7F4EF),
    raised: Color(0xFFFFFFFF),
    sunken: Color(0xFFEFEAE2),
    overlay: Color(0xFFFFFFFF),
    ink: Color(0xFF241F1A),
    inkMuted: Color(0xFF706861),
    accent: Color(0xFFA65135),
    onAccent: Color(0xFFFFFFFF),
    active: Color(0xFF925E11),
    inactive: Color(0xFFD8D0C6),
    success: Color(0xFF447359),
    warn: Color(0xFF915C1C),
    danger: Color(0xFFC0524B),
    offline: Color(0xFF936C6F),
    hairline: Color(0xFFE2DACE),
    corners: (6, 12, 20, 28),
    spaceUnit: 8,
    typeScale: 1,
    glowStrength: 0.35,
    glowRadius: 26,
    density: SkinDensity.comfortable,
    motion: SkinMotion.standard,
    glass: SkinGlass.tinted,
    focus: Color(0xFFC2603F),
    densityOverride: HcDensity(
        rowHeight: 56, controlHeight: 48, minTapTarget: 48, cardPadding: 18),
    motionOverride: HcMotion(
      fast: Duration(milliseconds: 130),
      base: Duration(milliseconds: 260),
      slow: Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      emphasized: Curves.easeOutBack,
      enabled: true,
    ),
    // A light ground needs darker sensor hues than any accent-derived value.
    metric: HcMetricTints(
      temperature: Color(0xFF803B1E),
      humidity: Color(0xFF266C87),
      illuminance: Color(0xFF74570B),
      co2: Color(0xFF2D7B5B),
      power: Color(0xFF5C370A),
      reading: Color(0xFF2F4774),
    ),
  ),
};

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
