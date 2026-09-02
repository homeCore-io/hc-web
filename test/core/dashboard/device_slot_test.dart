import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/device_slot.dart';
import 'package:hc_web/core/dashboard/widget_registry.dart';
import 'package:hc_web/core/models/dashboard.dart';
import 'package:hc_web/features/dashboard/builtin_cards.dart';

/// A place a device goes, before anyone has said which device.
///
/// The claim this carries: a page can be shared without carrying this house's
/// hardware, and the gaps it arrives with can be found — because a control
/// pointed at nothing looks exactly like a control, and the only thing that
/// makes it findable is a list.
DashboardWidgetModel _w(
  String id,
  String type,
  Map<String, dynamic> config, {
  String title = '',
}) =>
    DashboardWidgetModel(
      id: id,
      type: type,
      title: title,
      config: config,
      refreshPolicy: DashboardRefreshPolicy.live,
    );

void main() {
  setUp(() {
    WidgetRegistry.reset();
    registerBuiltinDashboardWidgets();
  });

  group('the spelling', () {
    test('a slot is a string, so an old client sees a device it cannot find',
        () {
      // Not an object: core declares `device_id` as a string and executes that
      // declaration, and a client that never heard of slots must degrade to
      // "pointed at nothing" rather than to a parse error.
      expect(slotFor('Ceiling light'), isA<String>());
      expect(slotFor('Ceiling light'), 'slot:Ceiling light');
    });

    test('an ordinary id is not a slot', () {
      expect(isSlot('hue_001788fffe6841b3_light_50a25900'), isFalse);
      expect(slotLabel('lamp'), isNull);
      expect(slotLabel(null), isNull);
      expect(slotLabel(42), isNull);
    });

    test('an unnamed slot is still a slot', () {
      // An element dropped and not yet named is unwired. Treating it as wired
      // would hide it from the one list that can find it.
      expect(isSlot('slot:'), isTrue);
      expect(slotLabel('slot:'), '');
    });
  });

  group('finding the gaps', () {
    test('a slot is a gap, and says what belongs there', () {
      final gaps = wiringGaps([
        _w('a', 'toggle',
            {'device_id': slotFor('Ceiling light'), 'attribute': 'on'}),
      ]);
      expect(gaps, hasLength(1));
      expect(gaps.single.widgetId, 'a');
      expect(gaps.single.field, 'device_id');
      expect(gaps.single.wants, 'Ceiling light');
      expect(gaps.single.scene, isFalse);
    });

    test('an empty reference is a gap too', () {
      // A slider dragged out and never pointed anywhere is as dead as one an
      // import left empty.
      expect(wiringGaps([_w('a', 'slider', const {})]), hasLength(1));
    });

    test('a wired element is not a gap', () {
      final gaps = wiringGaps([
        _w('a', 'toggle', {'device_id': 'lamp', 'attribute': 'on'}),
      ]);
      expect(gaps, isEmpty);
    });

    test('a scene slot is marked as one, so the wrong picker is not offered',
        () {
      final gaps = wiringGaps([
        _w('a', 'scene_button', {'scene_id': slotFor('Evening')}),
      ]);
      expect(gaps.single.scene, isTrue);
    });

    test('the fields come from the registry, not from a list kept here', () {
      // Every element that names a device is covered, including ones added
      // after this test was written.
      final everyRefType = WidgetRegistry.all.where((d) => d.configFields.any(
          (f) =>
              f.kind == WidgetConfigKind.deviceRef ||
              f.kind == WidgetConfigKind.sceneRef));
      expect(everyRefType, isNotEmpty);
      for (final descriptor in everyRefType) {
        final gaps = wiringGaps([_w('x', descriptor.type, const {})]);
        expect(gaps, isNotEmpty,
            reason: '${descriptor.type} names a device and reports no gap');
      }
    });

    test('a type this app does not know is skipped, not guessed at', () {
      // It draws as an unknown card already; inventing slots for a config
      // nobody can describe would put rows in the panel no picker could fill.
      expect(wiringGaps([_w('a', 'from_the_future', const {})]), isEmpty);
    });

    test('one element can hold more than one gap', () {
      final gaps = wiringGaps([
        _w('a', 'toggle', {'device_id': slotFor('Lamp')}),
        _w('b', 'scene_button', {'scene_id': slotFor('Evening')}),
      ]);
      expect(gaps, hasLength(2));
    });
  });

  group('sharing strips the house out', () {
    test('an id becomes a slot named for the element', () {
      // "Hob light" travels; "Office Desk Lamp" is a fact about this house.
      final widget = _w(
          'a', 'toggle', {'device_id': 'hue_abc', 'attribute': 'on'},
          title: 'Hob light');
      final shared = unwireAll(widget, null);
      expect(shared['device_id'], 'slot:Hob light');
      expect(shared['attribute'], 'on', reason: 'only references are stripped');
    });

    test('a nameless element falls back to what the device was called', () {
      final widget = _w('a', 'toggle', {'device_id': 'hue_abc'});
      final shared = unwireAll(widget, (id) => 'Office Desk Lamp');
      expect(shared['device_id'], 'slot:Office Desk Lamp');
    });

    test('a slot is left alone, so sharing twice is not lossy', () {
      final widget = _w('a', 'toggle', {'device_id': slotFor('Ceiling light')},
          title: 'Overhead');
      expect(unwireAll(widget, null)['device_id'], 'slot:Ceiling light');
    });

    test('a shared page is all gaps, and every one can be found', () {
      final page = [
        _w('a', 'toggle', {'device_id': 'lamp', 'attribute': 'on'},
            title: 'Lamp'),
        _w('b', 'scene_button', {'scene_id': 'evening'}, title: 'Evening'),
      ];
      final shared = [
        for (final w in page)
          _w(w.id, w.type, unwireAll(w, null), title: w.title),
      ];
      expect(wiringGaps(shared), hasLength(2));
      expect(wiringGaps(shared).map((g) => g.wants), ['Lamp', 'Evening']);
    });
  });

  test('wiring one gap leaves the rest of the config alone', () {
    final config = {
      'device_id': slotFor('Lamp'),
      'attribute': 'on',
      'ink': 'accent'
    };
    final wired = wire(config, 'device_id', 'hue_abc');
    expect(wired['device_id'], 'hue_abc');
    expect(wired['attribute'], 'on');
    expect(wired['ink'], 'accent');
    expect(config['device_id'], slotFor('Lamp'),
        reason: 'the original is untouched');
  });
}
