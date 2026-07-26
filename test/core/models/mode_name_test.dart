import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/mode_state.dart';

/// Built through `jsonDecode`, like the real payload — a Dart map literal
/// infers `Map<dynamic, dynamic>` and would not exercise the same casts.
ModeState _mode(Map<String, dynamic> json) =>
    ModeState.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);

void main() {
  group('a mode is called what the hub calls it', () {
    test('the name on the config is used', () {
      // Both live modes carry one — "Night Mode", "Day Mode" — and nothing
      // read it, so displayName invented names from the id instead.
      final m = _mode({
        'config': {'id': 'mode_day', 'kind': 'solar', 'name': 'Day Mode'},
        'state': {'attributes': {}},
      });
      expect(m.displayName, 'Day Mode');
    });

    test('the name on the backing device is used when the config has none', () {
      final m = _mode({
        'config': {'id': 'mode_night', 'kind': 'solar'},
        'state': {'name': 'Night Mode', 'attributes': {}},
      });
      expect(m.displayName, 'Night Mode');
    });

    test('two modes no longer read in two different styles', () {
      // The bug, exactly: a hard-coded case for mode_night returned "Night
      // Mode" while everything else got a lowercase strip, so one dropdown
      // showed "Night Mode" above "day".
      final night = _mode({
        'config': {'id': 'mode_night', 'kind': 'solar'},
        'state': {'attributes': {}},
      });
      final day = _mode({
        'config': {'id': 'mode_day', 'kind': 'solar'},
        'state': {'attributes': {}},
      });
      expect(night.displayName, 'Night');
      expect(day.displayName, 'Day');
    });

    test('an unnamed multi-word mode still title-cases', () {
      final m = _mode({
        'config': {'id': 'mode_guest_room', 'kind': 'manual'},
        'state': {'attributes': {}},
      });
      expect(m.displayName, 'Guest Room');
      expect(m.displayName, isNot(contains('_')));
    });

    test('a blank name falls back rather than rendering empty', () {
      final m = _mode({
        'config': {'id': 'mode_away', 'kind': 'manual', 'name': '   '},
        'state': {'attributes': {}},
      });
      expect(m.displayName, 'Away');
    });
  });
}
