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
          final updated = current
              .map((d) => d.id == event.deviceId
                  ? d.copyWith(
                      available: true,
                      state: Map<String, dynamic>.from(d.state)
                        ..addAll(event.current!),
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
      state = AsyncData(raw.map(DeviceState.fromJson).toList());
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

    try {
      await ref.read(devicesApiProvider).setDeviceState(id, patch);
      ref.read(commandFailureProvider.notifier).clear();
    } catch (e) {
      _revert(id, optimistic, before);
      ref.read(commandFailureProvider.notifier).report(CommandFailure(
            deviceId: id,
            deviceName: before?.displayName ?? id,
            error: e,
            at: DateTime.now(),
          ));
    }
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
