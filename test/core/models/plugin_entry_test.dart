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

  group('versionDiverged', () {
    PluginEntry entry({String? running, String? installed}) =>
        PluginEntry.fromJson({
          'plugin_id': 'plugin.thermostat',
          'status': 'active',
          'registered_at': '2026-07-22T08:00:00Z',
          if (running != null) 'version': running,
          if (installed != null) 'installed_version': installed,
        });

    test('the running build differing from the record is divergence', () {
      // Exactly the sandbox state: binaries rebuilt at 0.1.6 while the install
      // record still said 0.1.5. Both were reported, neither was compared, and
      // the tile called it "up to date".
      expect(
          entry(running: '0.1.6', installed: '0.1.5').versionDiverged, isTrue);
    });

    test('agreement is not divergence', () {
      expect(
          entry(running: '0.1.6', installed: '0.1.6').versionDiverged, isFalse);
    });

    test('a plugin with no install record cannot diverge', () {
      // hue is declared in homecore.toml against a build path, so it reports a
      // running version and no installed one. Absence is not disagreement, and
      // flagging it would cry wolf on every dev-declared plugin.
      expect(entry(running: '0.1.5').versionDiverged, isFalse);
      expect(entry(installed: '0.1.5').versionDiverged, isFalse);
      expect(entry().versionDiverged, isFalse);
    });
  });

  group('wouldInstall', () {
    PluginEntry entry({String? running, String? installed}) =>
        PluginEntry.fromJson({
          'plugin_id': 'plugin.ecowitt',
          'status': 'active',
          'registered_at': '2026-07-22T08:00:00Z',
          if (running != null) 'version': running,
          if (installed != null) 'installed_version': installed,
        });

    test('a genuinely newer version is worth fetching', () {
      expect(entry(running: '0.1.3', installed: '0.1.3').wouldInstall('0.1.4'),
          isTrue);
    });

    test('what is already installed is not', () {
      expect(entry(running: '0.1.4', installed: '0.1.4').wouldInstall('0.1.4'),
          isFalse);
    });

    test('what is already running is not, however stale the record', () {
      // The trap: record says 0.1.3, registry offers 0.1.4, and the process is
      // *already* 0.1.4. Comparing only against the record offered "Update to
      // v0.1.4" for the build in memory — a button that downloads what is
      // running. The record needs reconciling, not an artifact.
      expect(entry(running: '0.1.4', installed: '0.1.3').wouldInstall('0.1.4'),
          isFalse);
    });

    test('a version newer than both still offers', () {
      expect(entry(running: '0.1.4', installed: '0.1.3').wouldInstall('0.1.5'),
          isTrue);
    });

    test('an OLDER registry version is not an update', () {
      // hc-zwave ran 0.1.5 while the registry still carried 0.1.4, and the
      // plugin page offered "Update available — v0.1.4": a button that
      // installs an older build over a newer one. Inequality is not ordering.
      expect(entry(running: '0.1.5', installed: '0.1.5').wouldInstall('0.1.4'),
          isFalse);
      expect(
          entry(running: '0.1.10', installed: '0.1.10').wouldInstall('0.1.9'),
          isFalse,
          reason: '0.1.10 is newer than 0.1.9, not older');
    });

    test('newer than the record but older than what runs is not an update', () {
      // Half-ahead is still not something to fetch.
      expect(entry(running: '0.1.5', installed: '0.1.3').wouldInstall('0.1.4'),
          isFalse);
    });

    test('nothing to compare against offers nothing', () {
      expect(entry(running: '0.1.4', installed: '0.1.3').wouldInstall(null),
          isFalse);
    });
  });
}
