import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/room_sections.dart';
import '../../core/models/dashboard.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/components/hc_tile.dart';
import '../../design/tokens.dart';
import '../devices/device_sheet.dart';
import '../../core/devices/presentation.dart' show isOn;
import 'builtin_cards.dart' show selectDevicesForConfig;

/// The house, by room — **one element that draws many sections**.
///
/// Every other element is one you place. You choose it, you put it somewhere,
/// and it draws what you told it to. That is why a designed page could not look
/// like the house's own home page: the home page has a section per room and
/// fills each from the house, so a light installed in the kitchen appears by
/// itself. Reproducing that by hand meant a card per room, and the page was
/// wrong the moment a room changed.
///
/// This is told what to *ask* rather than what to draw. Which rooms, and what
/// counts as being in one — then a section for each answer. Add a room and a
/// section arrives; add a device and it lands in its room; nobody opens the
/// designer.
///
/// It draws the same [HcTile] the device grid draws, on purpose. A second kind
/// of device tile that behaved slightly differently would be the more expensive
/// mistake by far — this is a new way to *choose* what is on a page, not a new
/// way to render a device.
class RoomsCard extends ConsumerWidget {
  const RoomsCard({super.key, required this.widgetModel, this.compact = false});

  final DashboardWidgetModel widgetModel;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final async = ref.watch(devicesProvider);
    // "No rooms" is a claim about the house and it is false while the house is
    // still arriving — the same rule every other card follows.
    if (async.value == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final config = widgetModel.config;
    // Computed ONCE, not per device: `keep` is called for every device in the
    // house, and rebuilding the whole selection inside it made this quadratic
    // on a house with a couple of hundred things in it.
    final kept = _kept(async.value!, config);
    final sections = roomSections(
      devices: async.value!,
      choice: roomChoiceFrom(config['rooms_mode']),
      rooms: _strings(config['rooms']),
      order: _strings(config['room_order']),
      // The per-room filter goes through the app's ONE answer to "which
      // devices does this config mean". Re-deriving it here is how a card ends
      // up selecting a different set than its own preview.
      keep: (d) => kept.contains(d.id),
      hideEmpty: config['hide_empty'] != false,
    );

    if (sections.isEmpty) {
      return Center(
        child: Text(
          'No rooms match. Devices need an area before they can be grouped '
          'into one.',
          textAlign: TextAlign.center,
          style: t.text.captionStyle
              .copyWith(color: t.surface.onBaseMuted, height: 1.4),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / (compact ? 160.0 : 180.0))
            .floor()
            .clamp(1, 4);
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sections.length,
          separatorBuilder: (_, __) => SizedBox(height: t.space.md),
          itemBuilder: (context, i) => _Section(
            section: sections[i],
            columns: columns,
            compact: compact,
          ),
        );
      },
    );
  }

  /// The ids this element's device filter keeps.
  ///
  /// Goes through the app's ONE answer to "which devices does this config
  /// mean" — [selectDevicesForConfig] stays the only thing that reads
  /// `selection_mode`, so this element and its own preview cannot disagree.
  Set<String> _kept(List<DeviceState> all, Map<String, dynamic> config) {
    // No filter named means "everything in the room", which is what the home
    // page does and what anybody would expect of an element called Rooms.
    if (config['selection_mode'] == null) {
      return {
        for (final d in all)
          if (!d.isSystem && d.deviceType != 'scene') d.id,
      };
    }
    return {for (final d in selectDevicesForConfig(all, config)) d.id};
  }

  static List<String> _strings(Object? raw) =>
      (raw as List?)?.whereType<String>().toList() ?? const [];
}

class _Section extends ConsumerWidget {
  const _Section({
    required this.section,
    required this.columns,
    required this.compact,
  });

  final RoomSection section;
  final int columns;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final notifier = ref.read(devicesProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: t.space.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  section.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.subtitleStyle.copyWith(
                    color: t.surface.onBase,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // The count, not a state summary. What is on in a room is the
              // room's own business and the tiles already say it; the count is
              // what tells you the section is complete.
              Text(
                '${section.devices.length}',
                style: t.text.captionStyle.copyWith(
                  color: t.surface.onBaseMuted,
                  fontFeatures: t.numericFontFeatures,
                ),
              ),
            ],
          ),
        ),
        if (section.devices.isEmpty)
          Text(
            'Nothing here yet.',
            style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: section.devices.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: compact ? 1.9 : 1.7,
            ),
            itemBuilder: (context, i) {
              final device = section.devices[i];
              return HcTile(
                device: device,
                onTap: () => showDeviceSheet(context, device.id),
                onToggle: device.isMediaPlayer
                    ? null
                    : () => notifier.command(device.id, {'on': !isOn(device)}),
                onLevel: device.isMediaPlayer
                    ? null
                    : (v) => notifier.command(
                        device.id, {'brightness_pct': (v * 100).round()}),
              );
            },
          ),
      ],
    );
  }
}
