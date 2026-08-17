import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/design_tools.dart';

/// The toolbar as data.
///
/// The point of keeping the tool set out of the widget is that these questions
/// can be asked without building anything: what does dragging with this make,
/// which key reaches it, and can two tools claim the same key. The last one is
/// the bug this file exists to prevent — a duplicate shortcut is invisible
/// until somebody presses it and gets the wrong tool.

void main() {
  test('every tool has a key, and no two share one', () {
    final keys = DesignTool.values.map((t) => t.shortcut).toList();
    expect(keys.toSet().length, keys.length,
        reason: 'duplicate shortcut in: $keys');
    for (final tool in DesignTool.values) {
      expect(tool.shortcut, matches(RegExp(r'^[A-Z]$')),
          reason: '${tool.name} must be one bare capital letter');
    }
  });

  test('the key finds the tool, in either case', () {
    expect(DesignTool.forKey('t'), DesignTool.text);
    expect(DesignTool.forKey('T'), DesignTool.text);
    expect(DesignTool.forKey('v'), DesignTool.select);
    expect(DesignTool.forKey('q'), isNull);
  });

  test('select is the only tool that makes nothing', () {
    for (final tool in DesignTool.values) {
      expect(tool.draws, tool != DesignTool.select, reason: tool.name);
    }
  });

  test('a drawing tool names a type; the catalogue asks instead', () {
    for (final tool in DesignTool.values.where((t) => t.draws)) {
      expect(tool.type != null || tool.picks, isTrue, reason: tool.name);
    }
    expect(DesignTool.card.type, isNull);
    expect(DesignTool.card.picks, isTrue);
  });

  test('the primitives start visible', () {
    // Every default here earns its place by making the new element findable on
    // the canvas you just drew it on. A shape with no fill and text at caption
    // size are both things you have to hunt for.
    expect(DesignTool.shape.defaults['fill'], isNotNull);
    expect(DesignTool.text.defaults['size'], isNotNull);
    expect(DesignTool.line.defaults['ink'], isNotNull);
  });

  test('every tool says what it is and carries an icon', () {
    for (final tool in DesignTool.values) {
      expect(tool.label, isNotEmpty);
      expect(tool.icon, isNotEmpty);
    }
  });

  group('the rectangle a drag describes', () {
    // In **pixels**, which is the whole point. A cell on a twelve-column
    // desktop layout is about 130 by 120, so a rule drawn in cells is a
    // two-by-four block with a hairline lost inside it.

    test('a shape is exactly the rectangle dragged', () {
      final d = toolDrawing(
          DesignTool.shape, const Offset(100, 50), const Offset(340, 210));
      expect(d.rect.x, 100);
      expect(d.rect.y, 50);
      expect(d.rect.w, 240);
      expect(d.rect.h, 160);
    });

    test('dragging up and left makes the same rectangle as down and right', () {
      // Otherwise half of all drags produce a negative width and nothing
      // appears, which reads as the tool not working rather than as a rule.
      final a = toolDrawing(
          DesignTool.shape, const Offset(10, 10), const Offset(210, 130));
      final b = toolDrawing(
          DesignTool.shape, const Offset(210, 130), const Offset(10, 10));
      expect(a.rect.x, b.rect.x);
      expect(a.rect.y, b.rect.y);
      expect(a.rect.w, b.rect.w);
      expect(a.rect.h, b.rect.h);
    });

    test('a click still makes something you can see and take hold of', () {
      final d = toolDrawing(
          DesignTool.shape, const Offset(80, 80), const Offset(80, 80));
      expect(d.rect.w, greaterThan(24));
      expect(d.rect.h, greaterThan(24));
    });

    group('a line is a line', () {
      test('the angle comes from the drag, so a diagonal is a diagonal', () {
        final d = toolDrawing(
            DesignTool.line, const Offset(0, 0), const Offset(100, 100));
        expect(d.config['angle'], 45);
      });

      test('and it runs the other way when you drag the other way', () {
        final d = toolDrawing(
            DesignTool.line, const Offset(0, 100), const Offset(100, 0));
        expect(d.config['angle'], -45);
      });

      test('a level drag is level', () {
        final d = toolDrawing(
            DesignTool.line, const Offset(20, 60), const Offset(300, 60));
        expect(d.config['angle'], 0);
        expect(d.rect.w, 280);
      });

      test('a level line still gets a band you can hit', () {
        // A zero-height element cannot be grabbed, resized, or even seen to
        // be selected.
        final d = toolDrawing(
            DesignTool.line, const Offset(20, 60), const Offset(300, 60));
        expect(d.rect.h, greaterThanOrEqualTo(8));
        // Centred on the drag, so the stroke lands where the pointer went
        // rather than below it.
        expect(d.rect.y + d.rect.h / 2, closeTo(60, 0.01));
      });

      test('a plumb drag is plumb', () {
        final d = toolDrawing(
            DesignTool.line, const Offset(60, 20), const Offset(60, 300));
        expect(d.config['angle'], 90);
        expect(d.rect.h, 280);
        expect(d.rect.w, greaterThanOrEqualTo(8));
      });

      test('a click makes a rule, not a dot', () {
        // The band floor alone would hand back a 12×12 stub, which reads as
        // the tool being broken rather than as a very short line.
        final d = toolDrawing(
            DesignTool.line, const Offset(200, 200), const Offset(200, 200));
        expect(d.rect.w, greaterThan(100));
        expect(d.rect.h, lessThan(20));
        expect(d.config['angle'], 0);
      });

      test('the angle is a whole number, because it is read in a form', () {
        final d = toolDrawing(
            DesignTool.line, const Offset(0, 0), const Offset(100, 93));
        expect(d.config['angle'], isA<int>());
      });
    });

    group('text is as tall as its type', () {
      test('one line tall by default, not one row of the grid', () {
        // John: *"Why is the text so small in the large rectangle."* Because
        // the box was a grid cell and the words were type.
        final d = toolDrawing(
          DesignTool.text,
          const Offset(0, 0),
          const Offset(300, 4),
          lineHeight: 22,
        );
        expect(d.rect.h, 22);
        expect(d.rect.w, 300);
      });

      test('unless you dragged a taller box, which is you asking', () {
        final d = toolDrawing(
          DesignTool.text,
          const Offset(0, 0),
          const Offset(300, 200),
          lineHeight: 22,
        );
        expect(d.rect.h, 200);
      });
    });

    test('every drawing carries the tool’s own defaults', () {
      for (final tool in DesignTool.values.where((t) => t.type != null)) {
        final d = toolDrawing(tool, const Offset(0, 0), const Offset(50, 50));
        for (final key in tool.defaults.keys) {
          expect(d.config[key], tool.defaults[key], reason: tool.name);
        }
      }
    });
  });
}
