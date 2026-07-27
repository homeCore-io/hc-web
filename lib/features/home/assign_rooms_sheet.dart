import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/text/humanize.dart';
import '../devices/device_query.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../../shell/hc_sheet.dart';

/// Give the room-less devices a room, without leaving the house.
///
/// The "No room" bucket is the largest room in the sandbox house — 64 of 179
/// devices, and it holds every TV and every speaker. A page organised by room
/// cannot place a third of what it is showing, and until now the only cure was
/// opening each device's panel, expanding Details, and typing an area: sixty-four
/// times, four taps each.
///
/// So the bucket gets the one affordance it was missing. The list stays put as
/// you work — a row that has just been assigned shows where it went rather than
/// vanishing, because a list that shortens under the cursor makes you lose your
/// place.
Future<void> showAssignRoomsSheet(
  BuildContext context,
  List<DeviceState> devices,
) =>
    showHcSheet<void>(
      context,
      title: 'Assign rooms',
      child: _AssignRooms(devices: devices),
    );

class _AssignRooms extends ConsumerStatefulWidget {
  const _AssignRooms({required this.devices});

  final List<DeviceState> devices;

  @override
  ConsumerState<_AssignRooms> createState() => _AssignRoomsState();
}

class _AssignRoomsState extends ConsumerState<_AssignRooms> {
  /// What each device was just set to, so the row can confirm instead of
  /// disappearing.
  final _assigned = <String, String>{};
  String? _busy;
  String _search = '';

  /// The rooms this house already has. Offering the existing set is what keeps
  /// "Living Room" and "living room" from becoming two areas.
  List<String> _rooms() {
    final all = ref.read(devicesProvider).valueOrNull ?? const <DeviceState>[];
    final names = <String>{
      for (final d in all)
        if ((d.effectiveArea ?? '').isNotEmpty) humanize(d.effectiveArea!),
      ..._assigned.values,
    };
    return names.toList()..sort();
  }

  Future<void> _assign(DeviceState d, String room) async {
    setState(() => _busy = d.id);
    try {
      await ref
          .read(devicesProvider.notifier)
          .updateDevice(d.id, {'area': room});
      if (mounted) setState(() => _assigned[d.id] = room);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not assign: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final rooms = _rooms();
    final q = _search.trim().toLowerCase();
    final shown = q.isEmpty
        ? widget.devices
        : widget.devices
            .where((d) =>
                d.displayName.toLowerCase().contains(q) ||
                d.pluginId.toLowerCase().contains(q) ||
                (d.deviceType ?? '').toLowerCase().contains(q))
            .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HcSheetHeader(
          title: 'Assign rooms',
          subtitle: _assigned.isEmpty
              ? '${widget.devices.length} devices have no room'
              : '${_assigned.length} assigned · '
                  '${widget.devices.length - _assigned.length} to go',
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(t.space.md, 0, t.space.md, t.space.sm),
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Search devices',
              prefixIcon: Icon(HcIcons.search, size: 15),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(t.space.md, 0, t.space.md, t.space.lg),
            itemCount: shown.length,
            separatorBuilder: (_, __) => SizedBox(height: t.space.xs),
            itemBuilder: (context, i) => _Row(
              device: shown[i],
              rooms: rooms,
              assignedTo: _assigned[shown[i].id],
              busy: _busy == shown[i].id,
              onAssign: (room) => _assign(shown[i], room),
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.device,
    required this.rooms,
    required this.onAssign,
    this.assignedTo,
    this.busy = false,
  });

  final DeviceState device;
  final List<String> rooms;
  final ValueChanged<String> onAssign;
  final String? assignedTo;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final facet = facetOf(device, device.schema);
    final done = assignedTo != null;

    return Container(
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        color: t.surface.raised,
        borderRadius: t.radius.mdR,
        border: Border.all(
          color: done
              ? t.accent.success.withValues(alpha: 0.4)
              : t.stroke.hairline,
        ),
      ),
      child: Row(
        children: [
          Icon(HcIcons.forFacet(facet), size: 17, color: t.surface.onBaseMuted),
          SizedBox(width: t.space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: t.surface.onBase),
                ),
                Text(
                  // What it is, so an unhelpful name like "Device 001" is still
                  // placeable — which is most of why these are unassigned.
                  '${facet.label} · '
                  '${humanize(device.pluginId.replaceFirst('plugin.', ''))}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 11.5, color: t.surface.onBaseMuted),
                ),
              ],
            ),
          ),
          SizedBox(width: t.space.sm),
          if (busy)
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
          else if (done)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_rounded, size: 15, color: t.accent.success),
                SizedBox(width: t.space.xs),
                Text(assignedTo!,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: t.accent.success)),
              ],
            )
          else
            _RoomPicker(rooms: rooms, onPick: onAssign),
        ],
      ),
    );
  }
}

/// Pick an existing room, or type a new one. Existing rooms lead, because
/// almost every unassigned device belongs in a room the house already has.
class _RoomPicker extends StatelessWidget {
  const _RoomPicker({required this.rooms, required this.onPick});

  final List<String> rooms;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Set room',
      position: PopupMenuPosition.under,
      onSelected: (v) async {
        if (v != _kNew) {
          onPick(v);
          return;
        }
        final name = await showDialog<String>(
          context: context,
          builder: (_) => const _NewRoomDialog(),
        );
        if (name != null && name.trim().isNotEmpty) onPick(name.trim());
      },
      itemBuilder: (_) => [
        for (final r in rooms) PopupMenuItem(value: r, child: Text(r)),
        if (rooms.isNotEmpty) const PopupMenuDivider(),
        const PopupMenuItem(value: _kNew, child: Text('New room…')),
      ],
      child: Container(
        padding:
            EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
        decoration: BoxDecoration(
          color: t.surface.sunken,
          borderRadius: BorderRadius.circular(t.radius.pill),
          border: Border.all(color: t.stroke.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Set room',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: t.accent.primary)),
            SizedBox(width: t.space.xs),
            Icon(HcIcons.caretDown, size: 10, color: t.accent.primary),
          ],
        ),
      ),
    );
  }
}

const _kNew = ' new';

class _NewRoomDialog extends StatefulWidget {
  const _NewRoomDialog();

  @override
  State<_NewRoomDialog> createState() => _NewRoomDialogState();
}

class _NewRoomDialogState extends State<_NewRoomDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New room'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Kitchen'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
