import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/devices/presentation.dart';
import 'package:hc_web/core/models/device_state.dart';

/// **A rename wins over the wall.**
///
/// A keypad's engravings arrive from the bridge — Lutron reads them out of
/// DbXML — and arrive again on every re-registration, so a name written where
/// the plugin publishes would be wiped the next time it reconnected. The
/// override is the field registration never touches, which is the same
/// contract the device's own name has, so it is asked in the same order.

DeviceState keypad({Map<String, String>? names}) => DeviceState(
      id: 'keypad',
      pluginId: 'plugin.lutron',
      name: 'Hallway 6 Button',
      deviceType: 'keypad',
      available: true,
      state: const {},
      buttonNames: names,
    );

void main() {
  test('the override is asked first', () {
    expect(
      buttonLabel(keypad(names: const {'2': 'Movie night'}), 2,
          engraved: 'Overhead'),
      'Movie night',
    );
  });

  test('then the engraving the bridge sent', () {
    expect(buttonLabel(keypad(), 2, engraved: 'Overhead'), 'Overhead');
  });

  test('then the number, because a blank square is not a button', () {
    expect(buttonLabel(keypad(), 3), 'Button 3');
    expect(buttonLabel(null, 3), 'Button 3');
  });

  test('a blank override is not an override', () {
    // Clearing the field is how one button goes back to the wall's own word,
    // so an empty string has to mean *no opinion* rather than *no name*.
    expect(
      buttonLabel(keypad(names: const {'2': '   '}), 2, engraved: 'Overhead'),
      'Overhead',
    );
  });

  test('and it only speaks for the button it names', () {
    final d = keypad(names: const {'2': 'Movie night'});
    expect(buttonLabel(d, 4, engraved: 'All Off'), 'All Off');
  });
}
