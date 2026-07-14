import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/device_state.dart';
import '../../../core/providers/devices_provider.dart';
import '../../../core/providers/modes_provider.dart';
import '../../../core/providers/name_resolver_provider.dart';
import '../../../core/providers/scenes_provider.dart';

/// Everything the editor's pickers need, resolved once and handed down.
///
/// Fetching this per-field would issue a request for every dropdown in a rule
/// with twenty actions.
class RuleRefs {
  const RuleRefs({
    this.devices = const [],
    this.modes = const [],
    this.scenes = const [],
  });

  final List<DeviceState> devices;
  final List<({String id, String name})> modes;
  final List<({String id, String name})> scenes;

  /// What a rule should actually store for a device.
  ///
  /// `canonical_name` (e.g. `living_room.floor_lamp`) survives the device being
  /// replaced; a raw `device_id` does not. `rule_resolver.rs` accepts either, so
  /// we always prefer the canonical form when the device has one.
  String refFor(DeviceState d) =>
      (d.canonicalName?.isNotEmpty ?? false) ? d.canonicalName! : d.id;

  /// Human label for a stored device reference, which may be a canonical name
  /// *or* a raw id depending on when the rule was written.
  String labelFor(String ref) {
    for (final d in devices) {
      if (d.id == ref || d.canonicalName == ref) {
        return d.name?.isNotEmpty ?? false ? d.name! : ref;
      }
    }
    return ref; // a deleted device, or a DELETED: placeholder from core
  }

  bool isKnownDevice(String ref) =>
      devices.any((d) => d.id == ref || d.canonicalName == ref);

  /// The device behind a reference, in either form. A chip needs the whole
  /// device, not just its name, because it renders that device's *live* state.
  DeviceState? deviceFor(String ref) {
    for (final d in devices) {
      if (d.id == ref || d.canonicalName == ref) return d;
    }
    return null;
  }

  /// Attribute names seen on a device, so the attribute field can suggest
  /// rather than demand that the user remember `color_temp`.
  List<String> attributesOf(String ref) {
    for (final d in devices) {
      if (d.id == ref || d.canonicalName == ref) {
        return d.state.keys.toList()..sort();
      }
    }
    return const [];
  }
}

final ruleRefsProvider = Provider<RuleRefs>((ref) {
  final devices = ref.watch(devicesProvider).valueOrNull ?? const [];
  final modes = ref.watch(modesProvider).valueOrNull ?? const [];
  final scenes = ref.watch(scenesProvider).valueOrNull ?? const [];
  // ModeState carries no display name of its own — it lives on the mode's
  // backing device, which is what the resolver reads.
  final modeNames = ref.watch(modeNameResolverProvider);

  return RuleRefs(
    devices: devices,
    modes: [
      for (final m in modes) (id: m.id, name: modeNames.resolve(m.id)),
    ],
    scenes: [
      for (final s in scenes) (id: s.id, name: s.name),
    ],
  );
});
