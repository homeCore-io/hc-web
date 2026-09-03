import 'package:flutter/material.dart';

import '../../core/dashboard/card_style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/design_tools.dart';
import '../../core/dashboard/device_placement.dart';
import '../../core/devices/presentation.dart';
import '../../core/models/dashboard.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/tokens.dart';
import '../devices/device_query.dart';

/// The devices of this house, as things you can put on a page.
///
/// **Rooms and kinds narrow this list. They are not things you drop.** Twice
/// over: *"seems it should be a shortcut for selecting devices in the room or
/// of those kinds not a what it is"*, and then *"it's not intuitive to drop a
/// blob on the page and have to remove items"*. Both are the same complaint,
/// and the previous answer — a container card you could edit afterwards — fixed
/// the wrong half. You should not have to prune something you did not ask for.
///
/// **The device is the data; the rail decides the form.** Hold the icon tool
/// and pick Hob Light and an icon lands, bound to it. Hold the slider and a
/// slider lands on its brightness. See `core/dashboard/device_placement.dart`
/// for the whole rule, which is pure and tested there rather than here.
class DevicesPanel extends ConsumerStatefulWidget {
  const DevicesPanel({super.key, required this.tool, required this.onPick});

  /// What is in your hand, which decides what a pick becomes.
  final DesignTool tool;
  final ValueChanged<DashboardWidgetModel> onPick;

  @override
  ConsumerState<DevicesPanel> createState() => _DevicesPanelState();
}

class _DevicesPanelState extends ConsumerState<DevicesPanel> {
  String _query = '';
  String? _room;
  DeviceFacetGroup? _kind;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final all = ref.watch(devicesProvider).value ?? const <DeviceState>[];

    // Counted over what the OTHER filter has already left, so the numbers on
    // the chips are what you would actually get rather than what the house
    // holds in total. A chip reading 7 that yields 2 is a chip that lies.
    final forRooms = all
        .where((d) =>
            _matchesQuery(d) &&
            (_kind == null || facetGroupOf(facetOf(d)) == _kind))
        .toList();
    final forKinds = all
        .where((d) =>
            _matchesQuery(d) && (_room == null || d.effectiveArea == _room))
        .toList();

    final rooms = <String, int>{};
    for (final d in forRooms) {
      final area = d.effectiveArea;
      if (area != null && area.isNotEmpty) {
        rooms[area] = (rooms[area] ?? 0) + 1;
      }
    }
    final kinds = <DeviceFacetGroup, int>{};
    for (final d in forKinds) {
      final group = facetGroupOf(facetOf(d));
      kinds[group] = (kinds[group] ?? 0) + 1;
    }

