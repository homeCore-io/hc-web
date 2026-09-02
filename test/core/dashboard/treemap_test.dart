import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/treemap.dart';

/// Area is a number, and the rectangles stay near-square.
///
/// The plain version is unusable here: slicing a row per item gives the Hallway
/// a strip two pixels wide and the Living Room a band across the page, and
/// neither can hold its own name.
void main() {
  final house = <TreemapItem>[
    (key: 'living_room', value: 30),
    (key: 'office', value: 28),
    (key: 'family_room', value: 23),
    (key: 'garage', value: 21),
    (key: 'bathroom', value: 9),
    (key: 'master_bedroom', value: 8),
    (key: 'kitchen', value: 7),
    (key: 'laundry_room', value: 7),
    (key: 'attic', value: 5),
    (key: 'equipment_room', value: 4),
    (key: 'bedroom_3', value: 4),
    (key: 'outdoor', value: 3),
    (key: 'dining_room', value: 3),
    (key: 'bathroom_2', value: 3),
    (key: 'hallway', value: 2),
  ];

  test('everything with a value gets a rectangle', () {
    final cells = squarify(house, 800, 500);
    expect(cells, hasLength(house.length));
    expect(cells.map((c) => c.key).toSet(), house.map((i) => i.key).toSet());
  });

  test('the rectangles fill the space and do not overlap', () {
    final cells = squarify(house, 800, 500);
    final area = cells.fold<double>(0, (a, c) => a + c.w * c.h);
    expect(area, closeTo(800 * 500, 1));
    for (var i = 0; i < cells.length; i++) {
      for (var j = i + 1; j < cells.length; j++) {
        final a = cells[i], b = cells[j];
        final overlaps = a.x < b.x + b.w - 0.001 &&
            b.x < a.x + a.w - 0.001 &&
            a.y < b.y + b.h - 0.001 &&
            b.y < a.y + a.h - 0.001;
        expect(overlaps, isFalse, reason: '${a.key} overlaps ${b.key}');
      }
    }
  });

  test('area is the value, so the house has its own shape', () {
    final cells = {for (final c in squarify(house, 800, 500)) c.key: c};
    final unit = 800 * 500 / 157;
    expect(cells['living_room']!.w * cells['living_room']!.h,
        closeTo(unit * 30, 1));
    expect(cells['hallway']!.w * cells['hallway']!.h, closeTo(unit * 2, 1));
  });

  test('nothing is a sliver — that is the whole point of squarifying', () {
    // The naive layout gives the Hallway a strip two pixels wide. Every
    // rectangle here has to be able to hold a word.
    for (final c in squarify(house, 800, 500)) {
      final ratio = c.w / c.h;
      expect(ratio, greaterThan(0.12), reason: '${c.key} is a sliver');
      expect(ratio, lessThan(9), reason: '${c.key} is a band');
    }
  });

  test('a room with nothing in it is left out, not given a sliver', () {
    // Not a small room: a room this page has nothing to say about. A rectangle
    // too small to label is worse than an absence.
    final cells = squarify(<TreemapItem>[
      (key: 'a', value: 4),
      (key: 'empty', value: 0),
    ], 100, 100);
    expect(cells.map((c) => c.key), ['a']);
  });

  test('an empty house lays out nothing rather than dividing by zero', () {
    expect(squarify(const [], 100, 100), isEmpty);
    expect(squarify(<TreemapItem>[(key: 'a', value: 1)], 0, 100), isEmpty);
  });

  test('one room takes the whole space', () {
    final cells = squarify(<TreemapItem>[(key: 'only', value: 7)], 200, 120);
    expect(cells.single.w, closeTo(200, 0.001));
    expect(cells.single.h, closeTo(120, 0.001));
  });

  test('the biggest room comes first, whatever order it arrived in', () {
    final shuffled = <TreemapItem>[
      (key: 'small', value: 2),
      (key: 'big', value: 40),
      (key: 'mid', value: 10),
    ];
    final cells = squarify(shuffled, 400, 300);
    final biggest = cells.reduce((a, b) => a.w * a.h > b.w * b.h ? a : b);
    expect(biggest.key, 'big');
  });
}
