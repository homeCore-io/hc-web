import 'package:flutter/material.dart';

import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../devices/device_sheet.dart';

/// The pencil that opens a device's sheet — the one consistent "manage this
/// device" door on cards whose tap is already spent on inline controls (a colour
/// wheel, a thermostat dial, transport). Plain rows just open the sheet on tap,
/// so they only reveal this on hover. The sheet is where name and room are
/// edited, so this is also how you rename a device you reached from Home.
class HomeEditButton extends StatelessWidget {
  const HomeEditButton({super.key, required this.deviceId, this.size = 13});

  final String deviceId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: size + 15, height: size + 15),
      iconSize: size,
      color: t.surface.onBaseMuted,
      tooltip: 'Edit',
      icon: const Icon(HcIcons.pencil),
      onPressed: () => showDeviceSheet(context, deviceId),
    );
  }
}
