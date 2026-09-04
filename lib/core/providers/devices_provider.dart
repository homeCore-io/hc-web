import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/devices_api.dart';
import '../models/device_state.dart';
import 'auth_provider.dart';
import 'command_failure_provider.dart';
import 'events_provider.dart';

final devicesApiProvider = Provider<DevicesApi>((ref) {
  return DevicesApi(ref.watch(homecoreClientProvider));
});

class DevicesNotifier extends AsyncNotifier<List<DeviceState>> {
  // Guards against a refetch storm when several events for unknown devices
  // arrive before the first refetch completes.
  bool _refetching = false;

  /// What we have told a device to be, and how long we will hold that belief.
  ///
  /// **Why a toggle bounced.** The optimistic patch lands instantly, then the
  /// write goes out — and a plugin poll that *started before the write* lands
  /// after it, carrying the old value. The tile flips on, flips back off, then
  /// flips on again when the next poll finally sees the change. John: *"toggling
  /// these causes the toggles to bounce on/off a couple times before settling
  /// which is wrong."*
  ///
  /// It is not enough to apply the optimistic patch and hope; a frame that
  /// contradicts a write still in flight is stale by definition, and the only
  /// thing that knows it is stale is the write. So we remember what we asked
  /// for and ignore contradictions of exactly those keys until the house
  /// agrees or the window closes.
  final _expecting = <String, _Expectation>{};

  /// How long a write is allowed to outrank what the house says.
  ///
  /// Long enough to cover a poll cycle and a slow bridge; short enough that a
  /// command the device genuinely refused shows the truth while the finger is
  /// still near the tile. Suppressing forever would be the older bug — a tile
  /// insisting a light is on — pointed the other way.
  static const _holdFor = Duration(seconds: 4);

  @override
  Future<List<DeviceState>> build() async {
    // Listen for WebSocket events and update devices in-place
    ref.listen(eventsStreamProvider, (_, next) {
      next.whenData((event) {
        final current = state.value;
        if (current == null) return;

        if (event.type == 'device_state_changed' &&
            event.deviceId != null &&
            event.current != null) {
          // A state frame for a device we don't have yet means it just
          // registered (discovery add, Hue pairing, Z-Wave inclusion…). The
          // in-place map below can't add it, so pull the full list once —
          // otherwise the new device stays invisible until a manual refresh.
          if (!current.any((d) => d.id == event.deviceId)) {
            _refetchAll();
            return;
          }
          // copyWith, not a hand-rolled rebuild. The old code dropped `schema`
          // on every state change — and state changes are constant — so
          // schema-driven controls degraded to heuristics within seconds of the
          // app loading. It dropped ui_hint, status_icon and last_seen too.
          final incoming = _settled(event.deviceId!, event.current!);
          final updated = current
              .map((d) => d.id == event.deviceId
                  ? d.copyWith(
                      available: true,
                      state: Map<String, dynamic>.from(d.state)
                        ..addAll(incoming),
                      lastSeen: DateTime.now(),
                    )
                  : d)
              .toList();
          state = AsyncData(updated);
        } else if (event.type == 'device_availability_changed' &&
            event.deviceId != null) {
          // Same as above: an availability frame for an unknown device is a
          // fresh registration — reload rather than drop it.
          if (!current.any((d) => d.id == event.deviceId)) {
            _refetchAll();
            return;
          }
          final avail = event.available ?? false;
          // copyWith, not a hand-rolled rebuild: the old code dropped schema,
          // ui_hint, status_icon and last_seen, so an availability event silently
          // wiped a device's capability schema and its controls fell back to
          // heuristics.
          final updated = current
              .map((d) =>
                  d.id == event.deviceId ? d.copyWith(available: avail) : d)
              .toList();
          state = AsyncData(updated);
        } else if (event.type == 'custom' &&
            event.data['event_type'] == 'device_deleted') {
          // Core signals a device removal (plugin unregister, incl. unpairing a
          // hub) as a Custom event: type "custom", event_type "device_deleted",
          // with the id nested under `payload` — NOT a top-level device_id like
          // state/availability events. Without this the tile lingered until a
          // manual refresh. Drop it so the list updates live.
          final payload = event.data['payload'];
          final removedId =
              payload is Map ? payload['device_id'] as String? : null;
          if (removedId != null) {
            state = AsyncData(current.where((d) => d.id != removedId).toList());
          }
        }
      });
    });

    final api = ref.read(devicesApiProvider);
    final raw = await api.listDevices();
    return raw.map(DeviceState.fromJson).toList();
  }

  /// Reload the full device list — used when a WS frame references a device we
  /// don't have yet (a fresh registration). The `_refetching` guard collapses a
  /// burst of unknown-device frames into a single reload.
  Future<void> _refetchAll() async {
    if (_refetching) return;
    _refetching = true;
    try {
      final raw = await ref.read(devicesApiProvider).listDevices();
      // A full reload is a snapshot like any other, and just as able to be
      // older than a write still in flight.
      state = AsyncData([
        for (final d in raw.map(DeviceState.fromJson))
          d.copyWith(state: _settled(d.id, d.state, whole: true)),
      ]);
    } catch (_) {
      // Keep the current list on a transient failure; the next frame retries.
    } finally {
      _refetching = false;
    }
  }

