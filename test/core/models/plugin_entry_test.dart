import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/plugin_entry.dart';

void main() {
  group('PluginEntry.fromJson', () {
    test('parses active plugin', () {
      final p = PluginEntry.fromJson({
        'plugin_id': 'plugin.hue',
        'status': 'active',
        'registered_at': '2026-03-23T08:00:00Z',
      });

      expect(p.pluginId, 'plugin.hue');
      expect(p.status, 'active');
      expect(p.isActive, isTrue);
    });

    test('parses offline plugin', () {
      final p = PluginEntry.fromJson({
        'plugin_id': 'plugin.zwave',
        'status': 'offline',
        'registered_at': '2026-03-23T08:00:00Z',
      });

      expect(p.isActive, isFalse);
    });

    test('defaults status to unknown on missing field', () {
      final p = PluginEntry.fromJson({
        'plugin_id': 'plugin.sonos',
        'registered_at': '2026-03-23T08:00:00Z',
      });

      expect(p.status, 'unknown');
      expect(p.isActive, isFalse);
    });

    test('handles missing registered_at', () {
      final p = PluginEntry.fromJson({
        'plugin_id': 'plugin.lutron',
        'status': 'active',
      });

      expect(p.registeredAt, '');
    });
  });
}
