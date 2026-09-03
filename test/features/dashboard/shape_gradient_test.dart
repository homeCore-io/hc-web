import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/features/dashboard/primitive_cards.dart';

/// A shape can be a wash of colour, not only a flat fill.
///
/// **The primitive every mockup needed and the page could not draw.** A hero
/// band is a gradient. Without one the only way to fake a soft wash was a huge
/// circle at low alpha — and a flat fill has a hard boundary however large you
/// make it, which is exactly what two attempts at this page kept showing.
///
/// The painter has no public surface to interrogate, so the test hands it a
/// canvas that remembers what it was given and reads the paint back. That is
/// the only way to tell a gradient from a flat fill without comparing pixels.

/// A canvas that records the paints it is handed and ignores everything else.
class _Recorder implements Canvas {
  final paints = <Paint>[];

  @override
  void drawPath(Path path, Paint paint) => paints.add(paint);

  @override
  void noSuchMethod(Invocation invocation) {}
}

/// The paints [ShapePrimitiveCard] uses for [config], in order.
Future<List<Paint>> paintsFor(
  WidgetTester tester,
  Map<String, dynamic> config,
) async {
  await tester.pumpWidget(MaterialApp(
    theme: hcTheme(HcSkin.midnight, reduceMotion: true),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          height: 120,
          child: ShapePrimitiveCard(config: config),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();

  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(ShapePrimitiveCard),
      matching: find.byType(CustomPaint),
    ),
  );
  final recorder = _Recorder();
  paint.painter!.paint(recorder, const Size(400, 120));
  return recorder.paints;
}

void main() {
  testWidgets('one colour is a flat fill', (tester) async {
    final paints = await paintsFor(tester, const {
      'shape': 'rectangle',
      'fill': '#FFB661',
    });
    expect(paints, isNotEmpty);
    expect(paints.first.shader, isNull);
  });

  testWidgets('a second colour makes it a gradient', (tester) async {
    // Without this a hero band is a hard-edged block, which is what the first
    // two versions of the Office page looked like.
    final paints = await paintsFor(tester, const {
      'shape': 'rectangle',
      'fill': '#FFB661',
      'fill_to': '#00000000',
    });
    expect(paints.first.shader, isNotNull);
    expect(paints.first.shader, isA<ui.Gradient>());
  });

  testWidgets('the angle is honoured, not rounded to a compass point',
      (tester) async {
    // Both are gradients; the point of the test is that an odd angle is a legal
    // thing to ask for. Eight named alignments cannot say 37°, and a gradient
    // you can only point eight ways decides your design for you.
    for (final angle in [0, 37, 90, -145]) {
      final paints = await paintsFor(tester, {
        'shape': 'rectangle',
        'fill': '#FFB661',
        'fill_to': '#7CC4FF',
        'fill_angle': angle,
      });
      expect(paints.first.shader, isNotNull, reason: 'at $angle°');
    }
  });

  testWidgets('a colour nobody can parse leaves the fill flat', (tester) async {
    // Not an error and not a black shape: a colour nobody can read is a colour
    // nobody asked for, and a flat fill is what the shape had before.
    final paints = await paintsFor(tester, const {
      'shape': 'rectangle',
      'fill': '#FFB661',
      'fill_to': 'chartreuse',
    });
    expect(paints.first.shader, isNull);
  });

  testWidgets('a named token works as the far end too', (tester) async {
    final paints = await paintsFor(tester, const {
      'shape': 'rectangle',
      'fill': 'surface',
      'fill_to': 'accent',
    });
    expect(paints.first.shader, isNotNull);
  });
}
