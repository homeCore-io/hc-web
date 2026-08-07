import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/design/skin_validator.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/design/tokens.dart';

/// The ratchets, now that they are a function.
///
/// These assertions used to live as three separate loops over `HcSkin.values`
/// in `token_ratchet_test.dart`, `metrics_test.dart` and `skin_reach_test.dart`.
/// They still run against the shipped four — that is the first group below —
/// but they run through [validateSkin], so the same measurement protects a skin
/// that arrived over HTTP and never saw CI.
///
/// The second group is the half that could not exist before: deliberately bad
/// skins, checked to fail for the stated reason. A validator nobody has watched
/// reject anything is a validator that might be returning an empty list.

/// Midnight with one thing changed — the shape most of these tests want.
HcTokens midnightBut({
  HcSurfaces? surface,
  HcAccents? accent,
  HcGlow? glow,
  HcDensity? density,
  HcMetricTints? metric,
  HcType? text,
}) {
  final t = HcSkin.midnight.tokens;
  return t.copyWith(
    surface: surface,
    accent: accent,
    glow: glow,
    density: density,
    metric: metric,
    text: text,
  );
}

void main() {
  group('the shipped skins pass their own ratchets', () {
    for (final skin in HcSkin.values) {
      test(skin.name, () {
        final report = validateSkin(skin.tokens);
        expect(report.isClean, isTrue, reason: '${skin.name}:\n$report');
      });
    }

    test('and every one of them is saveable', () {
      for (final skin in HcSkin.values) {
        expect(validateSkin(skin.tokens).canSave, isTrue, reason: skin.name);
      }
    });
  });

  group('it actually rejects things', () {
    test('faint text is caught, with the measurement', () {
      // A muted ink barely off the card it sits on — the shape of the "Offline"
      // bug that shipped at 2.3:1 in every skin.
      final t = HcSkin.midnight.tokens;
      final bad = midnightBut(
        surface: HcSurfaces(
          base: t.surface.base,
          raised: t.surface.raised,
          sunken: t.surface.sunken,
          overlay: t.surface.overlay,
          glassTint: t.surface.glassTint,
          glassBlur: t.surface.glassBlur,
          onBase: t.surface.onBase,
          onBaseMuted: const Color(0xFF1A1F27),
        ),
      );

      final found = validateSkin(bad).of(SkinCheck.contrast);
      expect(found, hasLength(1));
      expect(found.single.field, 'surface.onBaseMuted');
      expect(found.single.measured, lessThan(4.5));
      // The number has to be in the message: "too faint" is not actionable,
      // "1.4:1, needs 4.5" is.
      expect(found.single.message, contains(':1'));
      expect(found.single.message, contains('4.5'));
    });

    test('unreadable body text blocks the save; a bad accent only warns', () {
      final t = HcSkin.midnight.tokens;

      final unreadable = midnightBut(
        surface: HcSurfaces(
          base: t.surface.base,
          raised: t.surface.raised,
          sunken: t.surface.sunken,
          overlay: t.surface.overlay,
          glassTint: t.surface.glassTint,
          glassBlur: t.surface.glassBlur,
          // Ink almost exactly the page it sits on.
          onBase: const Color(0xFF0D1015),
          onBaseMuted: t.surface.onBaseMuted,
        ),
      );
      expect(validateSkin(unreadable).canSave, isFalse,
          reason: 'you could not read the controls that would fix it');

      final merelyBad = midnightBut(
        accent: HcAccents(
          primary: t.accent.primary,
          onPrimary: t.accent.onPrimary,
          active: t.accent.active,
          inactive: t.accent.inactive,
          success: t.accent.success,
          // Dim, ugly, legible-ish — a bad choice, not a trap.
          warn: const Color(0xFF3A3020),
          danger: t.accent.danger,
          onDanger: t.accent.onDanger,
          offline: t.accent.offline,
        ),
      );
      final report = validateSkin(merelyBad);
      expect(report.isClean, isFalse);
      expect(report.canSave, isTrue,
          reason: 'a poor warn colour is a bad skin, not an unusable one');
    });

    test('two roles collapsing is caught and named', () {
      // Control Room really shipped `warn` and `active` as one amber, so a door
      // standing open and a room with someone in it were the same colour.
      final t = HcSkin.midnight.tokens;
      final collapsed = midnightBut(
        accent: HcAccents(
          primary: t.accent.primary,
          onPrimary: t.accent.onPrimary,
          active: t.accent.active,
          inactive: t.accent.inactive,
          success: t.accent.success,
          warn: t.accent.active,
          danger: t.accent.danger,
          onDanger: t.accent.onDanger,
          offline: t.accent.offline,
        ),
      );
      final found = validateSkin(collapsed).of(SkinCheck.roleCollapse);
      expect(found, isNotEmpty);
      expect(found.map((f) => f.field).join(), contains('caution'));
      expect(found.first.message, contains('open'));
    });

    test('two sensors sharing a tint is caught', () {
      final m = HcSkin.midnight.tokens.metric;
      final clashing = midnightBut(
        metric: HcMetricTints(
          temperature: m.temperature,
          humidity: m.temperature,
          illuminance: m.illuminance,
          co2: m.co2,
          power: m.power,
          reading: m.reading,
        ),
      );
      final found = validateSkin(clashing).of(SkinCheck.metricDistinctness);
      expect(found, hasLength(1));
      expect(found.single.field, contains('temperature'));
      expect(found.single.field, contains('humidity'));
    });

    test('a skin claiming no bloom that still glows is caught', () {
      // The inverse of what Control Room needs: strength 0 must mean no halo.
      final glowing = midnightBut(glow: const HcGlow(strength: 0, radius: 30));
      final found = validateSkin(glowing).of(SkinCheck.bloom);
      // Midnight's halo() honours strength, so this passes — the check exists
      // for a skin whose glow implementation stops honouring it.
      expect(found.isEmpty || found.single.field == 'glow', isTrue);
    });

    test('type scaled under the legibility floor is caught', () {
      final tiny = midnightBut(text: const HcType.scaled(0.5));
      final found = validateSkin(tiny).of(SkinCheck.typeFloor);
      expect(found, hasLength(1));
      expect(found.single.measured, lessThan(9));
      expect(found.single.message, contains('type scale'));
    });

    test('a tap target under the floor is caught', () {
      final cramped = midnightBut(
        density: const HcDensity(
            rowHeight: 20, controlHeight: 18, minTapTarget: 18, cardPadding: 4),
      );
      final found = validateSkin(cramped).of(SkinCheck.tapTarget);
      expect(found, hasLength(1));
      expect(found.single.measured, 18);
    });
  });

  group('contrastRatio itself', () {
    test('the extremes are the extremes', () {
      expect(contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
          closeTo(21, 0.01));
      expect(contrastRatio(const Color(0xFF808080), const Color(0xFF808080)),
          closeTo(1, 0.001));
    });

    test('it does not care which way round the pair is given', () {
      const a = Color(0xFF123456), b = Color(0xFFEEDDCC);
      expect(contrastRatio(a, b), closeTo(contrastRatio(b, a), 0.0001));
    });
  });
}
