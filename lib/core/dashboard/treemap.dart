/// Squarified treemap: area is a number, and the rectangles stay near-square.
///
/// **The plain version is unusable here.** Slicing a row per item gives the
/// Hallway a strip two pixels wide and the Living Room a band across the page,
/// and neither can hold its own name. Squarifying picks how many items share
/// each row by keeping the worst aspect ratio down, which is what makes fifteen
/// rooms — thirty devices down to two — legible at once.
///
/// Pure, and pixel-free at the edges: it takes a width and a height, and gives
/// back rectangles in the same units. The renderer decides what a unit is.
library;

import 'dart:math' as math;

/// One thing to lay out: a key, and how much of the area it should get.
typedef TreemapItem = ({String key, double value});

/// Where one item landed.
typedef TreemapCell = ({String key, double x, double y, double w, double h});

/// [items] laid out to fill [width] by [height].
///
/// Items with no value are dropped rather than given a sliver: a room with no
/// devices is not a small room, it is a room this page has nothing to say
/// about, and a rectangle too small to label is worse than an absence.
List<TreemapCell> squarify(
  List<TreemapItem> items,
  double width,
  double height,
) {
  final live = items.where((i) => i.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (live.isEmpty || width <= 0 || height <= 0) return const [];

  final total = live.fold<double>(0, (a, i) => a + i.value);
  final scale = width * height / total;
  final queue = [
    for (final i in live) (key: i.key, area: i.value * scale),
  ];

  final out = <TreemapCell>[];
  var x = 0.0, y = 0.0, w = width, h = height;
  var row = <({String key, double area})>[];

  while (queue.isNotEmpty) {
    final side = math.min(w, h);
    final next = queue.first;
    if (row.isEmpty || _worst([...row, next], side) <= _worst(row, side)) {
      row.add(queue.removeAt(0));
      continue;
    }
    final placed = _place(row, x, y, w, h);
    out.addAll(placed.cells);
    x = placed.x;
    y = placed.y;
    w = placed.w;
    h = placed.h;
    row = [];
  }
  if (row.isNotEmpty) out.addAll(_place(row, x, y, w, h).cells);
  return out;
}

/// The worst aspect ratio in a row laid along [side] — the thing being
/// minimised, and the whole of the algorithm's judgement.
double _worst(List<({String key, double area})> row, double side) {
  var sum = 0.0, most = double.negativeInfinity, least = double.infinity;
  for (final item in row) {
    sum += item.area;
    most = math.max(most, item.area);
    least = math.min(least, item.area);
  }
  if (sum <= 0 || side <= 0 || least <= 0) return double.infinity;
  return math.max(
    side * side * most / (sum * sum),
    sum * sum / (side * side * least),
  );
}

({List<TreemapCell> cells, double x, double y, double w, double h}) _place(
  List<({String key, double area})> row,
  double x,
  double y,
  double w,
  double h,
) {
  final sum = row.fold<double>(0, (a, i) => a + i.area);
  final cells = <TreemapCell>[];
  // Rows run down the left of a wide rectangle and across the top of a tall
  // one, which is what keeps the leftover space closer to square each time.
  if (w >= h) {
    final thickness = h <= 0 ? 0.0 : sum / h;
    var oy = y;
    for (final item in row) {
      final ch = thickness <= 0 ? 0.0 : item.area / thickness;
      cells.add((key: item.key, x: x, y: oy, w: thickness, h: ch));
      oy += ch;
    }
    return (cells: cells, x: x + thickness, y: y, w: w - thickness, h: h);
  }
  final thickness = w <= 0 ? 0.0 : sum / w;
  var ox = x;
  for (final item in row) {
    final cw = thickness <= 0 ? 0.0 : item.area / thickness;
    cells.add((key: item.key, x: ox, y: y, w: cw, h: thickness));
    ox += cw;
  }
  return (cells: cells, x: x, y: y + thickness, w: w, h: h - thickness);
}
