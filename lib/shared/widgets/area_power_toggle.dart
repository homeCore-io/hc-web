import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/tokens.dart';

/// The room on/off pill in a group header — turns every actuator in the area
/// on or off at once. Shows nothing when the area has no controllable device
/// (a header button that does nothing is worse than no button), so a group of
/// pure sensors or source-only scenes simply omits it.
class AreaPowerToggle extends ConsumerWidget {
  const AreaPowerToggle({super.key, required this.devices});

  /// Every device in the area (the toggle picks out the actuators itself).
  final List<DeviceState> devices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final actuators = devices
        .where((d) => d.available && facetOf(d, d.schema).isActuator)
        .toList();
    if (actuators.isEmpty) return const SizedBox.shrink();

    final anyOn = actuators.any(isOn);

    void set(bool on) {
      final n = ref.read(devicesProvider.notifier);
      for (final d in actuators) {
        if (isOn(d) != on) n.command(d.id, {'on': on});
      }
    }

    return GestureDetector(
      onTap: () => set(!anyOn),
      child: AnimatedContainer(
        duration: t.motion.fast,
        width: 38,
        height: 22,
        decoration: BoxDecoration(
          color: anyOn
              ? t.accent.active.withValues(alpha: 0.3)
              : t.surface.overlay,
          borderRadius: t.radius.pillR,
          border:
              Border.all(color: anyOn ? Colors.transparent : t.stroke.hairline),
        ),
        child: AnimatedAlign(
          duration: t.motion.fast,
          alignment: anyOn ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: anyOn ? t.accent.active : t.surface.onBaseMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
