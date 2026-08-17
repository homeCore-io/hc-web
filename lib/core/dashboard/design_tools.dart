/// The toolbar: what you are holding, and what dragging with it makes.
///
/// **This is the gesture that was missing.** Until now an element arrived one
/// way: open a catalogue, find an entry, click it, and something appears at the
/// engine's first fit — then move it, then resize it. That is a content-
/// management interaction, and it is the reason the designer read as a form
/// with a preview rather than as a design application. Every drawing tool in
/// existence works the other way round: you hold a tool, you drag, and the
/// thing exists at the size and place you dragged it.
///
/// The catalogue does not go away — a device grid genuinely is chosen from a
/// list of what the house can show. It stops being the *only* way in.
///
/// Pure: what a tool is, and what config it hands a new element. What the
/// toolbar looks like is `features/pages/tool_palette.dart`; the drag lives on
/// the board in `page_grid.dart`.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'grid_engine.dart' show DashboardRect;

/// One thing you can be holding.
///
/// A tool is a *type plus a starting config*, not a widget class, which is why
/// this is data and not a set of subclasses: adding "drag out a gauge" needs a
/// row here and nothing else, and every element the registry knows is
/// reachable this way in principle.
enum DesignTool {
  /// The default, and the one you return to after every other. Dragging
  /// selects; nothing is created.
  select(
    label: 'Select',
    shortcut: 'V',
    icon: 'cursor',
  ),

  /// Words. The first tool anyone reaches for on an empty page.
  text(
    label: 'Text',
    shortcut: 'T',
    icon: 'text',
    type: 'text',
    defaults: {'size': 'title', 'align': 'start', 'vertical': 'middle'},
  ),

  /// A filled path. Defaults to a rectangle because that is what dragging a
  /// box means everywhere else, and the kind is one click away in the
  /// inspector.
  shape(
    label: 'Shape',
    shortcut: 'R',
    icon: 'shape',
    type: 'shape',
    defaults: {'shape': 'rectangle', 'fill': 'accent', 'opacity': 20},
  ),

  /// A rule at an angle.
  ///
  /// **Muted, not hairline.** A hairline is the colour of a card's border: it
  /// is meant to be barely there against the surface it sits on, and a line
  /// drawn in it on the page's own ground is invisible — which reads as the
  /// tool being broken, not as a subtle line. `hairline` is still on the
  /// palette for anyone who wants it.
  line(
    label: 'Line',
    shortcut: 'L',
    icon: 'line',
    type: 'line',
    defaults: {'ink': 'muted'},
  ),

  /// A picture. The element exists already; what is new is drawing its box
  /// before choosing the file, which is the order anybody laying out a page
  /// actually works in.
  image(
    label: 'Image',
    shortcut: 'I',
    icon: 'image',
    type: 'image',
  ),

  /// One reading against a range.
  gauge(
    label: 'Gauge',
    shortcut: 'G',
    icon: 'gauge',
    type: 'gauge',
  ),

  /// Markup the author writes, run in a sandbox.
  code(
    label: 'Code',
    shortcut: 'C',
    icon: 'code',
    type: 'code',
  ),

  /// The catalogue, opened as a tool rather than as a permanent panel.
  ///
  /// Everything the house can show is here — a device grid, the rooms query, a
  /// history chart — and none of it can be *drawn*, because what it draws is
  /// decided by what you pick. So this tool opens the picker, and the rectangle
  /// you dragged becomes the card's placement.
  card(
    label: 'Card',
    shortcut: 'A',
    icon: 'card',
    picks: true,
  );

  const DesignTool({
    required this.label,
    required this.shortcut,
    required this.icon,
    this.type,
    this.defaults = const {},
    this.picks = false,
  });

  final String label;

  /// The single key that reaches it, shown on the button. A design tool whose
  /// tools need a menu is a design tool nobody is fast in.
  final String shortcut;

  /// A name resolved to an `IconData` by the palette. A string rather than the
  /// icon itself so this file stays free of Flutter — the tool set is data the
  /// tests can read.
  final String icon;

  /// The element type a drag creates, or null when the tool creates nothing
  /// ([select]) or has to ask first ([card]).
  final String? type;

  /// The config a newly drawn element starts with.
  ///
  /// Deliberately sparse. Every key here is one the author will have to notice
  /// and undo if it is wrong, so it holds only what makes the new element
  /// *visible* — a shape with no fill and text at caption size are both things
  /// you have to hunt for on the canvas you just drew them on.
  final Map<String, Object> defaults;

  /// The tool asks what to make before making it.
  final bool picks;

  /// True when dragging with this tool draws a new element.
  bool get draws => type != null || picks;

