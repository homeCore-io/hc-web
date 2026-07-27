import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/components/hc_scene_chip.dart';
import '../../design/tokens.dart';

/// The scenes this light can be put into.
///
/// A Hue scene is not a property of the bridge, it is a property of a *room* —
/// "Tropical twilight" means something only for the lights in the Office. So the
/// lights in that room are exactly where you would reach for it, and until now
/// the only place to find one was the Scenes page, several taps away from the
/// bulb you were looking at.
///
/// Deliberately Hue-only, and deliberately matched on bridge as well as room.
/// A Lutron scene is a whole-house preset that happens to carry an area, so
/// listing it under one bulb would promise something it does not do; and a house
/// with two bridges must not offer one bridge's scenes to the other's lights.
class DeviceScenesBlock extends ConsumerWidget {
  const DeviceScenesBlock({super.key, required this.device});

  final DeviceState device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final scenes = scenesForDevice(
      device,
      ref.watch(devicesProvider).valueOrNull ?? const [],
    );
    if (scenes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SCENES IN THIS ROOM',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: t.surface.onBaseMuted,
          ),
        ),
        SizedBox(height: t.space.sm),
        Wrap(
          spacing: t.space.sm,
          runSpacing: t.space.sm,
          children: [
            for (final s in scenes)
              HcSceneChip(
                name: s.displayName,
                // A bridge scene is run-only: homeCore does not own it, so a
                // pencil here would open nothing.
                onRun: () => ref
                    .read(devicesProvider.notifier)
                    .command(s.id, {'action': 'activate_scene'}),
              ),
          ],
        ),
        SizedBox(height: t.space.md),
      ],
    );
  }
}

/// The Hue scenes that belong to the same bridge and room as [device].
///
/// Returns empty for anything that is not a Hue light, which is most of the
/// house — the match is on `bridge_id`, so a device without one can never
/// accidentally collect another integration's scenes.
List<DeviceState> scenesForDevice(DeviceState device, List<DeviceState> all) {
  final bridge = device.state['bridge_id'];
  final area = device.effectiveArea;
  if (bridge is! String || bridge.isEmpty) return const [];
  if (area == null || area.isEmpty) return const [];

  final facet = facetOf(device, device.schema);
  const lights = {
    DeviceFacet.light,
    DeviceFacet.dimmableLight,
    DeviceFacet.colorLight,
  };
  if (!lights.contains(facet)) return const [];

  final out = [
    for (final d in all)
      if (facetOf(d, d.schema) == DeviceFacet.scene &&
          d.state['bridge_id'] == bridge &&
          d.effectiveArea == area)
        d,
  ]..sort((a, b) => a.displayName.compareTo(b.displayName));
  return out;
}
