import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/models/plugin_entry.dart';
import 'package:hc_web/core/rules/rule.dart';
import 'package:hc_web/features/manage/manage_attention.dart';

int _n = 0;
HcRule _rule({bool enabled = true, String? error}) =>
    HcRule(id: 'r${_n++}', name: 'a rule', enabled: enabled, error: error);

DeviceState _device(String id, String plugin, {required bool available}) =>
    DeviceState.fromJson({
      'device_id': id,
      'plugin_id': plugin,
      'available': available,
      'attributes': const <String, dynamic>{},
    });

PluginEntry _plugin(String id, String status) => PluginEntry.fromJson({
      'plugin_id': id,
      'status': status,
    });

void main() {
  group('a check that has not answered is not a clean bill', () {
    test('nothing loaded, nothing claimed', () {
      // The failure this guards: `?? 0` somewhere in the chain turns "still
      // fetching" into "zero problems", and Manage cheerfully reports a healthy
      // house it has not looked at.
      expect(buildAttention(), isEmpty);
    });

    test('a zero from a check that did answer is also silence', () {
      expect(
        buildAttention(
          rules: [_rule()],
          devices: [_device('d1', 'plugin.hue', available: true)],
          plugins: [_plugin('plugin.hue', 'active')],
          staleRefs: 0,
          deniedToday: 0,
        ),
        isEmpty,
      );
    });
  });

  group('what counts as a finding', () {
    test('stale references are the loudest thing here', () {
      final items = buildAttention(staleRefs: 3);
      expect(items, hasLength(1));
      expect(items.single.level, AttentionLevel.bad);
      expect(items.single.headline,
          '3 automations point at devices that no longer exist.');
      expect(items.single.route, '/admin/maintenance');
    });

    test('one of something reads as one, not "1 automations"', () {
      expect(buildAttention(staleRefs: 1).single.headline,
          '1 automation points at a device that no longer exists.');
      expect(buildAttention(deniedToday: 1).single.headline,
          '1 sign-in was denied today.');
      expect(
        buildAttention(plugins: [_plugin('p', 'offline')]).single.headline,
        '1 plugin is offline.',
      );
    });

    test('a rule that failed to load is reported', () {
      final items = buildAttention(rules: [_rule(error: 'bad toml'), _rule()]);
      expect(items.single.headline, '1 automation failed to load.');
      expect(items.single.level, AttentionLevel.bad);
    });

    test('some rules disabled is housekeeping, not a finding', () {
      // Deliberate: a few rules off is how people use the app. Reporting it
      // would make the band permanent, and a permanent warning is furniture.
      final items = buildAttention(
        rules: [_rule(enabled: false), _rule(), _rule()],
      );
      expect(items, isEmpty);
    });

    test('every rule disabled means the house runs on nothing', () {
      final items =
          buildAttention(rules: [_rule(enabled: false), _rule(enabled: false)]);
      expect(items.single.headline, 'All 2 automations are disabled.');
      expect(items.single.level, AttentionLevel.warn);
    });

    test('a house with no rules at all is not "all disabled"', () {
      expect(buildAttention(rules: const []), isEmpty);
    });

    test('a device is orphaned only when its plugin has nothing else live', () {
      // hue is mid-restart: one device unavailable, another still live. That is
      // a restart, not an orphan, and reporting it would fire on every deploy.
      final restarting = buildAttention(devices: [
        _device('hue-1', 'plugin.hue', available: false),
        _device('hue-2', 'plugin.hue', available: true),
      ]);
      expect(restarting, isEmpty);

      final gone = buildAttention(devices: [
        _device('old-1', 'plugin.removed', available: false),
        _device('hue-2', 'plugin.hue', available: true),
      ]);
      expect(gone.single.headline, '1 device has no plugin behind it.');
    });
  });

  test('worst first', () {
    final items = buildAttention(
      staleRefs: 2,
      deniedToday: 4,
      plugins: [_plugin('p', 'offline')],
      devices: [_device('x', 'plugin.gone', available: false)],
    );
    expect(items.map((i) => i.level).toList(), [
      AttentionLevel.bad,
      AttentionLevel.bad,
      AttentionLevel.warn,
      AttentionLevel.warn,
    ]);
  });

  test('every finding points somewhere that exists', () {
    final routes = buildAttention(
      staleRefs: 1,
      deniedToday: 1,
      rules: [_rule(error: 'x', enabled: false)],
      plugins: [_plugin('p', 'offline')],
      devices: [_device('x', 'plugin.gone', available: false)],
    ).map((i) => i.route).toSet();

    // The band is only useful if "Review →" lands somewhere. These are checked
    // against app.dart by manage_routes_test.
    expect(routes, {
      '/admin/maintenance',
      '/automations',
      '/plugins',
      '/admin/audit',
    });
  });
}
