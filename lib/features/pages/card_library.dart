import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/dashboard.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/devices/presentation.dart';
import '../../core/text/humanize.dart';
import '../../design/tokens.dart';

/// What you can put on a page, drawn from the house you are putting it on.
///
/// Step 6 of `dashboard-authoring-plan.md`, and the point at which the editor
/// stops being a config panel. The palette it replaces was thirteen near
/// identical rows — twelve of them a bare noun, three of them the same idea in
/// three renderers — and it was **byte-identical on a homeCore with no
/// devices**. It could not have told you your house has a living room.
///
/// This one is a view of the device map: *Living room · 31 devices · 6 on*.
/// Picking a room places a card for that room, configured and titled, with no
/// form in between. Two houses see two different libraries, which is the whole
/// argument.
///
/// **No filter chips yet, deliberately.** `/devices` offers Lights 22, Sensors
/// 55, Low battery 2, and they are computed from each device's *facet* — a
/// schema-derived idea. The stored card format has three selection modes,
/// `manual | area | query`, and none can express "every light": a query for
/// `light` matches 17 of this house's 22, because a colour bulb's type is not
/// the word light. Offering a chip labelled 22 that places a card showing 17
/// would be precisely the silent wrongness this arc has been removing. They
/// arrive with a selection mode that can hold them.
class CardLibrary extends ConsumerStatefulWidget {
  const CardLibrary({super.key, required this.onPick});

  /// A ready-to-place card. The page decides where it lands.
  final ValueChanged<DashboardWidgetModel> onPick;

  @override
  ConsumerState<CardLibrary> createState() => _CardLibraryState();
}

class _CardLibraryState extends ConsumerState<CardLibrary> {
  String _query = '';

  /// Rooms with something in them, most-populated first.
  ///
  /// Derived from the devices themselves rather than from `GET /areas`: the
  /// area catalog is empty on a fresh house, and a room derived from a device
  /// is guaranteed to select at least that device. The same reasoning the
  /// config form's area list already uses.
  List<_Room> _rooms(List<DeviceState> devices) {
    final byArea = <String, List<DeviceState>>{};
    for (final d in devices) {
      if (d.isSystem || d.deviceType == 'scene') continue;
      final area = d.effectiveArea;
      if (area == null || area.isEmpty) continue;
      byArea.putIfAbsent(area, () => []).add(d);
    }
    final rooms = [
      for (final entry in byArea.entries)
        _Room(
          area: entry.key,
          label: humanize(entry.key),
          total: entry.value.length,
          on: entry.value.where(isOn).length,
        ),
    ]..sort((a, b) => b.total.compareTo(a.total));
    return rooms;
  }

  bool _matches(String label) =>
      _query.isEmpty || label.toLowerCase().contains(_query.toLowerCase());

  DashboardWidgetModel _model({
    required String type,
    required String title,
    required Map<String, dynamic> config,
  }) =>
      DashboardWidgetModel(
        id: 'widget_${DateTime.now().microsecondsSinceEpoch}',
        type: type,
        title: title,
        refreshPolicy: DashboardRefreshPolicy.live,
        config: config,
      );

