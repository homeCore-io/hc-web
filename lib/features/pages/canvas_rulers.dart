import 'package:flutter/material.dart';

import '../../core/dashboard/canvas_view.dart';
import '../../design/tokens.dart';

/// The edges of the canvas, marked in cells.
///
/// Arc 3. **In cells, not pixels** — and that is the whole design decision.
/// Every other drawing tool rules its canvas in points or millimetres because
/// that is where things can go; here a card can only ever start at a whole
/// column and a whole row, so a ruler reading `137px` would be describing a
/// position nothing can occupy. The status bar already says `at 3,2`; this is
/// where you read that off the canvas instead of counting cards.
///
/// **They are chrome, so they do not scroll** — they are told where the canvas
/// got to and redraw. A ruler inside the scroller would leave the page it
/// measures, which is the one thing a ruler must never do.
///
/// The shaded band is what earns the strip its 20 pixels: it marks where the
/// selection begins and ends on each axis, so *how wide is this and where does
/// it sit* is answerable by looking rather than by reading two numbers off the
/// floor of the window and doing the arithmetic.
class CanvasRuler extends StatelessWidget {
  const CanvasRuler({
    super.key,
    required this.horizontal,
    required this.step,
    required this.scale,
    required this.offset,
    required this.lead,
    required this.cells,
    required this.span,
  });

  /// Across the top, or down the left-hand side.
  final bool horizontal;

  /// One cell plus its gap, in canvas pixels before zoom.
  final double step;
  final double scale;

  /// How far the canvas has scrolled on this axis.
  final double offset;

  /// The padding between the pane and the canvas.
  final double lead;

  /// How many cells to mark. The column count across; enough rows to cover the
  /// page down.
  final int cells;

  /// Where the selection starts and ends on this axis, in cells, or null.
  final (int, int)? span;

  static const thickness = 20.0;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return SizedBox(
      width: horizontal ? null : thickness,
      height: horizontal ? thickness : null,
      child: CustomPaint(
        painter: _RulerPainter(
          horizontal: horizontal,
          step: step,
          scale: scale,
          offset: offset,
          lead: lead,
          cells: cells,
          span: span,
          background: t.surface.raised,
          line: t.stroke.hairline,
          tick: t.surface.onBaseMuted,
          highlight: t.accent.active,
          // The smallest role we ship, unbent. A ruler's numbers are the
          // quietest text in the window by design — they are there to be
          // glanced at, never read.
          style: t.text.overlineStyle.copyWith(
            color: t.surface.onBaseMuted,
            fontFeatures: t.numericFontFeatures,
          ),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  const _RulerPainter({
    required this.horizontal,
    required this.step,
    required this.scale,
    required this.offset,
    required this.lead,
    required this.cells,
    required this.span,
    required this.background,
    required this.line,
    required this.tick,
    required this.highlight,
    required this.style,
  });

  final bool horizontal;
  final double step;
  final double scale;
  final double offset;
  final double lead;
  final int cells;
  final (int, int)? span;
  final Color background;
  final Color line;
  final Color tick;
  final Color highlight;
  final TextStyle style;

  double _along(Size size) => horizontal ? size.width : size.height;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    final length = _along(size);
    final thick = horizontal ? size.height : size.width;

    // The selection's band, under the ticks so the numbers stay readable over
    // it.
    if (span case (final from, final to)) {
      final start = edgeOf(from, step, scale, offset, lead);
      final end = edgeOf(to, step, scale, offset, lead);
      canvas.drawRect(
        horizontal
            ? Rect.fromLTRB(start, 0, end, thick)
            : Rect.fromLTRB(0, start, thick, end),
        Paint()..color = highlight.withValues(alpha: 0.22),
      );
    }

    final stride = tickStride(step, scale);
    final ticks = Paint()
      ..color = tick
      ..strokeWidth = 1;

    for (var n = 0; n <= cells; n++) {
      final at = edgeOf(n, step, scale, offset, lead);
      // Everything off the strip is skipped rather than clipped: a page can be
      // hundreds of rows and only a dozen are ever on screen.
      if (at < -40 || at > length + 40) continue;

      final labelled = n % stride == 0;
      final size0 = labelled ? thick * 0.45 : thick * 0.25;
      canvas.drawLine(
        horizontal ? Offset(at, thick - size0) : Offset(thick - size0, at),
        horizontal ? Offset(at, thick) : Offset(thick, at),
        ticks,
      );
      if (!labelled || n == cells) continue;

      final painter = TextPainter(
        text: TextSpan(text: '$n', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      // Just past the tick, inside the cell it names — a number centred on the
      // line would belong equally to the cell on either side of it.
      painter.paint(
        canvas,
        horizontal ? Offset(at + 3, 2) : Offset(2, at + 1),
      );
    }

    canvas.drawLine(
      horizontal ? Offset(0, thick - 0.5) : Offset(thick - 0.5, 0),
      horizontal ? Offset(length, thick - 0.5) : Offset(thick - 0.5, length),
      Paint()
        ..color = line
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.offset != offset ||
      old.scale != scale ||
      old.step != step ||
      old.lead != lead ||
      old.cells != cells ||
      old.span != span ||
      old.background != background;
}
