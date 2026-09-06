import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/tokens.dart';
import '../dashboard/builtin_cards.dart';

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
  String _query = '';
  bool _showAll = false;

  bool get _isManual => widget.config['selection_mode'] == 'manual';

  Set<String> _list(String key) {
    final raw = widget.config[key];
    return raw is List ? raw.whereType<String>().toSet() : <String>{};
  }

  /// Toggling a device, written wherever it belongs.
  ///
  /// In `manual` mode the rule *is* a list, so membership edits `device_ids`
  /// directly — writing an exception against your own list would be a second
  /// way to say the same thing, and an older client would not read it. In every
  /// other mode the rule stays untouched and the change lands in `add` or
  /// `remove`, whichever cancels first.
  void _toggle(DeviceState device, bool wanted) {
    final next = {...widget.config};

    if (_isManual) {
      final ids = _list('device_ids').toList();
      wanted ? ids.add(device.id) : ids.remove(device.id);
      next['device_ids'] = ids;
      widget.onChanged(next);
      return;
    }

    final add = _list('add');
    final remove = _list('remove');
    if (wanted) {
      // Cancel an exclusion before inventing an inclusion, so ticking a device
      // back on leaves the config exactly as it was before you ticked it off.
      if (remove.remove(device.id) == false) add.add(device.id);
    } else {
      if (add.remove(device.id) == false) remove.add(device.id);
    }
    next['add'] = add.toList();
    next['remove'] = remove.toList();
    // An empty exception list is no exception. Keeping `"add": []` on every
    // card would make a document that records every idle tick.
    if (add.isEmpty) next.remove('add');
    if (remove.isEmpty) next.remove('remove');
    widget.onChanged(next);
  }

  /// The order the author arranged, written as the ids in the order they are
  /// drawn.
  ///
  /// **A rule says which devices, never in what order.** So an arrangement is
  /// its own list: the ids as they now stand, which is what `applyOrder` reads
  /// back. Anything the rule matches later and this does not name follows on
  /// the end rather than disturbing what somebody arranged.
  void _reorder(List<DeviceState> shown, int from, int to) {
    final ids = [for (final d in shown) d.id];
    ids.insert(to, ids.removeAt(from));
    widget.onChanged({...widget.config, 'order': ids});
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final all = ref.watch(devicesProvider).value;
    if (all == null) return const SizedBox.shrink();

    // In the order the card draws them — `selectDevicesForConfig` has already
    // applied the arrangement, so this list and the page agree.
    final shownDevices =
        selectDevicesForConfig(all, {...widget.config}..remove('limit'));
    final shown = {for (final d in shownDevices) d.id};
    final add = _list('add');
    final remove = _list('remove');

    // What to offer: everything you have had an opinion about, and — once you
    // ask — the rest of the house, behind a search. 188 rows in front of the
    // answer would bury it.
    //
    // `remove` is in that list for a reason: without it, ticking a device off
    // made it vanish from the panel, so the only way to change your mind was
    // to know the exception existed and go looking for the device by name. An
    // exclusion you cannot see is one you cannot undo.
    final q = _query.toLowerCase();
    final offers = <DeviceState>[
      for (final d in all)
        if (!shown.contains(d.id) && !d.isSystem && d.deviceType != 'scene')
          if (remove.contains(d.id) || _showAll || _query.isNotEmpty)
            if (q.isEmpty ||
                d.displayName.toLowerCase().contains(q) ||
                (d.effectiveArea ?? '').toLowerCase().contains(q))
              d,
    ]..sort((a, b) => a.displayName.compareTo(b.displayName));

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
            _ruleLine(shown.length, add.length, remove.length),
            style: t.text.captionStyle
                .copyWith(color: t.surface.onBaseMuted, height: 1.4),
          ),
          SizedBox(height: t.space.xs),
          if (shownDevices.isNotEmpty)
            Text('Drag to reorder. Cross to take one off.',
                style:
                    t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(height: t.space.xs),
          // **What is on the card, in the order it is drawn.** The panel used
          // to be one alphabetical list of tick-boxes, which could say what a
          // card held and never what came first. John: *"All sections need to
          // be easily arranged like what was done for scenes in the house
          // view."*
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: shownDevices.length,
            onReorderItem: (from, to) => _reorder(shownDevices, from, to),
            itemBuilder: (context, i) {
              final device = shownDevices[i];
              return _MemberRow(
                key: ValueKey(device.id),
                index: i,
                device: device,
                note: add.contains(device.id) ? 'added' : null,
                onRemove: () => _toggle(device, false),
              );
            },
          ),
          SizedBox(height: t.space.sm),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: 'Find a device to add',
              hintStyle:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted),
            ),
          ),
          SizedBox(height: t.space.xs),
          for (final device in offers.take(40))
            _OfferRow(
              device: device,
              note: remove.contains(device.id) ? 'removed' : null,
              onAdd: () => _toggle(device, true),
            ),
          if (!_showAll && _query.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _showAll = true),
                child: const Text('Show every device'),
              ),
            ),
        ],
      ),
    );
  }

  String _ruleLine(int shown, int added, int removed) {
    final mode = widget.config['selection_mode'] as String? ?? 'query';
    final base = switch (mode) {
      'area' =>
        'Everything in ${humanize('${widget.config['area_name'] ?? ''}')}',
      'facet' =>
        'Every ${'${widget.config['facet'] ?? ''}'.replaceAll('_', ' ')} in the house',
      'manual' => 'The devices you picked',
      _ => 'Everything matching the search',
    };
    final parts = [
      if (added > 0) '$added added',
      if (removed > 0) '$removed removed',
    ];
    return parts.isEmpty
        ? '$base — $shown now.'
        : '$base, ${parts.join(' and ')} — $shown now.';
  }
}

/// A device the card is drawing: drag it, or take it off.
class _MemberRow extends StatelessWidget {
  const _MemberRow({
    super.key,
    required this.index,
    required this.device,
    required this.note,
    required this.onRemove,
  });

  final int index;
  final DeviceState device;
  final String? note;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xs / 2),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: EdgeInsets.only(right: t.space.xs),
              child: Icon(Icons.drag_indicator,
                  size: 16, color: t.surface.onBaseMuted),
            ),
          ),
          Expanded(child: _DeviceLine(device: device, on: true)),
          if (note != null)
            Text(note!,
                style: t.text.captionStyle.copyWith(color: t.accent.active)),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            tooltip: 'Take it off this card',
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// A device the card is not drawing, and the one tap that adds it.
class _OfferRow extends StatelessWidget {
  const _OfferRow(
      {required this.device, required this.note, required this.onAdd});

  final DeviceState device;
  final String? note;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return InkWell(
      onTap: onAdd,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: t.space.xs / 2),
        child: Row(
          children: [
            Expanded(child: _DeviceLine(device: device, on: false)),
            if (note != null)
              Text(note!,
                  style: t.text.captionStyle.copyWith(color: t.accent.active)),
            SizedBox(width: t.space.xs),
            Icon(Icons.add, size: 16, color: t.surface.onBaseMuted),
          ],
        ),
      ),
    );
  }
}

/// A name and, under it, the room — which is what tells two of the same name
/// apart.
class _DeviceLine extends StatelessWidget {
  const _DeviceLine({required this.device, required this.on});

  final DeviceState device;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(device.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.text.bodySmallStyle.copyWith(
                color: on ? t.surface.onBase : t.surface.onBaseMuted)),
        if ((device.effectiveArea ?? '').isNotEmpty)
          Text(humanize(device.effectiveArea!),
              style:
                  t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
      ],
    );
  }
}
