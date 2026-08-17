/// Text, shapes and lines — the parts a page is *drawn* from.
///
/// Every element until now answers "which devices, presented how". That is a
/// content model, and it is why a page could only ever be a mosaic of device
/// cards: there was nothing to put between them. A heading, a rule under it, a
/// panel behind a group, an octagon for a stop button — none of those are about
/// a device at all, and none of them could be made.
///
/// **These are not cards.** A card is a titled, bordered, padded surface that
/// holds something. A shape is a filled path; a line is a rule; text is words
/// at a size you chose. They draw to their own edges and carry no chrome, which
/// is the difference between composing a page and filling in a form.
///
/// Pure: what a shape *is* geometrically, and what the defaults are. Painting
/// is `features/dashboard/primitive_cards.dart`.
library;

import 'dart:typed_data';
import 'dart:ui';

/// The shapes a person can reach without writing a path.
///
/// Deliberately short. Every one of these is a shape people actually ask for —
/// the octagon is a stop button, the pill is a status chip — and a longer list
/// would be a menu to read rather than a set to know. Anything else is
/// [ShapeKind.path], which takes an SVG path and can be anything at all.
enum ShapeKind {
  rectangle,
  circle,
  pill,
  octagon,
  path;

  static ShapeKind from(Object? raw) => switch (raw) {
        'circle' => ShapeKind.circle,
        'pill' => ShapeKind.pill,
        'octagon' => ShapeKind.octagon,
        'path' => ShapeKind.path,
        _ => ShapeKind.rectangle,
      };

  String get label => switch (this) {
        ShapeKind.rectangle => 'Rectangle',
        ShapeKind.circle => 'Circle',
        ShapeKind.pill => 'Pill',
        ShapeKind.octagon => 'Octagon',
        ShapeKind.path => 'Your own path',
      };
}

/// The outline of [kind] at [size].
///
/// **One path for the fill, the border, the shadow and the hit area.** That is
/// the whole reason this returns a path rather than a `ShapeBorder` or a set of
/// radii: a shape whose fill was an octagon and whose tap target was still the
/// bounding rectangle would be a picture of a button rather than a button.
///
/// [corner] is only read for a rectangle — a circle has no corners, a pill's
/// radius *is* half its height, and an octagon's bevel is proportional. Taking
/// the value anyway and ignoring it where it means nothing keeps the caller
/// from having to know which shapes care.
Path shapePath(ShapeKind kind, Size size, {double corner = 0, String? path}) {
  final w = size.width, h = size.height;
  switch (kind) {
    case ShapeKind.rectangle:
      final r = corner.clamp(0.0, (w < h ? w : h) / 2);
      return Path()
        ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, w, h), Radius.circular(r)));
    case ShapeKind.circle:
      // An ellipse in its box, not a circle of the smaller side. A "circle"
      // stretched to its element is what every drawing tool gives you, and
      // insisting on a true circle would mean the element and the shape
      // disagreed about where the edges were.
      return Path()..addOval(Rect.fromLTWH(0, 0, w, h));
    case ShapeKind.pill:
      return Path()
        ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, w, h), Radius.circular((h < w ? h : w) / 2)));
    case ShapeKind.octagon:
      // The proportions the mock draws: a 30% bevel on each corner, which is
      // what makes it read as a stop sign rather than as a clipped rectangle.
      final bx = w * 0.3, by = h * 0.3;
      return Path()
        ..moveTo(bx, 0)
        ..lineTo(w - bx, 0)
        ..lineTo(w, by)
        ..lineTo(w, h - by)
        ..lineTo(w - bx, h)
        ..lineTo(bx, h)
        ..lineTo(0, h - by)
        ..lineTo(0, by)
        ..close();
    case ShapeKind.path:
      final parsed = path == null ? null : tryParsePath(path);
      // A path that does not parse falls back to the rectangle rather than
      // drawing nothing. An element that vanishes while you are typing its
      // path is an element you cannot find again to fix.
      return parsed ?? shapePath(ShapeKind.rectangle, size, corner: corner);
  }
}

