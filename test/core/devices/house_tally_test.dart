import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/devices/house_tally.dart';
import 'package:hc_web/core/models/device_state.dart';

/// A number about the whole house.
///
/// The house page said "7 LIGHTS ON" for months and did not mean it: the
/// number was written into the page when the page was generated, so it stayed
/// 7 while the lights went on and off underneath it. John: *"Fix the header
/// light count as well."*

DeviceState _d(
  String id, {
  String type = 'switch',
  String? hint,
  bool on = false,
  bool available = true,
  Map<String, dynamic>? state,
}) =>
    DeviceState(
      id: id,
      pluginId: 'p',
      name: id,
      deviceType: type,
      uiHint: hint,
      available: available,
      state: state ?? {'on': on},
    );

void main() {
  final house = [
    _d('bulb', type: 'light', on: true),
    _d('lamp', type: 'light'),
    // A relay somebody retyped, and a Lutron dimmer that publishes `switch`:
    // both are lights, and neither says so in `device_type`.
    _d('relay', hint: 'light', on: true),
    _d('dimmer', state: const {'on': true, 'brightness_pct': 30}),
    _d('plug'),
    _d('gone', available: false),
  ];

  test('lights are counted by facet, not by the type a plugin sent', () {
    expect(houseTally('lights', house), 4);
  });

  test('and the lit ones are the ones that are on', () {
    expect(houseTally('lights_on', house), 3);
  });

  test('the rest of the house is countable too', () {
    expect(houseTally('devices', house), 6);
    expect(houseTally('offline', house), 1);
  });

  test('a tally this build has never heard of is not a zero', () {
    // A page asking for something newer than this client gets its own words
    // back. Answering "0 lights on" would be a lie told confidently.
    expect(houseTally('sunspots', house), -1);
  });

  test('every metric the inspector offers has an answer', () {
    for (final metric in houseTallyMetrics) {
      expect(houseTally(metric, house), greaterThanOrEqualTo(0),
          reason: '$metric is offered and unanswered');
    }
  });
}