  void _placeRoom(_Room room) => widget.onPick(_model(
        type: 'device_grid',
        // Titled with the room, because that is what the user picked. A card
        // called "Device grid" would be naming its renderer at them.
        title: room.label,
        config: {
          'selection_mode': 'area',
          'area_name': room.area,
          'show_offline': true,
          'limit': 12,
        },
      ));

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value;
    final rooms = devices == null ? const <_Room>[] : _rooms(devices);
    final shownRooms = rooms.where((r) => _matches(r.label)).toList();

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: t.surface.raised,
        borderRadius: BorderRadius.circular(t.radius.md),
        border: Border.all(color: t.stroke.hairline, width: t.stroke.width),
      ),
      padding: EdgeInsets.all(t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add to this page',
              style: t.text.subtitleStyle.copyWith(
                  color: t.surface.onBase, fontWeight: FontWeight.w600)),
          SizedBox(height: t.space.sm),
          _Search(onChanged: (v) => setState(() => _query = v)),
          SizedBox(height: t.space.md),
          Expanded(
            child: ListView(
              children: [
                if (devices == null)
                  Text('Loading the house…',
                      style: t.text.captionStyle
                          .copyWith(color: t.surface.onBaseMuted))
                else ...[
                  if (shownRooms.isNotEmpty) ...[
                    const _Heading(label: 'Rooms'),
                    for (final room in shownRooms)
                      _RoomRow(room: room, onTap: () => _placeRoom(room)),
                    SizedBox(height: t.space.md),
                  ] else if (_query.isEmpty && rooms.isEmpty)
                    Padding(
                      padding: EdgeInsets.only(bottom: t.space.md),
                      child: Text(
                        'No rooms yet. Assign devices to rooms in Manage and '
                        'they will show up here.',
                        style: t.text.captionStyle.copyWith(
                            color: t.surface.onBaseMuted, height: 1.4),
                      ),
                    ),
                ],
                for (final group in _groups)
                  if (group.entries.any((e) => _matches(e.label))) ...[
                    _Heading(label: group.label),
                    for (final entry in group.entries)
                      if (_matches(entry.label))
                        _PlainRow(
                          label: entry.label,
                          hint: entry.hint,
                          onTap: () => widget.onPick(_model(
                            type: entry.type,
                            title: entry.label,
                            config: entry.config,
                          )),
                        ),
                    SizedBox(height: t.space.md),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Everything that is not a room, grouped by what it is for rather than by
  /// which renderer draws it.
  static const _groups = <_Group>[
    _Group('Devices', [
      _Entry('Pick devices by hand', 'device_tile', 'choose them yourself',
          {'selection_mode': 'manual', 'device_ids': <String>[]}),
    ]),
    _Group('The house', [
      _Entry(
          'At a glance', 'house_status_hero', 'lights, climate, security', {}),
      _Entry('Activity', 'event_feed', 'what just happened',
          {'limit': 20, 'group_by': 'none'}),
      _Entry('Modes', 'mode_chips', 'day, night, away', {}),
      _Entry('Scenes', 'scene_row', 'one tap each', {}),
      _Entry('Now playing', 'media_player', 'speakers and TVs',
          {'selection_mode': 'query', 'query': '', 'limit': 4}),
    ]),
    _Group('Other', [
      _Entry('Camera', 'camera_video', 'a live view',
          {'source_type': 'image_refresh'}),
      _Entry('Chart', 'history_chart', 'a value over time',
          {'timeframe_hours': 24}),
      _Entry('Web page', 'web_embed', 'anything with a URL',
          {'sandbox_profile': 'readonly_embed'}),
      _Entry('Note', 'markdown', 'text you write',
          {'markdown': '# Note\nWrite something here.'}),
      _Entry('Numbers', 'stat_summary', 'counts of things', {
        'metrics': ['devices', 'on', 'offline']
      }),
    ]),
  ];
}

class _Group {
  const _Group(this.label, this.entries);
  final String label;
  final List<_Entry> entries;
}

class _Entry {
  const _Entry(this.label, this.type, this.hint, this.config);
  final String label;
  final String type;
  final String hint;
  final Map<String, dynamic> config;
}

class _Room {
  const _Room(
      {required this.area,
      required this.label,
      required this.total,
      required this.on});
  final String area;
  final String label;
  final int total;
  final int on;
}

class _Search extends StatelessWidget {
  const _Search({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: BorderRadius.circular(t.radius.sm),
        border: Border.all(color: t.stroke.hairline, width: t.stroke.width),
      ),
      padding: EdgeInsets.symmetric(horizontal: t.space.sm),
      child: TextField(
        onChanged: onChanged,
        style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: 'Search rooms and cards',
          hintStyle:
              t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.xs),
      child: Text(label.toUpperCase(),
          style: t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted)),
    );
  }
}

/// A room, with the two numbers that make it a real thing rather than a label.
class _RoomRow extends StatelessWidget {
  const _RoomRow({required this.room, required this.onTap});
  final _Room room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(t.radius.sm),
      child: Padding(
        padding:
            EdgeInsets.symmetric(vertical: t.space.xs, horizontal: t.space.xs),
        child: Row(
          children: [
            Expanded(
              child: Text(room.label,
                  style:
                      t.text.bodySmallStyle.copyWith(color: t.surface.onBase)),
            ),
            Text(
              '${room.total}',
              style: t.text.bodySmallStyle.copyWith(
                  color: t.surface.onBaseMuted,
                  fontFeatures: t.numericFontFeatures),
            ),
            SizedBox(width: t.space.sm),
            SizedBox(
              width: 44,
              child: Text(
                room.on > 0 ? '${room.on} on' : '',
                textAlign: TextAlign.right,
                style: t.text.captionStyle.copyWith(
                    color:
                        room.on > 0 ? t.accent.active : t.surface.onBaseMuted,
                    fontFeatures: t.numericFontFeatures),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlainRow extends StatelessWidget {
  const _PlainRow(
      {required this.label, required this.hint, required this.onTap});
  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(t.radius.sm),
      child: Padding(
        padding:
            EdgeInsets.symmetric(vertical: t.space.xs, horizontal: t.space.xs),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style:
                      t.text.bodySmallStyle.copyWith(color: t.surface.onBase)),
            ),
            Flexible(
              child: Text(hint,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.captionStyle
                      .copyWith(color: t.surface.onBaseMuted)),
            ),
          ],
        ),
      ),
    );
  }
}