  /// The tool a key press means, or null for a key that is not a tool.
  ///
  /// Single letters, unmodified — the convention every design application
  /// shares. They only bind on the canvas, so typing a card's name still types
  /// letters; see `_CanvasKeys` for why that scoping is what makes bare letters
  /// safe.
  static DesignTool? forKey(String key) {
    final upper = key.toUpperCase();
    for (final tool in DesignTool.values) {
      if (tool.shortcut == upper) return tool;
    }
    return null;
  }
}

/// What a drag makes: a rectangle in canvas pixels, and config the gesture
/// itself decided.
typedef ToolDrawing = ({DashboardRect rect, Map<String, Object> config});

/// The element [tool] makes from a drag between two points **in canvas
/// pixels**.
///
/// **Pixels, not cells, and this is the whole point.** A cell on a twelve
/// column desktop layout is about 130 by 120, so a line drawn in cells is a
/// two-by-four block with a hairline somewhere inside it, and a caption is a
/// word floating in a rectangle four times its height. That is a dashboard
/// grid pretending to be a design tool. The document has been able to express
/// a rectangle since the composition arc — `DashboardRect` is the truth and the
/// cells are a snapped approximation of it — and drawing simply has to use it.
///
/// Each tool reads the drag differently, because the gesture means different
/// things:
///
///   * a **shape** is the rectangle you dragged, exactly;
///   * a **line** is the *line* between the two points — the box is only its
///     bounding box, and the angle comes from the drag, so pulling a diagonal
///     gives you a diagonal rather than a diagonal-shaped box;
///   * **text** is as wide as you dragged and one line tall, because a text
///     box taller than its type is a box with a word floating in it. Drag
///     taller if you want taller; [lineHeight] is only the floor.
///
/// [lineHeight] comes from the caller because it is a skin decision — the type
/// ramp scales per skin, so a number here would be a second type system.
ToolDrawing toolDrawing(
  DesignTool tool,
  Offset from,
  Offset to, {
  double lineHeight = 24,
}) {
  final left = math.min(from.dx, to.dx);
  final top = math.min(from.dy, to.dy);
  final width = (from.dx - to.dx).abs();
  final height = (from.dy - to.dy).abs();

  switch (tool) {
    case DesignTool.line:
      // The drag *is* the line. `_LinePainter` runs a line at [angle] out to
      // the edge of its box, so the bounding box of the two points plus the
      // angle between them reproduces exactly the stroke that was drawn —
      // corner to corner for a diagonal, and across the middle for a level
      // one.
      final angle =
          math.atan2(to.dy - from.dy, to.dx - from.dx) * 180 / math.pi;
      // A click is a drag of no length, and a line of no length is a dot: the
      // band floor alone would hand back a 12×12 stub that reads as the tool
      // being broken. So a click makes a rule of a usable length, level,
      // which is the line anybody drawing one by clicking meant.
      if (width < _grab && height < _grab) {
        return (
          rect: DashboardRect(
              x: left - _minLine / 2,
              y: top - _grab / 2,
              w: _minLine,
              h: _grab),
          config: {...tool.defaults, 'angle': 0},
        );
      }
      // A level or plumb drag has no thickness at all, and a zero-height
      // element cannot be grabbed, resized or even seen to be selected. The
      // band is the smallest thing a pointer can reasonably hit.
      final w = width < _grab ? _grab : width;
      final h = height < _grab ? _grab : height;
      return (
        rect: DashboardRect(
          x: left - (w - width) / 2,
          y: top - (h - height) / 2,
          w: w,
          h: h,
        ),
        config: {...tool.defaults, 'angle': _round(angle)},
      );

    case DesignTool.text:
      return (
        rect: DashboardRect(
          x: left,
          y: top,
          w: width < _minText ? _minText : width,
          h: height < lineHeight ? lineHeight : height,
        ),
        config: {...tool.defaults},
      );

    default:
      return (
        rect: DashboardRect(
          x: left,
          y: top,
          w: width < _minBox ? _minBox : width,
          h: height < _minBox ? _minBox : height,
        ),
        config: {...tool.defaults},
      );
  }
}

/// The smallest band a pointer can reasonably hit, in logical pixels.
const double _grab = 12;

/// Floors for a click rather than a drag — big enough to see and to take hold
/// of, small enough that nobody mistakes them for the size they asked for.
const double _minBox = 48;
const double _minText = 80;

/// The length a clicked line gets. Long enough to be a rule you can see and
/// grab an end of, short enough to be obviously a starting point.
const double _minLine = 160;

/// Whole degrees. A line at 42.7° is a number nobody typed and nobody wants to
/// read in an inspector; the half-degree it costs is invisible.
int _round(double degrees) => degrees.round();
