import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/grid_engine.dart';
import 'package:hc_web/core/dashboard/groups.dart';
import 'package:hc_web/core/dashboard/repeat.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';

/// Stamping a row out once per device.
///
/// The number this exists for is forty-nine: that is how many light toggles
/// sixteen real pages carried, every one of them placed by hand, because there
/// was no way to say *this row, for the lights in this room*.
///
/// It is a **tool**, so what it produces is ordinary elements — which is what
/// most of these tests are really checking. Nothing links, nothing propagates,
/// and the row you drew is the first row rather than a master of it.

DeviceState device(String id, String name) => DeviceState(
      id: id,
      pluginId: 'test',
      name: name,
      available: true,
      state: const {},
    );

DashboardWidgetModel toggle(String id, {String? group}) => DashboardWidgetModel(
      id: id,
      type: 'toggle',
      title: 'Toggle',
      refreshPolicy: DashboardRefreshPolicy.live,
      config: {
        'device_id': '',
        if (group != null) 'group': group,
      },
    );

DashboardWidgetModel heading(String id, {String? group}) =>
    DashboardWidgetModel(
      id: id,
      type: 'heading',
      title: 'Lights',
      refreshPolicy: DashboardRefreshPolicy.passive,
      config: {
        'text': 'Lights',
        if (group != null) 'group': group,
      },
    );

GridItem at(String id, double x, double y, [double w = 200, double h = 40]) =>
    GridItem(
      id: id,
      x: 0,
      y: 0,
      w: 2,
      h: 1,
      rect: DashboardRect(x: x, y: y, w: w, h: h),
    );

final lights = [
  device('hue_1', 'Ceiling light'),
  device('hue_2', 'Desk lamp'),
  device('hue_3', 'Floor lamp'),
];

