import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dashboard/room_scope.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/page_room_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/tokens.dart';
import '../dashboard/builtin_cards.dart';
import 'widget_config_form.dart';

/// The devices a card holds, listed and tickable.
///
/// John, reviewing the live page: *"I don't understand the 'kind' and 'room' on
/// the left panel of just throwing a container of devices out, seems it should
/// be a shortcut for selecting devices in the room or of those kinds not a what
/// it is"* and *"no way to edit the contents in the container or in the lists.
/// I want to be able to choose the devices and remove/add to the groups."*
///
/// Both are the same gap. A room card stored `selection_mode: area` — a live
/// query, which is the right default because a new lamp should appear without
/// editing the page — but it was **opaque**: nothing showed which devices it
/// held, and nothing could change them. So the rule looked like a fixed list
/// you were not allowed to touch, which is the worst of both.
///
/// This makes the rule visible and gives it exceptions. What you tick is what
/// the card shows; the rule keeps working underneath for everything you have
/// not had an opinion about.
class CardMembers extends ConsumerStatefulWidget {
  const CardMembers({
    super.key,
    required this.config,
    required this.onChanged,
  });

  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  ConsumerState<CardMembers> createState() => _CardMembersState();
}

class _CardMembersState extends ConsumerState<CardMembers> {
  bool get _isManual => widget.config['selection_mode'] == 'manual';

  Set<String> _list(String key) {
    final raw = widget.config[key];
    return raw is List ? raw.whereType<String>().toSet() : <String>{};
  }

  /// What the sheet chose, written back as the rule plus its exceptions.
  ///
  /// **The rule stays a live query.** A new lamp in the room should appear
  /// without editing the page, so the answer is not frozen into a list: what
  /// somebody added that the rule did not choose becomes `add`, what they took
  /// off that it did becomes `remove`, and the order they put them in becomes
  /// `order`. In manual mode the rule already *is* a list, so it is written
  /// directly — an exception against your own list would be a second way to
  /// say the same thing.
  void _write(List<String> picked, List<DeviceState> all,
      Map<String, dynamic> resolved) {
    final next = {...widget.config};

    if (picked.isEmpty) {
      // Back to the rule alone, which is what the sheet's third button means.
      next
        ..remove('add')
        ..remove('remove')
        ..remove('order');
      widget.onChanged(next);
      return;
    }

    if (_isManual) {
      widget.onChanged(next..['device_ids'] = picked);
      return;
    }

    // What the rule alone would have chosen, so an exception is only written
    // where somebody actually disagreed with it.
    final rule = {
      for (final d in selectDevicesForConfig(
          all,
          {...resolved}
            ..remove('limit')
            ..remove('add')
            ..remove('remove')))
        d.id,
    };
    final add = [
      for (final id in picked)
        if (!rule.contains(id)) id
    ];
    final remove = [
      for (final id in rule)
        if (!picked.contains(id)) id
    ];

    next['order'] = picked;
    add.isEmpty ? next.remove('add') : next['add'] = add;
    remove.isEmpty ? next.remove('remove') : next['remove'] = remove;
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final all = ref.watch(devicesProvider).value;
    if (all == null) return const SizedBox.shrink();

    // **`@room` means a room here too.** The panel asked the selection what
    // the card holds and handed it the page's own notation, so on a room page
    // every list said "0 now" while the page beside it drew six devices.
    final resolved = resolveRoomRefs(
      widget.config,
      room: ref.watch(pageRoomProvider),
      devices: all,
    );

    // In the order the card draws them — `selectDevicesForConfig` has already
    // applied the arrangement, so this list and the page agree.
    final shownDevices =
        selectDevicesForConfig(all, {...resolved}..remove('limit'));
    final shown = [for (final d in shownDevices) d.id];
    final add = _list('add');
    final remove = _list('remove');

    return Padding(
      padding: EdgeInsets.only(top: t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('DEVICES',
                    style: t.text.overlineStyle
                        .copyWith(color: t.surface.onBaseMuted)),
              ),
              Text('${shown.length}',
                  style: t.text.captionStyle.copyWith(
                      color: t.surface.onBaseMuted,
                      fontFeatures: t.numericFontFeatures)),
            ],
          ),
          SizedBox(height: t.space.xs),
          // The rule, in words, so it stays visible rather than dissolving
          // into the list it produced.
          Text(
            _ruleLine(resolved, shown.length, add.length, remove.length),
            style: t.text.captionStyle
                .copyWith(color: t.surface.onBaseMuted, height: 1.4),
          ),
          SizedBox(height: t.space.sm),
          // **The same sheet the scenes go through.** This was an inline list
          // of its own — a second way of asking one question, in one panel.
          // John: *"This is no way matches the way scenes are selected from
          // the 'every room' starting page editor."*
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await pickAndOrder(
                context,
                title: 'Pick devices',
                all: [
                  for (final d in all)
                    if (!d.isSystem && d.deviceType != 'scene')
                      (
                        id: d.id,
                        name: d.displayName,
                        where: (d.effectiveArea ?? '').isEmpty
                            ? 'No room'
                            : humanize(d.effectiveArea!)
                      ),
                ],
                selected: shown,
                addHint: 'Add a device',
                clearLabel: 'Back to the rule',
              );
              if (picked != null) _write(picked, all, resolved);
            },
            icon: const Icon(Icons.tune, size: 15),
            label: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                shown.isEmpty
                    ? 'Choose devices…'
                    : 'Choose and arrange — ${shown.length}',
                style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
              ),
            ),
          ),
          SizedBox(height: t.space.xs),
          // What it holds, in the order it draws them, so the panel answers
          // without opening anything.
          for (final device in shownDevices.take(12))
            _DeviceLine(
                device: device, note: add.contains(device.id) ? 'added' : null),
          if (shownDevices.length > 12)
            Text('and ${shownDevices.length - 12} more',
                style:
                    t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
        ],
      ),
    );
  }

  String _ruleLine(
      Map<String, dynamic> config, int shown, int added, int removed) {
    final mode = config['selection_mode'] as String? ?? 'query';
    final base = switch (mode) {
      'area' => 'Everything in ${humanize('${config['area_name'] ?? ''}')}',
      'facet' =>
        'Every ${'${config['facet'] ?? ''}'.replaceAll('_', ' ')} in the house',
      'manual' => 'The devices you picked',
      _ => 'Everything matching the search',
    };
    // The room as it reads, not as the page writes it.

    final parts = [
      if (added > 0) '$added added',
      if (removed > 0) '$removed removed',
    ];
    return parts.isEmpty
        ? '$base — $shown now.'
        : '$base, ${parts.join(' and ')} — $shown now.';
  }
}

/// A device the card draws: its name, its room, and why it is there when the
/// rule alone does not say.
class _DeviceLine extends StatelessWidget {
  const _DeviceLine({required this.device, this.note});

  final DeviceState device;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xs / 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.text.bodySmallStyle
                        .copyWith(color: t.surface.onBase)),
                if ((device.effectiveArea ?? '').isNotEmpty)
                  Text(humanize(device.effectiveArea!),
                      style: t.text.captionStyle
                          .copyWith(color: t.surface.onBaseMuted)),
              ],
            ),
          ),
          if (note != null)
            Text(note!,
                style: t.text.captionStyle.copyWith(color: t.accent.active)),
        ],
      ),
    );
  }
}
