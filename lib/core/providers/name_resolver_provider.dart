import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/device_state.dart';
import '../models/mode_state.dart';
import 'devices_provider.dart';
import 'modes_provider.dart';

// ─── Device name resolver ─────────────────────────────────────────────────────

class DeviceNameResolver {
  final List<DeviceState> devices;

  const DeviceNameResolver(this.devices);

  String resolve(String id) {
    if (id.isEmpty) return id;
    for (final d in devices) {
      if (d.id == id) return d.displayName;
    }
    return id;
  }
}

final deviceNameResolverProvider = Provider<DeviceNameResolver>((ref) {
  final devices = ref.watch(devicesProvider).valueOrNull ?? [];
  return DeviceNameResolver(devices);
});

// ─── Mode name resolver ───────────────────────────────────────────────────────

class ModeNameResolver {
  final List<ModeState> modes;

  const ModeNameResolver(this.modes);

  String resolve(String id) {
    if (id.isEmpty) return id;
    for (final m in modes) {
      if (m.id == id) return m.displayName;
    }
    return id;
  }
}

final modeNameResolverProvider = Provider<ModeNameResolver>((ref) {
  final modes = ref.watch(modesProvider).valueOrNull ?? [];
  return ModeNameResolver(modes);
});
