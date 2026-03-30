import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/providers/name_resolver_provider.dart';

void main() {
  group('DeviceNameResolver', () {
    final resolver = DeviceNameResolver([
      DeviceState(
        id: 'light_living',
        canonicalName: 'living_room.floor_lamp',
        pluginId: 'plugin.hue',
        name: 'Living Floor Lamp',
        area: 'Living Room',
        deviceType: 'light',
        available: true,
        state: const {},
      ),
      DeviceState(
        id: 'switch_hall',
        canonicalName: 'hall.switch',
        pluginId: 'plugin.hue',
        name: 'Hall Switch',
        area: 'Hall',
        deviceType: 'switch',
        available: true,
        state: const {},
      ),
    ]);

    test('resolves canonical name to display name', () {
      expect(
        resolver.resolve('living_room.floor_lamp'),
        'Living Floor Lamp',
      );
    });

    test('resolves raw device id to display name', () {
      expect(resolver.resolve('light_living'), 'Living Floor Lamp');
    });

    test('maps legacy refs to preferred rule refs', () {
      expect(
        resolver.preferredRuleRef('light_living'),
        'living_room.floor_lamp',
      );
    });

    test('leaves unknown refs unchanged', () {
      expect(resolver.preferredRuleRef('unknown.device'), 'unknown.device');
    });
  });
}
