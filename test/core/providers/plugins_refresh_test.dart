import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/plugins_api.dart';
import 'package:hc_web/core/models/hc_event.dart';
import 'package:hc_web/core/providers/events_provider.dart';
import 'package:hc_web/core/providers/plugins_provider.dart';

/// Serves whatever the test last handed it, or throws on demand.
class _FakePluginsApi extends PluginsApi {
  _FakePluginsApi(this.rows) : super.fake();

  List<Map<String, dynamic>> rows;
  Object? failWith;
  int calls = 0;

  @override
  Future<List<Map<String, dynamic>>> listPlugins() async {
    calls++;
    if (failWith case final e?) throw e;
    return rows;
  }
}

Map<String, dynamic> _row(String id, {int devices = 0, String? status}) => {
      'plugin_id': id,
      'status': status ?? 'active',
      'device_count': devices,
      'registered_at': '2026-08-01T00:00:00Z',
    };

ProviderContainer _containerWith(_FakePluginsApi api) {
  final c = ProviderContainer(overrides: [
    pluginsApiProvider.overrideWithValue(api),
    // The notifier listens to the event stream in build(); a test has no
    // WebSocket and does not need one.
    eventsStreamProvider.overrideWith((ref) => const Stream<HcEvent>.empty()),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('PluginsNotifier.refresh', () {
    test('picks up a device count that changed after the first load', () async {
      // The bug this guards: hc-ecowitt sat at 0 devices on screen while core
      // had long since recorded 9, because nothing refetched.
      final api = _FakePluginsApi([_row('plugin.ecowitt')]);
      final c = _containerWith(api);

      await c.read(pluginsProvider.future);
      expect(c.read(pluginsProvider).value!.single.deviceCount, 0);

      api.rows = [_row('plugin.ecowitt', devices: 9)];
      await c.read(pluginsProvider.notifier).refresh();

      expect(c.read(pluginsProvider).value!.single.deviceCount, 9);
    });

    test('a failed poll keeps the last good list instead of blanking it',
        () async {
      final api = _FakePluginsApi([_row('plugin.ecowitt', devices: 9)]);
      final c = _containerWith(api);
      await c.read(pluginsProvider.future);

      api.failWith = Exception('core restarting');
      await c.read(pluginsProvider.notifier).refresh();

      final state = c.read(pluginsProvider);
      expect(state.hasError, isFalse, reason: 'a poll must not surface errors');
      expect(state.value!.single.deviceCount, 9);
    });

    test('recovers on the next poll after a failure', () async {
      final api = _FakePluginsApi([_row('plugin.ecowitt', devices: 9)]);
      final c = _containerWith(api);
      await c.read(pluginsProvider.future);

      api.failWith = Exception('down');
      await c.read(pluginsProvider.notifier).refresh();
      api
        ..failWith = null
        ..rows = [_row('plugin.ecowitt', devices: 11)];
      await c.read(pluginsProvider.notifier).refresh();

      expect(c.read(pluginsProvider).value!.single.deviceCount, 11);
    });
  });

  group('pluginsAutoRefreshProvider', () {
    test('polls while watched and stops once nothing is watching', () {
      fakeAsync((async) {
        final api = _FakePluginsApi([_row('plugin.ecowitt')]);
        final c = _containerWith(api);
        c.read(pluginsProvider.future);
        async.flushMicrotasks();
        final afterBuild = api.calls;

        final sub = c.listen(pluginsAutoRefreshProvider, (_, __) {});
        async.elapse(const Duration(seconds: 25));
        final polled = api.calls;
        expect(polled, greaterThan(afterBuild),
            reason: 'a watched view should be polling');

        sub.close();
        async.elapse(const Duration(seconds: 25));
        expect(api.calls, polled,
            reason: 'the timer must die with its last watcher');
      });
    });
  });
}
