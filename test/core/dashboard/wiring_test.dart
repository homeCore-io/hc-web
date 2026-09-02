import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/dashboard/wiring.dart';

/// Every wire on a page, gathered from what the document already says.
///
/// A properties panel shows one binding at a time and hides the rest, so a page
/// with forty of them cannot be audited by selecting things one at a time. The
/// claim under test is that this is the *same data* — nothing stored, nothing
/// added to the document — and that it says the two things the inspector
/// cannot: what a device drives, and what the step in the middle is.
({String id, String name, String type, Map<String, dynamic> config}) _el(
  String id,
  Map<String, dynamic> config, {
  String type = 'icon',
}) =>
    (id: id, name: id, type: type, config: config);

void main() {
  test('an unwired page has no wires', () {
    expect(
        wiresOf([
          _el('a', const {'facet': 'light'})
        ]),
        isEmpty);
  });

  test('a binding is a wire that reads', () {
    final wires = wiresOf([
      _el('a', const {
        'bindings': [
          {'property': 'ink', 'device_id': 'lamp', 'key': 'on'}
        ]
      })
    ]);
    expect(wires.single.way, WireWay.reads);
    expect(wires.single.deviceId, 'lamp');
    expect(wires.single.key, 'on');
    expect(wires.single.property, 'ink');
    expect(wires.single.transform, isNull, reason: 'nothing in the middle');
  });

  test('a range mapping shows as the step it is', () {
    // The setting most likely to be why a page shows the wrong number, and it
    // was buried two levels inside an inspector.
    final wires = wiresOf([
      _el('a', const {
        'bindings': [
          {
            'property': 'rotation',
            'device_id': 'hob',
            'key': 'temperature',
            'in_from': 16,
            'in_to': 24,
            'out_from': 0,
            'out_to': 210,
          }
        ]
      })
    ]);
    expect(wires.single.transform, '16–24 → 0–210');
  });

  test('a look table is counted, not listed', () {
    // Six entries would make the wire unreadable; the count is what tells you
    // whether to go and look.
    final wires = wiresOf([
      _el('a', const {
        'bindings': [
          {
            'property': 'ink',
            'device_id': 'lamp',
            'key': 'on',
            'map': {'true': 'accent', 'false': 'muted'},
          }
        ]
      })
    ]);
    expect(wires.single.transform, '2 looks');
  });

  test('an action is a wire that writes', () {
    final wires = wiresOf([
      _el('a', const {
        'on_tap': {'do': 'scene', 'target': 'evening'}
      })
    ]);
    expect(wires.single.way, WireWay.writes);
    expect(wires.single.deviceId, 'evening');
    expect(wires.single.key, 'run');
  });

  test('a half-set action is not drawn as a wire', () {
    // It goes nowhere yet. Drawing it would say the page does something it
    // does not.
    final wires = wiresOf([
      _el('a', const {
        'on_tap': {'do': 'set', 'target': 'lamp'}
      })
    ]);
    expect(wires, isEmpty);
  });

  test('one element can carry several wires, both ways', () {
    final wires = wiresOf([
      _el('a', const {
        'bindings': [
          {'property': 'ink', 'device_id': 'lamp', 'key': 'on'},
          {'property': 'opacity', 'device_id': 'lamp', 'key': 'brightness'},
        ],
        'on_tap': {'do': 'set', 'target': 'lamp', 'attribute': 'on'},
      })
    ]);
    expect(wires, hasLength(3));
    expect(wires.where((w) => w.way == WireWay.reads), hasLength(2));
    expect(wires.where((w) => w.way == WireWay.writes), hasLength(1));
  });

  test('wires from several elements come back together', () {
    // The question the inspector cannot answer: what does this device drive.
    final wires = wiresOf([
      _el('a', const {
        'bindings': [
          {'property': 'ink', 'device_id': 'lamp', 'key': 'on'}
        ]
      }),
      _el('b', const {
        'bindings': [
          {'property': 'fill', 'device_id': 'lamp', 'key': 'on'}
        ]
      }),
    ]);
    expect(wires.where((w) => w.deviceId == 'lamp'), hasLength(2));
    expect(wires.map((w) => w.elementId), ['a', 'b']);
  });

  test('an action this client cannot run is not drawn', () {
    // Left in the config and not shown as a wire: this view must not claim the
    // page does something this app would not do.
    final wires = wiresOf([
      _el('a', const {
        'on_tap': {'do': 'something_newer', 'target': 'x'}
      })
    ]);
    expect(wires, isEmpty);
  });
}
