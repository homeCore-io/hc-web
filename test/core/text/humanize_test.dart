import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/text/humanize.dart';

void main() {
  group('humanize', () {
    test('snake_case becomes Title Case', () {
      expect(humanize('family_room'), 'Family Room');
      expect(humanize('temperature_sensor'), 'Temperature Sensor');
      expect(humanize('device_state_changed'), 'Device State Changed');
    });

    test('keeps numbers', () {
      expect(humanize('bedroom_3'), 'Bedroom 3');
    });

    test('preserves acronyms', () {
      expect(humanize('master_bedroom_ac'), 'Master Bedroom AC');
      expect(humanize('led_strip'), 'LED Strip');
      expect(humanize('tv'), 'TV');
    });

    test('already-spaced or single words', () {
      expect(humanize('attic'), 'Attic');
      expect(humanize('living room'), 'Living Room');
    });

    test('empty and null', () {
      expect(humanize(''), '');
      expect(humanize(null), '');
    });
  });
}
