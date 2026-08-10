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

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final all = ref.watch(devicesProvider).value;
    if (all == null) return const SizedBox.shrink();

    final shown = {
      for (final d
          in selectDevicesForConfig(all, {...widget.config}..remove('limit')))
        d.id,
    };
    final add = _list('add');
    final remove = _list('remove');

    // Candidates: what the card holds, everything you have had an opinion
    // about, and — once you ask — the rest of the house, filtered by the
    // search. The full house sits behind a search rather than in front of it,
    // because 188 rows would bury the answer.
    //
    // `remove` is in that list for a reason: without it, ticking a device off
    // made it vanish from the panel, so the only way to change your mind was
    // to know the exception existed and go looking for the device by name. An
    // exclusion you cannot see is one you cannot undo.
    final mentioned = {...add, ...remove};
    final candidates = <DeviceState>[
      for (final d in all)
        if (!d.isSystem && d.deviceType != 'scene')
          if (shown.contains(d.id) ||
              mentioned.contains(d.id) ||
              _showAll ||
              _query.isNotEmpty)
            d,
    ]..sort((a, b) {
        final inA = shown.contains(a.id) ? 0 : 1;
        final inB = shown.contains(b.id) ? 0 : 1;
        return inA == inB ? a.displayName.compareTo(b.displayName) : inA - inB;
      });

    final matching = candidates
        .where((d) =>
            _query.isEmpty ||
            d.displayName.toLowerCase().contains(_query.toLowerCase()) ||
            (d.effectiveArea ?? '')
                .toLowerCase()
                .contains(_query.toLowerCase()))
        .toList();

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
          // The rule, in words, so it stays visible rather than dissolving into
          // the list it produced.
          Text(
            _ruleLine(shown.length, add.length, remove.length),
            style: t.text.captionStyle
                .copyWith(color: t.surface.onBaseMuted, height: 1.4),
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
          for (final device in matching.take(40))
            _MemberRow(
              device: device,
              checked: shown.contains(device.id),
              // Why it is in, or out, when the rule alone does not explain it.
              note: add.contains(device.id)
                  ? 'added'
                  : remove.contains(device.id)
                      ? 'removed'
                      : null,
              onChanged: (v) => _toggle(device, v),
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

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.device,
    required this.checked,
    required this.note,
    required this.onChanged,
  });

  final DeviceState device;
  final bool checked;
  final String? note;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return InkWell(
      onTap: () => onChanged(!checked),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: t.space.xs / 2),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Checkbox(
                value: checked,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => onChanged(v ?? false),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.text.bodySmallStyle.copyWith(
                          color: checked
                              ? t.surface.onBase
                              : t.surface.onBaseMuted)),
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
      ),
    );
  }
}