  /// Sends a command, and applies it optimistically.
  ///
  /// The tile must move the instant you touch it — waiting for the round trip
  /// through MQTT and back makes a light switch feel broken. If core *rejects*
  /// it, the next WS frame corrects us.
  ///
  /// If the send never lands, nothing corrects us. The two things that break
  /// the request — core down, network down — are the same two that stop the
  /// frame arriving, so the moment the optimistic state most needs correcting
  /// is the moment nothing is coming to correct it. That left the tile saying a
  /// light was on until someone reloaded the page, which is the exact shape of
  /// thing the brief means by *stale is a state, and it must be visible*.
  ///
  /// So a failed send is put back and said out loud. Nothing is rethrown:
  /// all 41 call sites are `onPressed: () => notifier.command(...)`, so a throw
  /// here is an unhandled Future, and this app installs no zone guard.
  Future<void> command(String id, Map<String, dynamic> patch) async {
    final current = state.value ?? [];
    DeviceState? before;
    for (final d in current) {
      if (d.id == id) before = d;
    }

    // Held so the rollback can recognise its own work. See [_revert].
    DeviceState? optimistic;
    state = AsyncData([
      for (final d in current)
        if (d.id == id)
          optimistic = d.copyWith(
              state: Map<String, dynamic>.from(d.state)..addAll(patch))
        else
          d,
    ]);

    _expecting[id] = _Expectation(
      patch: Map<String, dynamic>.from(patch),
      until: DateTime.now().add(_holdFor),
    );

    try {
      await ref.read(devicesApiProvider).setDeviceState(id, patch);
      ref.read(commandFailureProvider.notifier).clear();
    } catch (e) {
      // The write never landed, so there is nothing to hold out for.
      _expecting.remove(id);
      _revert(id, optimistic, before);
      ref.read(commandFailureProvider.notifier).report(CommandFailure(
            deviceId: id,
            deviceName: before?.displayName ?? id,
            error: e,
            at: DateTime.now(),
          ));
    }
  }

  /// An incoming reading with the stale contradictions of a live write removed.
  ///
  /// Only the keys we wrote are ever touched, and only while the write is still
  /// young: everything else in the frame is applied as it arrived, because a
  /// command about `on` says nothing about a temperature. The moment the house
  /// reports what we asked for, the expectation has done its job and goes.
  ///
  /// [whole] is for a full reload, where a missing key means *this device does
  /// not report it* rather than *this frame did not mention it* — so the
  /// expected value has to be put back rather than merely left alone.
  Map<String, dynamic> _settled(
    String id,
    Map<String, dynamic> incoming, {
    bool whole = false,
  }) {
    final held = _expecting[id];
    if (held == null) return incoming;
    if (DateTime.now().isAfter(held.until)) {
      _expecting.remove(id);
      return incoming;
    }

    final out = Map<String, dynamic>.from(incoming);
    var agreed = true;
    held.patch.forEach((key, want) {
      if (!incoming.containsKey(key)) {
        // A frame that is silent about the key neither confirms nor denies it.
        if (whole) out[key] = want;
        agreed = false;
        return;
      }
      if (_same(incoming[key], want)) return;
      out[key] = want;
      agreed = false;
    });

    if (agreed) _expecting.remove(id);
    return out;
  }

  /// Value equality that does not mind `25` arriving where `25.0` was sent.
  static bool _same(Object? a, Object? b) {
    if (a is num && b is num) return a.toDouble() == b.toDouble();
    return a == b;
  }

  /// Undoes an optimistic patch — but only if nothing has touched the device
  /// since we applied it.
  ///
  /// A WS frame can land while the doomed request is still in flight, and that
  /// frame is the truth: someone flipped the physical switch, and the light
  /// really is on now. Undoing to a pre-command snapshot would replace a real
  /// reading with an older one — the same lie, pointed the other way.
  ///
  /// Telling those apart needs *identity*, not equality. Comparing values
  /// cannot distinguish "nobody has changed this" from "somebody set it to the
  /// same value I did", and the second is precisely the mid-flight case: our
  /// optimistic `on: true` and core's real `on: true` are indistinguishable by
  /// value. Every update in this notifier goes through `copyWith`, which mints
  /// a new object, so an unchanged device is still the exact instance we put
  /// there and a changed one never is.
  ///
  /// Erring toward leaving it alone is the right bias anyway: whatever replaced
  /// our object came from somewhere more current than our snapshot.
  void _revert(String id, DeviceState? optimistic, DeviceState? before) {
    if (optimistic == null || before == null) return;
    final now = state.value ?? [];
    var untouched = false;
    for (final d in now) {
      if (d.id == id && identical(d, optimistic)) untouched = true;
    }
    if (!untouched) return;

    state = AsyncData([
      for (final d in now)
        if (d.id == id) before else d,
    ]);
  }

  Future<void> updateDevice(String id, Map<String, dynamic> body) async {
    final raw = await ref.read(devicesApiProvider).updateDevice(id, body);
    final updated = DeviceState.fromJson(raw);
    final current = state.value ?? [];

    state = AsyncData([
      for (final d in current)
        if (d.id == id)
          // PATCH /devices/:id does not echo the schema (only ?include_schema=
          // does), so taking the response wholesale would drop it — renaming a
          // device would quietly cost it its controls. Carry the old one over.
          updated.copyWith(schema: d.schema)
        else
          d,
    ]);
  }

  Future<void> deleteDevice(String id) async {
    await ref.read(devicesApiProvider).deleteDevice(id);
    final current = state.value ?? [];
    state = AsyncData(current.where((d) => d.id != id).toList());
  }
}

final devicesProvider =
    AsyncNotifierProvider<DevicesNotifier, List<DeviceState>>(
  DevicesNotifier.new,
);

/// What we told one device to be, and how long we will hold that belief.
class _Expectation {
  const _Expectation({required this.patch, required this.until});

  final Map<String, dynamic> patch;
  final DateTime until;
}
