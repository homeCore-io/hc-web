import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/features/devices/device_readings.dart';

DeviceState _d(Map<String, dynamic> state) => DeviceState(
      id: 'x',
      name: 'x',
      pluginId: 'plugin.ecowitt',
      available: true,
      state: state,
    );

/// The live Ecowitt weather station, verbatim — the device this block exists
/// for. Seventeen attributes, every one of which used to render as a bare
/// number under a tab called *Control*.
final _station = _d(const {
  'barometric_abs': 29.226,
  'barometric_rel': 30.088,
  'battery': 3.0,
  'battery_kind': 'voltage',
  'battery_low': false,
  'daily_max_wind': 5.37,
  'datetime': '2026-07-26 21:00:07',
  'gust_speed': 2.91,
  'humidity': 60.0,
  'light': 524.7,
  'temperature': 82.4,
  'temperature_unit': '°F',
  'uvi': 4.0,
  'vpd': 0.446,
  'wind_direction': 299.0,
  'wind_direction_avg10m': 316.0,
  'wind_speed': 2.24,
});

void main() {
  group('units — the number cannot tell you what it is', () {
    test('temperature uses the unit the device published', () {
      expect(formatReading(_station, 'temperature'), '82.40°F');
    });

    test('pressure is inHg, not a bare decimal', () {
      expect(formatReading(_station, 'barometric_rel'), '30.09 inHg');
      expect(formatReading(_station, 'barometric_abs'), '29.23 inHg');
    });

    test('vapour deficit is kPa', () {
      expect(formatReading(_station, 'vpd'), '0.45 kPa');
    });

    test('wind is mph and light is irradiance', () {
      expect(formatReading(_station, 'wind_speed'), '2.24 mph');
      expect(formatReading(_station, 'gust_speed'), '2.91 mph');
      expect(formatReading(_station, 'light'), '524.70 W/m²');
    });

    test('UV index is a bare number — it has no unit', () {
      expect(formatReading(_station, 'uvi'), '4');
    });

    test('humidity is a percentage', () {
      expect(formatReading(_station, 'humidity'), '60%');
    });
  });

  group('bearings', () {
    test('a wind direction is named, not just numbered', () {
      // 299 as a right-aligned number is data the reader has to decode.
      expect(formatReading(_station, 'wind_direction'), '299° WNW');
      expect(formatReading(_station, 'wind_direction_avg10m'), '316° NW');
    });

    test('the compass wraps at north', () {
      expect(
          formatReading(_d({'wind_direction': 0}), 'wind_direction'), '0° N');
      expect(formatReading(_d({'wind_direction': 355}), 'wind_direction'),
          '355° N');
      expect(
          formatReading(_d({'wind_direction': 90}), 'wind_direction'), '90° E');
      expect(formatReading(_d({'wind_direction': 180}), 'wind_direction'),
          '180° S');
    });
  });

  group('battery folds its kind in', () {
    test('3 volts is volts, not 3 percent', () {
      expect(formatReading(_station, 'battery'), '3.0 V');
    });

    test('a binary sensor says OK or Low, never a percentage', () {
      expect(
          formatReading(
              _d({
                'battery': 0.0,
                'battery_kind': 'binary',
                'battery_low': false
              }),
              'battery'),
          'OK');
      expect(
          formatReading(
              _d({
                'battery': 1.0,
                'battery_kind': 'binary',
                'battery_low': true
              }),
              'battery'),
          'Low');
    });

    test('a plain reading is still a percentage', () {
      expect(formatReading(_d({'battery': 87}), 'battery'), '87%');
    });
  });

  group('what is hidden', () {
    test('a unit is a qualifier, not a fact of its own', () {
      expect(isReadingMetadata('temperature_unit'), isTrue);
    });

    test('battery kind and low fold into the battery row', () {
      expect(isReadingMetadata('battery_kind'), isTrue);
      expect(isReadingMetadata('battery_low'), isTrue);
    });

    test('catalogues a picker consumes are not rows', () {
      // These are what made a Sonos panel a wall of JSON.
      for (final k in const [
        'available_apps',
        'available_favorite_items',
        'supported_actions',
        'ui_enrichments',
        'media_image_url',
        'sonos',
        'device_info',
      ]) {
        expect(isReadingMetadata(k), isTrue, reason: k);
      }
    });

    test('real readings are not hidden', () {
      for (final k in const ['temperature', 'humidity', 'vpd', 'uvi']) {
        expect(isReadingMetadata(k), isFalse, reason: k);
      }
    });

    test('Z-Wave command-class dumps fold behind Advanced', () {
      expect(isAdvancedReading('cc134_applicationversion'), isTrue);
      expect(isAdvancedReading('cc99_usercode_pk7'), isTrue);
      expect(isAdvancedReading('temperature'), isFalse);
    });
  });

  group('grouping and naming', () {
    test('the station splits into the groups a person thinks in', () {
      expect(readingGroup('temperature'), 'Air');
      expect(readingGroup('vpd'), 'Air');
      expect(readingGroup('gust_speed'), 'Wind');
      expect(readingGroup('wind_direction'), 'Wind');
      expect(readingGroup('uvi'), 'Sky');
      expect(readingGroup('battery'), 'Status');
    });

    test('an attribute the lexicon does not know lands in Other', () {
      // Safer than guessing: a wrong group is a confident lie.
      expect(readingGroup('mystery_reading'), 'Other');
      expect(formatReading(_d({'mystery_reading': 12.5}), 'mystery_reading'),
          '12.50');
    });

    test('names read as English, not as payload keys', () {
      expect(readingName('vpd'), 'Vapour deficit');
      expect(readingName('barometric_rel'), 'Pressure');
      expect(readingName('uvi'), 'UV index');
      expect(readingName('daily_max_wind'), 'Max wind today');
      expect(readingName('humidity'), 'Humidity');
    });
  });

  group('booleans read as states', () {
    test('open is unambiguous and gets a word', () {
      expect(formatReading(_d({'open': true}), 'open'), 'Open');
      expect(formatReading(_d({'open': false}), 'open'), 'Closed');
    });

    test('contact is NOT guessed at', () {
      // Every YoLink door sensor on the live install reports
      // `contact: false` alongside `open: false`. Under the electrical
      // convention (closed circuit = shut) those two contradict, so the client
      // cannot derive the word and must not pretend to. A plugin declaring
      // `AttributeSchema.states` is the fix; until then, neutral.
      expect(formatReading(_d({'contact': true}), 'contact'), 'Yes');
      expect(formatReading(_d({'contact': false}), 'contact'), 'No');
    });

    test('a leak sensor is dry, not false', () {
      expect(formatReading(_d({'leak': false}), 'leak'), 'Dry');
      expect(formatReading(_d({'leak': true}), 'leak'), 'Detected');
    });
  });
}