void main() {
  setUp(() {
    WidgetRegistry.reset();
    registerBuiltinDashboardWidgets();
  });

  group('the row you drew is the first row', () {
    test('three lights give three rows, not a master and three', () {
      final out = repeatFor(
        design: [toggle('a')],
        items: [at('a', 0, 0)],
        devices: lights,
        step: (dx: 0, dy: 48),
        stamp: (i) => 'new_$i',
      );
      expect(out.rewired, hasLength(1), reason: 'the design itself');
      expect(out.widgets, hasLength(2), reason: 'and two more');
      expect(out.items, hasLength(2));
    });

    test('the design is re-wired to the first device in place', () {
      final out = repeatFor(
        design: [toggle('a')],
        items: [at('a', 0, 0)],
        devices: lights,
        step: (dx: 0, dy: 48),
        stamp: (i) => 'new_$i',
      );
      expect(out.rewired['a']!.config['device_id'], 'hue_1');
      expect(out.rewired['a']!.id, 'a', reason: 'same element, same place');
    });

    test('and the copies take the rest, in order', () {
      final out = repeatFor(
        design: [toggle('a')],
        items: [at('a', 0, 0)],
        devices: lights,
        step: (dx: 0, dy: 48),
        stamp: (i) => 'new_$i',
      );
      final wired = [
        for (final w in out.widgets.values) w.config['device_id'],
      ];
      expect(wired, ['hue_2', 'hue_3']);
    });
  });

  group('what gets wired, and what does not', () {
    test('a toggle becomes that light and is named for it', () {
      final out = repeatFor(
        design: [toggle('a')],
        items: [at('a', 0, 0)],
        devices: lights,
        step: (dx: 0, dy: 48),
        stamp: (i) => 'new_$i',
      );
      expect(out.rewired['a']!.title, 'Ceiling light');
      expect(out.widgets.values.first.title, 'Desk lamp');
    });

    test('a heading in the row keeps saying what it said', () {
      // The rule is the registry's device fields. A caption is not a device,
      // so nothing about it is anybody's to rewrite.
      final out = repeatFor(
        design: [heading('h'), toggle('a')],
        items: [at('h', 0, 0), at('a', 0, 20)],
        devices: lights,
        step: (dx: 0, dy: 48),
        stamp: (i) => 'new_$i',
      );
      expect(out.rewired['h']!.title, 'Lights');
      expect(out.rewired['h']!.config['text'], 'Lights');
      for (final w in out.widgets.values.where((w) => w.type == 'heading')) {
        expect(w.title, 'Lights');
      }
    });
  });

  group('where the copies land', () {
    test('one step further along, per copy', () {
      final out = repeatFor(
        design: [toggle('a')],
        items: [at('a', 10, 100)],
        devices: lights,
        step: (dx: 0, dy: 48),
        stamp: (i) => 'new_$i',
      );
      expect([for (final i in out.items) i.rect!.y], [148.0, 196.0]);
      expect([for (final i in out.items) i.rect!.x], [10.0, 10.0]);
    });

    test('a whole row moves together, keeping its shape', () {
      final out = repeatFor(
        design: [heading('h'), toggle('a')],
        items: [at('h', 0, 0, 80, 20), at('a', 90, 0, 60, 20)],
        devices: [lights[0], lights[1]],
        step: (dx: 0, dy: 30),
        stamp: (i) => 'new_$i',
      );
      final rects = [for (final i in out.items) i.rect!];
      expect(rects[0].x, 0);
      expect(rects[1].x, 90, reason: 'the gap inside the row is preserved');
      expect(rects.every((r) => r.y == 30), isTrue);
    });

    test('stepFor measures the design and adds a gap', () {
      final step = stepFor([at('h', 0, 0, 80, 20), at('a', 90, 0, 60, 24)]);
      expect(step.dy, 32, reason: '24 tall plus the gap');
      expect(step.dx, 0);

      final across = stepFor([at('a', 0, 0, 60, 24)], across: true);
      expect(across.dx, 68);
      expect(across.dy, 0);
    });
  });

  group('grouping', () {
    test('each copy of a row is its own group', () {
      // Two rows in one group would move as one thing, which is not what a
      // list of rows is.
      final out = repeatFor(
        design: [heading('h', group: 'Row'), toggle('a', group: 'Row')],
        items: [at('h', 0, 0), at('a', 90, 0)],
        devices: lights,
        step: (dx: 0, dy: 30),
        stamp: (i) => 'new_$i',
        takenPaths: {'Row'},
      );
      final paths = {for (final w in out.widgets.values) groupOf(w.config)};
      expect(paths, hasLength(2));
      expect(paths, isNot(contains('Row')));
    });

    test('both members of one copy land in the same group', () {
      final out = repeatFor(
        design: [heading('h', group: 'Row'), toggle('a', group: 'Row')],
        items: [at('h', 0, 0), at('a', 90, 0)],
        devices: [lights[0], lights[1]],
        step: (dx: 0, dy: 30),
        stamp: (i) => 'new_$i',
        takenPaths: {'Row'},
      );
      final paths = [for (final w in out.widgets.values) groupOf(w.config)];
      expect(paths, hasLength(2));
      expect(paths.first, paths.last);
    });

    test('a row inside a frame stays inside it', () {
      final out = repeatFor(
        design: [toggle('a', group: 'Panel/Row')],
        items: [at('a', 0, 0)],
        devices: [lights[0], lights[1]],
        step: (dx: 0, dy: 30),
        stamp: (i) => 'new_$i',
        takenPaths: {'Row'},
      );
      final path = groupOf(out.widgets.values.single.config)!;
      expect(path, startsWith('Panel/'));
      expect(path, isNot('Panel/Row'));
    });

    test('an ungrouped design gives ungrouped copies', () {
      final out = repeatFor(
        design: [toggle('a')],
        items: [at('a', 0, 0)],
        devices: [lights[0], lights[1]],
        step: (dx: 0, dy: 30),
        stamp: (i) => 'new_$i',
      );
      expect(groupOf(out.widgets.values.single.config), isNull);
    });
  });

  group('nothing to do', () {
    test('no devices, no copies, and the design is left alone', () {
      final out = repeatFor(
        design: [toggle('a')],
        items: [at('a', 0, 0)],
        devices: const [],
        step: (dx: 0, dy: 30),
        stamp: (i) => 'new_$i',
      );
      expect(out.rewired, isEmpty);
      expect(out.widgets, isEmpty);
    });

    test('one device re-wires the design and adds nothing', () {
      final out = repeatFor(
        design: [toggle('a')],
        items: [at('a', 0, 0)],
        devices: [lights.first],
        step: (dx: 0, dy: 30),
        stamp: (i) => 'new_$i',
      );
      expect(out.rewired['a']!.config['device_id'], 'hue_1');
      expect(out.widgets, isEmpty);
    });
  });
}
