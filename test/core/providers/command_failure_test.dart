import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/devices_api.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/models/hc_event.dart';
import 'package:hc_web/core/providers/command_failure_provider.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/core/providers/events_provider.dart';
import 'package:hc_web/design/skins.dart';
import 'package:hc_web/shell/command_failure_banner.dart';

/// What happens to a command the house never received.
///
/// Commands are optimistic on purpose — a light switch that waits for a round
/// trip through MQTT feels broken. The bet is that a rejection gets corrected
/// by the next WS frame. The bet does not cover a *failure to deliver*, because
/// the two things that break the request (core down, network down) are the same
/// two that stop the frame arriving. So the tile went on saying the light was
/// on, for as long as the page stayed open, with the exception filed in a log
/// three navigations away.
///
/// The brief ranks *stale is a state, and it must be visible* above the
/// principles about size and layout. This is that principle applied to writes.
class _FakeDevicesApi extends DevicesApi {
  _FakeDevicesApi(this.rows) : super.fake();

  List<Map<String, dynamic>> rows;
  Object? failWith;
  int sends = 0;

  @override
  Future<List<Map<String, dynamic>>> listDevices(
          {bool includeSchema = true}) async =>
      rows;

  @override
  Future<void> setDeviceState(String id, Map<String, dynamic> state) async {
    sends++;
    if (failWith case final e?) throw e;
  }
}

Map<String, dynamic> _row(String id, Map<String, dynamic> state) => {
      'device_id': id,
      'name': id,
      'plugin_id': 'plugin.test',
      'available': true,
      'attributes': state,
      'last_seen': '2026-08-06T00:00:00Z',
    };

({ProviderContainer c, _FakeDevicesApi api}) _harness(
    {Map<String, dynamic> state = const {'on': false}}) {
  final api = _FakeDevicesApi([_row('lamp', state)]);
  final c = ProviderContainer(overrides: [
    devicesApiProvider.overrideWithValue(api),
    eventsStreamProvider.overrideWith((ref) => const Stream<HcEvent>.empty()),
  ]);
  addTearDown(c.dispose);
  return (c: c, api: api);
}

DeviceState _lamp(ProviderContainer c) =>
    c.read(devicesProvider).value!.firstWhere((d) => d.id == 'lamp');

void main() {
  group('a command the house did not take', () {
    test('moves the tile immediately — the optimistic path still works',
        () async {
      final h = _harness();
      await h.c.read(devicesProvider.future);
      expect(_lamp(h.c).state['on'], false);

      final pending =
          h.c.read(devicesProvider.notifier).command('lamp', {'on': true});
      // Before the await resolves, the tile already reads as on. This is the
      // behaviour the rollback must not cost us.
      expect(_lamp(h.c).state['on'], true);
      await pending;
    });

    test('puts the value back when the send fails', () async {
      final h = _harness();
      await h.c.read(devicesProvider.future);
      h.api.failWith = Exception('connection refused');

      await h.c.read(devicesProvider.notifier).command('lamp', {'on': true});

      expect(_lamp(h.c).state['on'], false,
          reason: 'the tile is still claiming a light that never switched');
    });

    test('says which device, by name', () async {
      final h = _harness();
      await h.c.read(devicesProvider.future);
      h.api.failWith = Exception('connection refused');

      expect(h.c.read(commandFailureProvider), isNull);
      await h.c.read(devicesProvider.notifier).command('lamp', {'on': true});

      final f = h.c.read(commandFailureProvider);
      expect(f, isNotNull, reason: 'the failure went nowhere anyone can see');
      expect(f!.deviceId, 'lamp');
      // "A command failed" is not something anyone can act on; the device that
      // did not move is the whole content of the message.
      expect(f.deviceName, isNotEmpty);
    });

    test('a later success clears it', () async {
      final h = _harness();
      await h.c.read(devicesProvider.future);
      h.api.failWith = Exception('down');
      await h.c.read(devicesProvider.notifier).command('lamp', {'on': true});
      expect(h.c.read(commandFailureProvider), isNotNull);

      h.api.failWith = null;
      await h.c.read(devicesProvider.notifier).command('lamp', {'on': true});
      expect(h.c.read(commandFailureProvider), isNull,
          reason: 'a banner outlived the outage it was reporting');
    });

    test('a key the device never had is removed, not set to null', () async {
      final h = _harness(state: {'on': false});
      await h.c.read(devicesProvider.future);
      h.api.failWith = Exception('down');

      await h.c
          .read(devicesProvider.notifier)
          .command('lamp', {'brightness_pct': 40});

      expect(_lamp(h.c).state.containsKey('brightness_pct'), isFalse,
          reason: 'a null brightness is not the same as no brightness — '
              'controls branch on the key being absent');
    });

    test('a frame that lands mid-flight wins over the rollback', () async {
      // The case that makes this more than a snapshot restore. A WS frame can
      // arrive while the doomed request is still out; that frame is the truth.
      // Undoing back to a pre-command snapshot would replace a real reading
      // with an older one — the same lie, pointed the other way.
      final h = _harness();
      await h.c.read(devicesProvider.future);
      h.api.failWith = Exception('down');

      final pending =
          h.c.read(devicesProvider.notifier).command('lamp', {'on': true});

      // Someone flips the physical switch; core tells us before our request
      // gives up. `on` is now true for a real reason.
      final notifier = h.c.read(devicesProvider.notifier);
      final live = h.c.read(devicesProvider).value!;
      notifier.state = AsyncData([
        for (final d in live)
          if (d.id == 'lamp')
            d.copyWith(state: {...d.state, 'on': true, 'brightness_pct': 80})
          else
            d,
      ]);

      await pending;

      expect(_lamp(h.c).state['on'], true,
          reason: 'the rollback clobbered a live frame with a stale snapshot');
      expect(_lamp(h.c).state['brightness_pct'], 80);
    });
  });

  group('the banner is on a screen someone can see', () {
    // The failure this guards is one this repo has already shipped once: a
    // notice band was added to `plugin_sheet.dart`, whose only entry point had
    // no callers anywhere, so the feature rendered on no reachable screen and
    // the tests were all green. A widget that exists is not a widget anyone
    // sees.
    test('both chromes embed it', () {
      for (final shell in ['touch_chrome.dart', 'wall_chrome.dart']) {
        final src = File('lib/shell/$shell').readAsStringSync();
        expect(src, contains('CommandFailureBanner()'),
            reason: '$shell no longer shows failed commands');
      }
    });

    testWidgets('shows the device name, and nothing at all when clear',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      Widget host() => UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: hcTheme(HcSkin.midnight),
              home: const Scaffold(body: CommandFailureBanner()),
            ),
          );

      await tester.pumpWidget(host());
      expect(find.byType(Text), findsNothing,
          reason: 'a banner with nothing to report should occupy no space');

      container.read(commandFailureProvider.notifier).report(CommandFailure(
            deviceId: 'lamp',
            deviceName: 'Hallway Overhead',
            error: Exception('down'),
            at: DateTime(2026, 8, 6),
          ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Hallway Overhead'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);

      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Hallway Overhead'), findsNothing);
    });
  });
}
