import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/devices_api.dart';
import '../models/device_state.dart';
import 'auth_provider.dart';
import 'events_provider.dart';

final devicesApiProvider = Provider<DevicesApi>((ref) {
  return DevicesApi(ref.watch(homecoreClientProvider));
});

class DevicesNotifier extends AsyncNotifier<List<DeviceState>> {
  @override
  Future<List<DeviceState>> build() async {
    // Listen for WebSocket events and update devices in-place
    ref.listen(eventsStreamProvider, (_, next) {
      next.whenData((event) {
        final current = state.valueOrNull;
        if (current == null) return;

        if (event.type == 'device_state_changed' &&
            event.deviceId != null &&
            event.current != null) {
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
            state =
                AsyncData(current.where((d) => d.id != removedId).toList());
          }
        }
      });
    });

    final api = ref.read(devicesApiProvider);
    final raw = await api.listDevices();
    return raw.map(DeviceState.fromJson).toList();
  }

  /// Sends a command, and applies it optimistically.
  ///
  /// The tile must move the instant you touch it — waiting for the round trip
  /// through MQTT and back makes a light switch feel broken. If core rejects it,
  /// the next WS frame corrects us.
  Future<void> command(String id, Map<String, dynamic> patch) async {
    final current = state.valueOrNull ?? [];
    state = AsyncData([
      for (final d in current)
        if (d.id == id)
          d.copyWith(state: Map<String, dynamic>.from(d.state)..addAll(patch))
        else
          d,
    ]);
    await ref.read(devicesApiProvider).setDeviceState(id, patch);
  }

  Future<void> updateDevice(String id, Map<String, dynamic> body) async {
    final raw = await ref.read(devicesApiProvider).updateDevice(id, body);
    final updated = DeviceState.fromJson(raw);
    final current = state.valueOrNull ?? [];

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
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.where((d) => d.id != id).toList());
  }
}

final devicesProvider =
    AsyncNotifierProvider<DevicesNotifier, List<DeviceState>>(
  DevicesNotifier.new,
);
