import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/history_entry.dart';
import 'package:hc_web/core/providers/device_history_provider.dart';

HistoryEntry _e(String attr, Object? value, String hhmm) => HistoryEntry(
      attribute: attr,
      value: value,
      recordedAt: DateTime(2026, 7, 27, int.parse(hhmm.split(':')[0]),
          int.parse(hhmm.split(':')[1])),
    );

void main() {
  group('seriesFor', () {
    test('keeps one attribute, numeric only, oldest first', () {
      final all = [
        _e('temperature', 72.0, '14:00'),
        _e('humidity', 55, '13:00'),
        _e('temperature', 70.0, '12:00'),
        // A plugin can write a string into a normally-numeric attribute; a
        // chart cannot plot it and must not crash on it.
        _e('temperature', 'unavailable', '13:30'),
      ];
      final s = seriesFor(all, 'temperature');
      expect(s.map((e) => e.value), [70.0, 72.0]);
    });

    test('an attribute with no history is empty, not null', () {
      expect(seriesFor([_e('humidity', 55, '13:00')], 'temperature'), isEmpty);
    });
  });

  group('trendOf', () {
    test('needs two points to say anything', () {
      expect(trendOf([]), isNull);
      expect(trendOf([_e('t', 70, '12:00')]), isNull);
    });

    test('rising says so, and names when it started', () {
      // Against the oldest point HELD, not a fixed window — history is capped
      // at 500 rows, so "today" would be a guess for a chatty sensor.
      final t = trendOf([_e('t', 70.0, '09:12'), _e('t', 73.1, '14:00')])!;
      expect(t.rising, isTrue);
      expect(t.text, '3.1 since 09:12');
      // No arrow glyph: ▲/▼ are not in the app font and render as tofu.
      expect(t.text.contains('▲'), isFalse);
    });

    test('falling says so', () {
      final t = trendOf([_e('t', 74.0, '08:00'), _e('t', 70.0, '14:00')])!;
      expect(t.rising, isFalse);
      expect(t.text, '4.0 since 08:00');
    });

    test('a big move drops the decimal', () {
      final t = trendOf([_e('t', 100.0, '08:00'), _e('t', 812.0, '14:00')])!;
      expect(t.text, '712 since 08:00');
    });

    test('noise is steady, not a rounding artefact', () {
      // Without a floor, 0.01 of drift renders as "▲ 0.0 since …" — a change
      // claimed and then contradicted by its own number.
      final t = trendOf([_e('t', 70.00, '08:00'), _e('t', 70.01, '14:00')])!;
      expect(t.text, 'steady');
    });
  });
}
