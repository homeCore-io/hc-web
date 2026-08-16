import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/dashboard/layer_tree.dart';
import 'package:hc_web/core/models/dashboard.dart';

/// The page, as a tree.
///
/// What is pinned here is that the list is a **map of the page**: same order,
/// same nesting, nothing invented and nothing quietly missing. A list that
/// disagrees with the canvas is worse than no list, because it is the thing
/// people reach for when the canvas is too busy to click accurately.

DashboardWidgetModel _w(String id, {String? group, String title = ''}) =>
    DashboardWidgetModel(
      id: id,
      type: 'markdown',
      title: title,
      refreshPolicy: DashboardRefreshPolicy.passive,
      config: {'markdown': 'x', if (group != null) 'group': group},
    );

/// Reading order down the page: a, b in `Wall`, c in `Wall/Lights`, d loose.
final _widgets = {
  'a': _w('a', title: 'Header'),
  'b': _w('b', group: 'Wall', title: 'Glass panel'),
  'c': _w('c', group: 'Wall/Lights', title: 'Bedside lamp'),
  'd': _w('d', title: 'Now playing'),
};

const _order = [
  GridItem(id: 'a', x: 0, y: 0, w: 2, h: 1),
  GridItem(id: 'b', x: 0, y: 1, w: 2, h: 1),
  GridItem(id: 'c', x: 0, y: 2, w: 2, h: 1),
  GridItem(id: 'd', x: 0, y: 3, w: 2, h: 1),
];

Map<String, String?> get _paths => {
      for (final e in _widgets.entries)
        e.key: e.value.config['group'] as String?
    };

List<LayerRow> _rows({Set<String> collapsed = const {}}) =>
    layerRows(order: _order, widgets: _widgets, collapsed: collapsed);

void main() {
  group('shape', () {
    test('a group appears at its first member, not sorted to the top', () {
      // The list is a map of the page. A group hoisted to the top would put
      // the tree in an order the canvas does not have.
      expect(_rows().map((r) => r.label), [
        'Header',
        'Wall',
        'Glass panel',
        'Lights',
        'Bedside lamp',
        'Now playing'
      ]);
    });

    test('nesting comes from the path, declared nowhere', () {
      final rows = _rows();
      expect(rows.map((r) => r.depth), [0, 0, 1, 1, 2, 0]);
    });

    test('a group row is a group and carries no id', () {
      final wall = _rows().firstWhere((r) => r.label == 'Wall');
      expect(wall.isGroup, isTrue);
      expect(wall.id, isNull,
          reason: 'a group has no identity beyond its path');
      expect(wall.path, 'Wall');
    });

    test('a group counts everything under it, nested included', () {
      final rows = _rows();
      expect(rows.firstWhere((r) => r.label == 'Wall').count, 2);
      expect(rows.firstWhere((r) => r.label == 'Lights').count, 1);
    });

    test('an element with no title falls back to something nameable', () {
      final rows = layerRows(
        order: const [GridItem(id: 'z', x: 0, y: 0, w: 1, h: 1)],
        widgets: {'z': _w('z')},
      );
      expect(rows.single.label, 'markdown',
          reason: 'a blank row is a row you cannot aim at');
    });
  });

  group('collapsing', () {
    test('a collapsed group keeps its own row and its count', () {
      // Nothing may simply vanish. The count is what says how much is folded
      // away, and it is the reason collapsing is safe to do.
      final rows = _rows(collapsed: {'Wall'});
      expect(rows.map((r) => r.label), ['Header', 'Wall', 'Now playing']);
      expect(rows.firstWhere((r) => r.label == 'Wall').count, 2);
    });

    test('collapsing a parent hides the nested group too', () {
      final rows = _rows(collapsed: {'Wall'});
      expect(rows.any((r) => r.label == 'Lights'), isFalse);
    });

    test('collapsing the child leaves the parent open', () {
      final rows = _rows(collapsed: {'Wall/Lights'});
      expect(rows.map((r) => r.label),
          ['Header', 'Wall', 'Glass panel', 'Lights', 'Now playing']);
    });
  });

  group('what a click puts in hand', () {
    test('a group row holds the whole group', () {
      // The same thing a click on the canvas does. Two ways to select a group
      // that disagreed would be worse than one.
      final wall = _rows().firstWhere((r) => r.label == 'Wall');
      expect(idsFor(wall, _paths), {'b', 'c'});
    });

    test('a nested group holds only its own', () {
      final lights = _rows().firstWhere((r) => r.label == 'Lights');
      expect(idsFor(lights, _paths), {'c'});
    });

    test('an element row holds itself', () {
      final header = _rows().firstWhere((r) => r.label == 'Header');
      expect(idsFor(header, _paths), {'a'});
    });
  });

  group('shift-click', () {
    test('takes everything between, in either direction', () {
      final rows = _rows();
      expect(rangeBetween(rows, 0, 2, _paths), {'a', 'b', 'c'});
      expect(rangeBetween(rows, 2, 0, _paths), {'a', 'b', 'c'},
          reason: 'dragging a range upward is the same range');
    });

    test('a range over a collapsed group does not pick up what is hidden', () {
      // Selecting something you cannot see is how a range stops being
      // predictable — and then something you never saw gets deleted.
      final rows = _rows(collapsed: {'Wall'});
      // Header .. Wall: the group row is visible, so the group comes, but the
      // range does not reach past it into rows that are not on screen.
      expect(rangeBetween(rows, 0, 1, _paths), {'a', 'b', 'c'});
      expect(rangeBetween(rows, 0, 0, _paths), {'a'});
    });

    test('an out-of-range index is clamped rather than thrown', () {
      final rows = _rows();
      expect(rangeBetween(rows, 0, 99, _paths).length, 4);
      expect(rangeBetween(const [], 0, 3, _paths), isEmpty);
    });
  });
}
