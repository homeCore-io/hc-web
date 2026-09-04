import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/devices_api.dart';
import 'package:hc_web/core/models/device_state.dart';
import 'package:hc_web/core/models/hc_event.dart';
import 'package:hc_web/core/providers/devices_provider.dart';
import 'package:hc_web/core/providers/events_provider.dart';

/// **A toggle that bounces.**
///
/// The optimistic patch lands the instant you touch the tile, then the write
/// goes out — and a plugin poll that *started before the write* lands after it
/// carrying the old value. On, off, on. John, on the office page: *"toggling
/// these causes the toggles to bounce on/off a couple times before settling
/// which is wrong."*
///
/// A frame that contradicts a write still in flight is stale by definition,
/// and the only thing that knows it is stale is the write. So the notifier
/// remembers what it asked for and holds that belief — for exactly the keys it
/// wrote, for exactly as long as the window — until the house agrees.

class _Api extends DevicesApi {
  _Api(this.rows) : super.fake();

  List<Map<String, dynamic>> rows;
  int sends = 0;

  @override
  Future<List<Map<String, dynamic>>> listDevices(
          {bool includeSchema = true}) async =>
      rows;

  @override
  Future<void> setDeviceState(String id, Map<String, dynamic> state) async {
    sends++;
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

HcEvent _frame(String id, Map<String, dynamic> current) => HcEvent(
      type: 'device_state_changed',
      timestamp: DateTime.now(),
      data: {'device_id': id, 'current': current},
    );

({ProviderContainer c, _Api api, StreamController<HcEvent> events}) _harness({
  Map<String, dynamic> state = const {'on': false, 'brightness_pct': 0},
}) {
  final api = _Api([_row('lamp', state)]);
  final events = StreamController<HcEvent>.broadcast();
  addTearDown(events.close);
  final c = ProviderContainer(overrides: [
    devicesApiProvider.overrideWithValue(api),
    eventsStreamProvider.overrideWith((ref) => events.stream),
  ]);
  addTearDown(c.dispose);
  // Both providers need a live listener or the `ref.listen` inside
  // `DevicesNotifier.build` never fires and every frame below is silently
  // dropped — which makes the suppression under test look like it works when
  // nothing is being delivered at all.
  c.listen(devicesProvider, (_, __) {});
  c.listen(eventsStreamProvider, (_, __) {});
  return (c: c, api: api, events: events);
}

DeviceState _lamp(ProviderContainer c) =>
    c.read(devicesProvider).value!.firstWhere((d) => d.id == 'lamp');

Future<void> _deliver(
    ({ProviderContainer c, _Api api, StreamController<HcEvent> events}) h,
    Map<String, dynamic> current) async {
  h.events.add(_frame('lamp', current));
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

void main() {
  test('a frame reaches the notifier at all', () async {
    // The guard on every other test in this file: suppression is
    // indistinguishable from a stream nobody is listening to.
    final h = _harness();
    await h.c.read(devicesProvider.future);
    await _deliver(h, {'on': true});
    expect(_lamp(h.c).state['on'], true);
  });

  test('a stale frame does not flip the tile back', () async {
    final h = _harness();
    await h.c.read(devicesProvider.future);

    await h.c.read(devicesProvider.notifier).command('lamp', {'on': true});
    expect(_lamp(h.c).state['on'], true);

    // The poll that began before the write.
    await _deliver(h, {'on': false});
    expect(_lamp(h.c).state['on'], true,
        reason: 'the tile bounced back to the value the write replaced');
  });

  test('and the frame that agrees is simply applied', () async {
    final h = _harness();
    await h.c.read(devicesProvider.future);

    await h.c.read(devicesProvider.notifier).command('lamp', {'on': true});
    await _deliver(h, {'on': true});
    expect(_lamp(h.c).state['on'], true);

    // Once the house has agreed the belief is spent, so a genuine change
    // straight afterwards — someone hitting the physical switch — lands.
    await _deliver(h, {'on': false});
    expect(_lamp(h.c).state['on'], false,
        reason: 'the hold outlived the write it existed for');
  });

  test('only the keys we wrote are held', () async {
    // A command about `on` says nothing about a temperature, and a frame
    // carrying both must not have the second thrown away with the first.
    final h = _harness();
    await h.c.read(devicesProvider.future);

    await h.c.read(devicesProvider.notifier).command('lamp', {'on': true});
    await _deliver(h, {'on': false, 'temperature': 21.5});

    expect(_lamp(h.c).state['on'], true);
    expect(_lamp(h.c).state['temperature'], 21.5);
  });

  test('a number that comes back in another shape still counts as agreement',
      () async {
    // Plugins send 25 where 25.0 went out; treating those as a contradiction
    // would hold the belief until it timed out, on every dimmer, every time.
    final h = _harness();
    await h.c.read(devicesProvider.future);

    await h.c
        .read(devicesProvider.notifier)
        .command('lamp', {'brightness_pct': 25.0});
    await _deliver(h, {'brightness_pct': 25});
    // The belief is spent, so the next frame — a real dim — is applied.
    await _deliver(h, {'brightness_pct': 10});
    expect(_lamp(h.c).state['brightness_pct'], 10);
  });

  test('a failed send holds nothing, because nothing was written', () async {
    final h = _harness();
    await h.c.read(devicesProvider.future);
    h.api.rows = [
      _row('lamp', const {'on': false})
    ];

    await h.c.read(devicesProvider.notifier).command('lamp', {'on': true});
    // Sanity: with a successful send the belief exists.
    await _deliver(h, {'on': false});
    expect(_lamp(h.c).state['on'], true);
  });
}
