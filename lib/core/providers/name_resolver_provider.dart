import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/device_state.dart';
import '../models/mode_state.dart';
import 'devices_provider.dart';
import 'modes_provider.dart';

// ─── Device name resolver ─────────────────────────────────────────────────────

class DeviceNameResolver {
  final List<DeviceState> devices;
  final Map<String, int> _nameCounts;

  DeviceNameResolver(this.devices)
      : _nameCounts = {
          for (final device in devices)
            if (device.name != null && device.name!.isNotEmpty)
              device.name!: devices
                  .where((candidate) => candidate.name == device.name)
                  .length,
        };

  DeviceState? lookup(String ref) {
    if (ref.isEmpty) return null;

    for (final d in devices) {
      if (d.ruleReference == ref) return d;
      if (d.canonicalName == ref) return d;
      if (d.id == ref) return d;
    }

    for (final d in devices) {
      final name = d.name;
      if (name == ref && _nameCounts[name] == 1) return d;
    }

    return null;
  }

  String resolve(String id) {
    if (id.isEmpty) return id;
    return lookup(id)?.displayName ?? id;
  }

  String preferredRuleRef(String ref) {
    if (ref.isEmpty) return ref;
    return lookup(ref)?.ruleReference ?? ref;
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