/// An SVG path, scaled into [size] by its caller.
///
/// Null rather than throwing: this is fed by a text field somebody is halfway
/// through typing into, so "not valid yet" is the normal case and not an error.
Path? tryParsePath(String d) {
  if (d.trim().isEmpty) return null;
  try {
    final path = _parseSvgPath(d);
    return path.getBounds().isEmpty ? null : path;
  } catch (_) {
    return null;
  }
}

/// How text sits in its element.
enum TextAlignChoice {
  start,
  center,
  end;

  static TextAlignChoice from(Object? raw) => switch (raw) {
        'center' => TextAlignChoice.center,
        'end' => TextAlignChoice.end,
        _ => TextAlignChoice.start,
      };
}

/// A minimal subset of SVG path syntax: M, L, H, V, C, Q, Z, absolute and
/// relative.
///
/// Deliberately not a full implementation — arcs are missing, and so are the
/// shorthand curve forms. It covers what a person pastes out of a drawing
/// program for a *shape*, and anything richer belongs in the SVG element,
/// which renders a whole document through the platform view and does not go
/// through this at all.
Path _parseSvgPath(String d) {
  final path = Path();
  final tokens = RegExp(r'[A-Za-z]|-?\d*\.?\d+(?:e-?\d+)?')
      .allMatches(d)
      .map((m) => m.group(0)!)
      .toList();
  var i = 0;
  var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0;
  String? cmd;

  double num_() => double.parse(tokens[i++]);

  while (i < tokens.length) {
    final token = tokens[i];
    if (RegExp(r'[A-Za-z]').hasMatch(token)) {
      cmd = token;
      i++;
      if (cmd.toUpperCase() == 'Z') {
        path.close();
        x = startX;
        y = startY;
        cmd = null;
        continue;
      }
    }
    if (cmd == null) break;
    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        final nx = num_(), ny = num_();
        x = rel ? x + nx : nx;
        y = rel ? y + ny : ny;
        path.moveTo(x, y);
        startX = x;
        startY = y;
        // A second pair after M is an implicit lineto, which is how most
        // exporters write a polygon.
        cmd = rel ? 'l' : 'L';
      case 'L':
        final nx = num_(), ny = num_();
        x = rel ? x + nx : nx;
        y = rel ? y + ny : ny;
        path.lineTo(x, y);
      case 'H':
        final nx = num_();
        x = rel ? x + nx : nx;
        path.lineTo(x, y);
      case 'V':
        final ny = num_();
        y = rel ? y + ny : ny;
        path.lineTo(x, y);
      case 'C':
        final x1 = num_(), y1 = num_(), x2 = num_(), y2 = num_();
        final nx = num_(), ny = num_();
        path.cubicTo(
          rel ? x + x1 : x1,
          rel ? y + y1 : y1,
          rel ? x + x2 : x2,
          rel ? y + y2 : y2,
          rel ? x + nx : nx,
          rel ? y + ny : ny,
        );
        x = rel ? x + nx : nx;
        y = rel ? y + ny : ny;
      case 'Q':
        final x1 = num_(), y1 = num_();
        final nx = num_(), ny = num_();
        path.quadraticBezierTo(
          rel ? x + x1 : x1,
          rel ? y + y1 : y1,
          rel ? x + nx : nx,
          rel ? y + ny : ny,
        );
        x = rel ? x + nx : nx;
        y = rel ? y + ny : ny;
      default:
        // An instruction this parser does not know ends the path rather than
        // silently dropping one segment and drawing the rest wrong.
        return path;
    }
  }
  return path;
}

/// Fits [path]'s own bounds into [size].
///
/// A pasted path is in whatever coordinates its author used — a 24-unit icon
/// grid, a 340-unit artboard — and an element is whatever size it was dragged
/// to. Scaling by the bounds is what makes those the same thing without asking
/// anybody for a viewBox.
Path fitPath(Path path, Size size) {
  final b = path.getBounds();
  if (b.isEmpty || size.isEmpty) return path;
  final sx = size.width / b.width, sy = size.height / b.height;
  // Column-major 4×4, the order `Path.transform` expects: scale, then shift
  // the scaled bounds back to the origin.
  return path.transform(Float64List.fromList(<double>[
    sx, 0, 0, 0, //
    0, sy, 0, 0, //
    0, 0, 1, 0, //
    -b.left * sx, -b.top * sy, 0, 1, //
  ]));
}
