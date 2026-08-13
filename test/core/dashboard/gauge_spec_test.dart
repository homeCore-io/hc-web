import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/gauge_spec.dart';
import 'package:hc_web/features/dashboard/gauge_card.dart';

/// The gauge, once it stopped being one fixed shape.
void main() {
  group('a gauge already on a page', () {
    // The whole risk of this change: someone's dial quietly becoming a
    // different dial. Every default is the constant it replaced.
    test('is drawn exactly as it was', () {
      const spec = GaugeSpec();
      expect(spec.shape, GaugeShape.radial);
      expect(spec.startDegrees, 135);
      expect(spec.sweepDegrees, 270);
      expect(spec.roundCap, isTrue);
      expect(spec.track, isTrue);
      expect(spec.glow, 0);
      expect(spec.readout, GaugeReadout.value);
      // 3π/4 and 3π/2 — the two constants that used to live in the painter.
      expect(spec.startRadians, closeTo(3 * math.pi / 4, 1e-9));
      expect(spec.sweepRadians, closeTo(3 * math.pi / 2, 1e-9));
      // 9% of the shorter side.
      expect(spec.strokeFor(200), closeTo(18, 1e-9));
    });

    test('and a config with only the old keys changes nothing', () {
      final spec = GaugeSpec.fromConfig(const {
        'device_id': 'a',
        'attribute': 'temperature',
        'min': 0,
        'max': 100,
        'unit': '°F',
      });
      expect(spec, isA<GaugeSpec>());
      expect(spec.startDegrees, 135);
      expect(spec.sweepDegrees, 270);
      expect(spec.color, isNull, reason: 'the reading keeps its own colour');
    });
  });

  group('the parameters', () {
    test('read the drawing out of the config', () {
      final spec = GaugeSpec.fromConfig(const {
        'shape': 'bar',
        'start': 180,
        'sweep': -170,
        'thickness': 10,
        'cap': 'flat',
        'track': false,
        'color': 'success',
        'color_to': 'primary',
        'glow': 40,
        'readout': 'none',
        'decimals': 2,
        'label': 'miles',
      });
      expect(spec.shape, GaugeShape.bar);
      expect(spec.startDegrees, 180);
      expect(spec.sweepDegrees, -170,
          reason: 'a mirrored flank runs backwards');
      expect(spec.thickness, 10);
      expect(spec.roundCap, isFalse);
      expect(spec.track, isFalse);
      expect(spec.readout, GaugeReadout.none);
      expect(spec.decimals, 2);
      expect(spec.label, 'miles');
    });

    test('a fixed thickness holds across sizes, so a stack stays even', () {
      const spec = GaugeSpec(thickness: 9);
      expect(spec.strokeFor(200), 9);
      expect(spec.strokeFor(120), 9);
      // …but never wider than the gauge itself.
      expect(spec.strokeFor(10), 5);
    });

    test('a hand-edited document cannot draw nonsense', () {
      final spec = GaugeSpec.fromConfig(const {
        'start': 5000,
        'sweep': -9000,
        'glow': 999,
        'decimals': 99,
      });
      expect(spec.startDegrees, 360);
      expect(spec.sweepDegrees, -360);
      expect(spec.glow, 100);
      expect(spec.decimals, 6);
    });
  });

  group('the value', () {
    test('sits where it should in its range', () {
      expect(GaugeSpec.fractionOf(50, 0, 100), 0.5);
      expect(GaugeSpec.fractionOf(-10, 0, 100), 0.0, reason: 'clamped');
      expect(GaugeSpec.fractionOf(200, 0, 100), 1.0);
      expect(GaugeSpec.fractionOf(72.5, 60, 85), closeTo(0.5, 1e-9));
    });

    test('is nothing when it cannot be drawn', () {
      expect(GaugeSpec.fractionOf(null, 0, 100), isNull);
      // A range of zero is a mistake, not a reason to render a broken dial.
      expect(GaugeSpec.fractionOf(5, 10, 10), isNull);
      expect(GaugeSpec.fractionOf(5, 100, 0), isNull);
    });

    test('reads as a person would write it', () {
      expect(formatGaugeValue(8, null), '8');
      expect(formatGaugeValue(21.4, null), '21.4');
      expect(formatGaugeValue(21.400000000000002, null), '21.4');
      expect(formatGaugeValue(3, 2), '3.00');
    });
  });
}
