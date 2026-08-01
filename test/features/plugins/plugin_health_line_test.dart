import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/plugin_entry.dart';
import 'package:hc_web/features/plugins/plugins_page.dart';

PluginEntry _p(String status, {bool enabled = true, int devices = 0}) =>
    PluginEntry(
      pluginId: 'plugin.wled',
      status: status,
      registeredAt: '2026-08-01T00:00:00Z',
      enabled: enabled,
      deviceCount: devices,
    );

void main() {
  group('pluginHealthLine', () {
    test('a stopped plugin says so, rather than claiming to be starting', () {
      // Caught on screen: stopping plugin.wled left the card reading
      // "Starting…" indefinitely, because both states shared one branch.
      expect(pluginHealthLine(_p('stopped')), 'Stopped');
    });

    test('a starting plugin still says starting', () {
      expect(pluginHealthLine(_p('starting')), 'Starting…');
    });

    test('offline names the cost, not just the state', () {
      expect(pluginHealthLine(_p('offline', devices: 9)),
          'Offline — 9 devices frozen');
    });

    test('disabled beats starting when the plugin is switched off', () {
      expect(pluginHealthLine(_p('stopped', enabled: false)), 'Stopped');
      expect(pluginHealthLine(_p('unknown', enabled: false)), 'Disabled');
    });

    test('active without an uptime does not print a dangling separator', () {
      expect(pluginHealthLine(_p('active')), 'Active');
    });
  });
}
