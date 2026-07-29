import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../shared/widgets/section_scaffold.dart';
import 'device_sheet.dart';

/// The device panel as a full page — reached by deep link, the command palette,
/// or the compact table. It renders the very same [DevicePanel] the sheet shows,
/// so there is one device UI, not two, and no Material detail page behind it.
class DeviceDetailPage extends ConsumerWidget {
  const DeviceDetailPage({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices =
        ref.watch(devicesProvider).valueOrNull ?? const <DeviceState>[];
    final device =
        devices.where((d) => d.id == deviceId).cast<DeviceState?>().firstOrNull;

    return SectionScaffold(
      title: device?.displayName ?? 'Device',
      onBack: () => context.canPop() ? context.pop() : context.go('/devices'),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: DevicePanel(deviceId: deviceId, showClose: false),
        ),
      ),
    );
  }
}
