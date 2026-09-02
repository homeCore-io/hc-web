import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dashboard/treemap.dart';
import '../../core/devices/scene_state.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/tokens.dart';

/// Every room of the house at once, sized by what is in it and lit by what is
/// on.
///
/// **This is the element a card grid could not be.** A row of room cards says
/// the house has fifteen rooms; it cannot say that the Living Room and the
/// Office hold a third of it between them and the Hallway holds two devices.
/// Area is the device count, so the shape of the house is the data rather than
/// a drawing somebody has to keep true — which is the thing a floor plan can
/// never promise.
///
/// **The glow is one binding, repeated**: the lights that are on in that room,
/// as fill. A room with no lights stays dark rather than being drawn as though
/// its lights were off, because those are different facts.
///
/// Tapping a room opens a page. Which page is the author's choice and is the
/// same for every room — a house has one room page, not fifteen — so the room
/// travels as a query rather than as fifteen separate links.
class RoomFieldElement extends ConsumerWidget {
  const RoomFieldElement({super.key, required this.config});

  final Map<String, dynamic> config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value;
    if (devices == null) {
      return Center(
        child: Text('Reading the house…',
            style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
      );
    }

    final rooms = roomsOf(devices);
    if (rooms.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(t.space.md),
          child: Text(
            'No devices are in a room yet. Assign them in Manage and they '
            'will show up here.',
            textAlign: TextAlign.center,
            style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
          ),
        ),
      );
    }

    final page = (config['room_page'] as String? ?? '').trim();
    final gap = (config['gap'] as num?)?.toDouble() ?? 4;

    return LayoutBuilder(builder: (context, box) {
      final cells = squarify(
        [for (final r in rooms) (key: r.area, value: r.total.toDouble())],
        box.maxWidth,
        box.maxHeight,
      );
      final byArea = {for (final r in rooms) r.area: r};
      return Stack(
        children: [
          for (final cell in cells)
            Positioned(
              left: cell.x + gap / 2,
              top: cell.y + gap / 2,
              width: (cell.w - gap).clamp(0.0, double.infinity),
              height: (cell.h - gap).clamp(0.0, double.infinity),
              child: _Cell(
                room: byArea[cell.key]!,
                // Below roughly a button's worth of space there is no room for
                // the count, and a truncated one reads as a different number.
                compact: cell.w < 150 || cell.h < 84,
                onTap: page.isEmpty
                    ? null
                    : () => context.go('/dashboards/$page?room=${cell.key}'),
              ),
            ),
        ],
      );
    });
  }
}

/// One room, as this element counts it.
typedef RoomTally = ({String area, int total, int lights, int on});

/// The rooms of a house, largest first.
///
/// Devices with no room are left out entirely rather than gathered into an
/// "Unassigned" block: they are real and they are nowhere, and a rectangle
/// implying they share a room would be inventing one.
List<RoomTally> roomsOf(List<DeviceState> devices) {
  final byArea = <String, List<DeviceState>>{};
  for (final d in devices) {
    final area = d.effectiveArea;
    if (area == null || area.isEmpty) continue;
    byArea.putIfAbsent(area, () => []).add(d);
  }
  final out = <RoomTally>[
    for (final entry in byArea.entries)
      (
        area: entry.key,
        total: entry.value.length,
        lights: entry.value.where(_isLight).length,
        on: entry.value
            .where((d) => _isLight(d) && d.state['on'] == true)
            .length,
      ),
  ]..sort((a, b) => b.total.compareTo(a.total));
  return out;
}

bool _isLight(DeviceState d) => d.deviceType == 'light' && !isSceneDevice(d);

class _Cell extends StatelessWidget {
  const _Cell({required this.room, required this.compact, required this.onTap});

  final RoomTally room;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    // 0 when the room has no lights at all — not the same as having them off.
    final lit = room.lights == 0 ? 0.0 : room.on / room.lights;

    return Semantics(
      button: onTap != null,
      label: '${humanize(room.area)}, ${room.total} devices'
          '${room.lights == 0 ? '' : ', ${room.on} of ${room.lights} lights on'}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: t.radius.smR,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? t.space.xs : t.space.sm,
              vertical: compact ? t.space.xs : t.space.sm,
            ),
            decoration: BoxDecoration(
              color: t.surface.raised,
              border: Border.all(color: t.stroke.hairline),
              borderRadius: t.radius.smR,
              gradient: lit == 0
                  ? null
                  : RadialGradient(
                      center: Alignment.bottomCenter,
                      radius: 1.1,
                      colors: [
                        t.accent.active.withValues(alpha: 0.10 + 0.5 * lit),
                        t.accent.active.withValues(alpha: 0),
                      ],
                    ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    humanize(room.area),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (compact ? t.text.captionStyle : t.text.bodySmallStyle)
                            .copyWith(color: t.surface.onBase),
                  ),
                ),
                if (!compact)
                  Text(
                    room.lights == 0
                        ? '${room.total} devices'
                        : '${room.on}/${room.lights} lit · ${room.total}',
                    overflow: TextOverflow.ellipsis,
                    style: t.text.captionStyle.copyWith(
                      color:
                          room.on > 0 ? t.accent.active : t.surface.onBaseMuted,
                      fontFeatures: t.numericFontFeatures,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