    final shown = all.where(_matches).toList()
      ..sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    final roomKeys = rooms.keys.toList()
      ..sort((a, b) => rooms[b]!.compareTo(rooms[a]!));
    final kindKeys = kinds.keys.toList()
      ..sort((a, b) => kinds[b]!.compareTo(kinds[a]!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: t.space.sm),
          child: TextField(
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search devices',
              prefixIcon:
                  Icon(Icons.search, size: 16, color: t.surface.onBaseMuted),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        // The filters, and what they are doing. Both rows are chips rather than
        // a grid of boxes: a box you can drop reads as a thing, and these are
        // not things.
        _Chips(
          label: 'Room',
          chosen: _room,
          options: [for (final r in roomKeys) (key: r, count: rooms[r]!)],
          // The key is `master_bedroom`; the room is Master Bedroom. Core
          // stores the first because it is an identifier, and every surface
          // that shows one to a person runs it through `humanize` — this one
          // was not, so the panel was showing the database.
          labelOf: humanize,
          onPick: (v) => setState(() => _room = v),
        ),
        _Chips(
          label: 'Kind',
          chosen: _kind?.key,
          options: [for (final k in kindKeys) (key: k.key, count: kinds[k]!)],
          labelOf: (key) => DeviceFacetGroup.fromKey(key)?.label ?? key,
          onPick: (v) => setState(
              () => _kind = v == null ? null : DeviceFacetGroup.fromKey(v)),
        ),
        SizedBox(height: t.space.xs),
        // Said, so a pick is never a surprise. The rail and this list are one
        // gesture between them, and the sentence is where that is explained.
        Text(
          _placesAs(),
          style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
        ),
        SizedBox(height: t.space.xs),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(
                    all.isEmpty
                        ? 'No devices yet.'
                        : 'Nothing matches those filters.',
                    style: t.text.captionStyle
                        .copyWith(color: t.surface.onBaseMuted),
                  ),
                )
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, i) => _Draggable(
                    payload: () => _modelFor(shown[i]),
                    label: shown[i].displayName,
                    child: _DeviceRow(
                      device: shown[i],
                      onTap: () => widget.onPick(_modelFor(shown[i])),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// What the held tool will make of whatever you pick.
  String _placesAs() => switch (widget.tool) {
        DesignTool.deviceIcon => 'Picking one places an icon bound to it.',
        DesignTool.toggle => 'Picking one places a switch for it.',
        DesignTool.slider => 'Picking one places a slider for it.',
        DesignTool.stepper => 'Picking one places a stepper for it.',
        DesignTool.gauge =>
          'Picking one places a gauge of one of its readings.',
        DesignTool.text => 'Picking one places one of its readings, as words.',
        _ => 'Picking one places a tile. Hold a tool on the left to place '
            'something else.',
      };

  /// The search matches the device name **or its room**, because "office" is
  /// a thing people type meaning "the things in the office" at least as often
  /// as they mean a device with Office in its name.
  bool _matchesQuery(DeviceState d) =>
      _query.isEmpty ||
      d.displayName.toLowerCase().contains(_query) ||
      (d.effectiveArea ?? '').toLowerCase().contains(_query);

  bool _matches(DeviceState d) {
    if (!_matchesQuery(d)) return false;
    if (_room != null && d.effectiveArea != _room) return false;
    if (_kind != null && facetGroupOf(facetOf(d)) != _kind) return false;
    return true;
  }

  DashboardWidgetModel _modelFor(DeviceState device) {
    final placement = placementFor(widget.tool, device);
    return DashboardWidgetModel(
      id: 'widget_${DateTime.now().microsecondsSinceEpoch}',
      // Named for the device, so the layer tree says which one rather than
      // "Icon" four times over.
      title: device.displayName,
      type: placement.type,
      refreshPolicy: DashboardRefreshPolicy.live,
      config: CardStyle.undecorated.toConfig(placement.config),
    );
  }
}

/// One row of filter chips, with a count each and a way back to all of them.
class _Chips extends StatelessWidget {
  const _Chips({
    required this.label,
    required this.chosen,
    required this.options,
    required this.labelOf,
    required this.onPick,
  });

  final String label;
  final String? chosen;
  final List<({String key, int count})> options;
  final String Function(String) labelOf;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    if (options.isEmpty) return const SizedBox.shrink();
    // **The label is a heading, not the first chip.** Inline it read as one
    // more bubble in the row — "Room" looked like something you could filter
    // by, and the group had no visible start. A heading above says what the
    // row is; a chip beside them says it is one of them.
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: t.space.xs),
            child: Row(children: [
              Text(
                label.toUpperCase(),
                style:
                    t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted),
              ),
              SizedBox(width: t.space.xs),
              Text(
                '${options.length}',
                style: t.text.captionStyle.copyWith(color: t.stroke.hairline),
              ),
              const Spacer(),
              // Only when one is on: a clear that is always there is a control
              // that does nothing most of the time.
              if (chosen != null)
                InkWell(
                  onTap: () => onPick(null),
                  borderRadius: t.radius.smR,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: t.space.xs),
                    child: Text('Clear',
                        style: t.text.captionStyle
                            .copyWith(color: t.accent.active)),
                  ),
                ),
            ]),
          ),
          Wrap(
            spacing: t.space.xs,
            runSpacing: t.space.xs,
            children: [
              for (final option in options)
                _Chip(
                  label: labelOf(option.key),
                  count: option.count,
                  on: option.key == chosen,
                  // Tapping the one that is on turns it off, which is how
                  // every filter chip anywhere works.
                  onTap: () => onPick(option.key == chosen ? null : option.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A filter, and how many it would leave.
///
/// **The count is not part of the name.** Written as one string it read as
/// "Bathroom 2 3" — a room called Bathroom 2 with three devices in it, or a
/// room called Bathroom with twenty-three, and no way to tell. So the number is
/// a separate span in its own colour, set apart by a rule: a name and a count
/// are different kinds of thing and have to look it.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.on,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: t.radius.pillR,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: t.space.sm, vertical: 3),
        decoration: BoxDecoration(
          color: on ? t.accent.active.withValues(alpha: .16) : t.surface.raised,
          border: Border.all(
              color: on
                  ? t.accent.active.withValues(alpha: .5)
                  : t.stroke.hairline),
          borderRadius: t.radius.pillR,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: t.text.captionStyle.copyWith(
                color: on ? t.accent.active : t.surface.onBase,
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: t.space.xs),
              child: SizedBox(
                height: 9,
                child: VerticalDivider(
                  width: t.stroke.width,
                  color: on
                      ? t.accent.active.withValues(alpha: .4)
                      : t.stroke.hairline,
                ),
              ),
            ),
            Text(
              '$count',
              style: t.text.captionStyle.copyWith(
                color: t.surface.onBaseMuted,
                fontFeatures: t.numericFontFeatures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.onTap});

  final DeviceState device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final on = isOn(device);
    return InkWell(
      onTap: onTap,
      borderRadius: t.radius.smR,
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: t.space.xs, vertical: t.space.sm),
        child: Row(children: [
          Icon(
            deviceIcon(device, on: on),
            size: 16,
            color: on ? t.accent.active : t.surface.onBaseMuted,
          ),
          SizedBox(width: t.space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.bodySmallStyle.copyWith(
                    // An unavailable device is still placeable — it will be
                    // back — but it says so rather than looking like the rest.
                    color: device.available
                        ? t.surface.onBase
                        : t.surface.onBaseMuted,
                  ),
                ),
                if ((device.effectiveArea ?? '').isNotEmpty)
                  Text(
                    humanize(device.effectiveArea),
                    overflow: TextOverflow.ellipsis,
                    style: t.text.captionStyle
                        .copyWith(color: t.surface.onBaseMuted),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Picking one up rather than clicking it.
///
/// The floor plan takes a drop, and so does the board — a device dragged onto
/// a plan lands where you dropped it rather than wherever the engine would have
/// put it. That gesture used to come from the catalogue's device rows; it comes
/// from here now, because here is where the devices are.
class _Draggable extends StatelessWidget {
  const _Draggable({
    required this.payload,
    required this.label,
    required this.child,
  });

  final DashboardWidgetModel Function() payload;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return MouseRegion(
      // The only honest way to say "this is draggable" without putting a grip
      // on every row: the cursor changes over something you can pick up.
      cursor: SystemMouseCursors.grab,
      child: Draggable<Object>(
        data: payload(),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: t.space.sm, vertical: t.space.xs),
            decoration: BoxDecoration(
              color: t.surface.overlay,
              borderRadius: t.radius.smR,
              border: Border.all(color: t.accent.active),
            ),
            child: Text(label,
                style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase)),
          ),
        ),
        childWhenDragging: Opacity(opacity: .4, child: child),
        child: child,
      ),
    );
  }
}
