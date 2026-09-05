import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/devices/presentation.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/design/components/hc_tile.dart';

/// **A keypad's news is which button was pressed.**
///
/// `button_N` accumulates the last action *per button*, so a keypad's state
/// says which buttons have ever fired and in no order at all — and a Pico
/// summarised as "—", which is a device the house has nothing to say about.
/// John: *"Lutron Keypads and Pico's should show last button pressed as their
/// status instead of just a dash."*
///
/// The ordering is the plugin's to know, so it publishes it; this is the
/// reading.
DeviceState keypad(Map<String, dynamic> state) => DeviceState(
      id: 'pico',
      pluginId: 'plugin.lutron',
      name: 'Pico',
      deviceType: 'pico_remote',
      available: true,
      state: state,
    );

void main() {
  test('the engraving, when the wall has one', () {
    expect(
      summarise(keypad(const {
        'button_2': 'press',
        'last_button': 2,
        'last_button_name': 'Overhead On',
      })),
      contains('Overhead On'),
    );
  });

  test('the number, when it does not', () {
    expect(
      summarise(keypad(const {'last_button': 4})),
      contains('Button 4'),
    );
  });

  test('and nothing invented before anything has been pressed', () {
    // A keypad nobody has touched has no news, and "Button 0" would be a
    // press that never happened.
    expect(
        summarise(keypad(const {
          'available_buttons': [2, 3]
        })),
        // A dash is what this element already says when it has nothing, and
        // that is still the right answer here.
        '—');
  });

  test('a keypad is a button, whatever it publishes', () {
    // The facet is what puts it in the right panel; this only checks that
    // reading its news did not change what it is.
    expect(facetOf(keypad(const {'last_button': 2})), DeviceFacet.button);
  });
}
