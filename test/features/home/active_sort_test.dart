import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/devices/presentation.dart';
import 'package:hc_web/core/models/device_state.dart';

DeviceState _d(String name, {required bool on}) => DeviceState(
      id: name,
      name: name,
      pluginId: 'plugin.test',
      deviceType: 'switch',
      available: true,
      state: {'on': on},
    );

/// The room card's ordering. Mirrors `_Room` in home_page.dart.
List<String> order(List<DeviceState> devices, {required bool activeFirst}) {
  final sorted = [...devices]..sort((a, b) {
      if (activeFirst) {
        final byOn = (isOn(b) ? 1 : 0).compareTo(isOn(a) ? 1 : 0);
        if (byOn != 0) return byOn;
      }
      return a.displayName.compareTo(b.displayName);
    });
  return sorted.map((d) => d.displayName).toList();
}

void main() {
  final room = [
    _d('Arch Lamp', on: false),
    _d('Zone 04', on: true),
    _d('Floor Lamp', on: false),
    _d('Bookshelf', on: true),
  ];

  test('active first puts the on ones up, A–Z within each group', () {
    expect(order(room, activeFirst: true),
        ['Bookshelf', 'Zone 04', 'Arch Lamp', 'Floor Lamp']);
  });

  test('off is plain A–Z, whatever is on', () {
    expect(order(room, activeFirst: false),
        ['Arch Lamp', 'Bookshelf', 'Floor Lamp', 'Zone 04']);
  });

  test('A–Z does not move when a device switches', () {
    // The whole point of the toggle: an order that holds still while you work.
    final before = order(room, activeFirst: false);
    final after = order([
      _d('Arch Lamp', on: true),
      _d('Zone 04', on: false),
      _d('Floor Lamp', on: true),
      _d('Bookshelf', on: false),
    ], activeFirst: false);
    expect(after, before);
  });

  test('active first DOES move — which is the behaviour being opted out of',
      () {
    final before = order(room, activeFirst: true);
    final after = order([
      _d('Arch Lamp', on: true),
      _d('Zone 04', on: false),
      _d('Floor Lamp', on: true),
      _d('Bookshelf', on: false),
    ], activeFirst: true);
    expect(after, isNot(before));
  });

  test('a room where nothing is on sorts the same either way', () {
    final dark = [_d('Beta', on: false), _d('Alpha', on: false)];
    expect(order(dark, activeFirst: true), order(dark, activeFirst: false));
  });
}
