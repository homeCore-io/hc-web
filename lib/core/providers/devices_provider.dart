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
          final updated = current.map((d) {
            if (d.id != event.deviceId) return d;
            return DeviceState(
              id: d.id,
              canonicalName: d.canonicalName,
              pluginId: d.pluginId,
              name: d.name,
              area: d.area,
              deviceType: d.deviceType,
              available: true,
              state: Map<String, dynamic>.from(d.state)..addAll(event.current!),
            );
          }).toList();
          state = AsyncData(updated);
        } else if (event.type == 'device_availability_changed' &&
            event.deviceId != null) {
          final avail = event.available ?? false;
          final updated = current.map((d) {
            if (d.id != event.deviceId) return d;
            return DeviceState(
              id: d.id,
              canonicalName: d.canonicalName,
              pluginId: d.pluginId,
              name: d.name,
              area: d.area,
              deviceType: d.deviceType,
              available: avail,
              state: d.state,
            );
          }).toList();
          state = AsyncData(updated);
        }
      });
    });

    final api = ref.read(devicesApiProvider);
    final raw = await api.listDevices();
    return raw.map(DeviceState.fromJson).toList();
  }

  Future<void> updateDevice(String id, Map<String, dynamic> body) async {
    final raw = await ref.read(devicesApiProvider).updateDevice(id, body);
    final updated = DeviceState.fromJson(raw);
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.map((d) => d.id == id ? updated : d).toList());
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
