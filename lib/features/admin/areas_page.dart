import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/device_state.dart';
import '../../core/providers/areas_provider.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/components/hc_surface.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';

/// Areas, studio-style: a rail of rooms on the left navigates; the pane shows
/// only the selected room — its devices, removable in place, with an
/// add-from-the-house picker below.
class AreasPage extends ConsumerStatefulWidget {
  const AreasPage({super.key});

  @override
  ConsumerState<AreasPage> createState() => _AreasPageState();
}

class _AreasPageState extends ConsumerState<AreasPage> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final areasAsync = ref.watch(areasProvider);

    final areas = areasAsync.value ?? const [];
    final assigned = areas.fold<int>(
        0, (a, x) => a + ((x['device_ids'] as List?)?.length ?? 0));

    return SectionScaffold(
      title: 'Areas',
      stats: areasAsync.hasValue
          ? [
              SectionStat(
                  value: '${areas.length}',
                  label: areas.length == 1 ? 'room' : 'rooms'),
              SectionStat(value: '$assigned', label: 'devices'),
            ]
          : const [],
      actions: [
        Builder(builder: (context) {
          final t = HcTokens.of(context);
          return IconButton(
            icon: Icon(Icons.refresh, color: t.surface.onBaseMuted),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(areasProvider),
          );
        }),
        SectionHeaderAction(
          icon: Icons.add_rounded,
          label: 'Add area',
          onPressed: () => _createArea(context),
        ),
      ],
      child: areasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (areas) {
          if (areas.isEmpty) {
            return _Empty(onAdd: () => _createArea(context));
          }
          final sorted = [...areas]..sort((a, b) => humanize('${a['name']}')
              .toLowerCase()
              .compareTo(humanize('${b['name']}').toLowerCase()));

          // Resolve the selection — default to the first room.
          Map<String, dynamic> selected = sorted.first;
          for (final a in sorted) {
            if (a['id'] == _selectedId) {
              selected = a;
              break;
            }
          }

          final t = HcTokens.of(context);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 260,
                child: _Rail(
                  areas: sorted,
                  selectedId: selected['id'] as String,
                  onSelect: (id) => setState(() => _selectedId = id),
                ),
              ),
              VerticalDivider(width: 1, color: t.stroke.hairline),
              Expanded(
                child: _AreaPane(
                  key: ValueKey(selected['id']),
                  area: selected,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createArea(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await _promptForName(context, title: 'Add area');
    if (name == null || name.isEmpty) return;
    try {
      final created = await ref.read(areasApiProvider).createArea(name);
      ref.invalidate(areasProvider);
      if (created['id'] != null) {
        setState(() => _selectedId = created['id'] as String);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
}

// ── left rail: rooms ──

class _Rail extends StatelessWidget {
  const _Rail(
      {required this.areas, required this.selectedId, required this.onSelect});
  final List<Map<String, dynamic>> areas;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return ListView(
      padding:
          EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.md),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(t.space.sm, 0, t.space.sm, t.space.sm),
          child: Text('ROOMS · ${areas.length}',
              style: t.text.captionStyle.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: t.surface.onBaseMuted)),
        ),
        for (final a in areas)
          _RailItem(
            area: a,
            selected: a['id'] == selectedId,
            onTap: () => onSelect(a['id'] as String),
          ),
      ],
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem(
      {required this.area, required this.selected, required this.onTap});
  final Map<String, dynamic> area;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final name = area['name'] as String? ?? '';
    final count = (area['device_ids'] as List?)?.length ?? 0;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.xs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: t.radius.smR,
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: t.space.md, vertical: t.space.sm + 1),
            decoration: BoxDecoration(
              color: selected
                  ? t.accent.active.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: t.radius.smR,
              border: Border(
                left: BorderSide(
                  color: selected ? t.accent.active : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(humanize(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.text.bodyStyle.copyWith(
                        fontWeight: FontWeight.w600,
                        color: selected ? t.accent.active : t.surface.onBase)),
                const SizedBox(height: 2),
                Text('$name · $count device${count == 1 ? '' : 's'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.text
                        .resolve(t.text.caption, mono: true)
                        .copyWith(color: t.surface.onBaseMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── right pane: the selected room ──

class _AreaPane extends ConsumerStatefulWidget {
  const _AreaPane({super.key, required this.area});
  final Map<String, dynamic> area;

  @override
  ConsumerState<_AreaPane> createState() => _AreaPaneState();
}

class _AreaPaneState extends ConsumerState<_AreaPane> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  String get _id => widget.area['id'] as String;
  String get _name => widget.area['name'] as String? ?? '';
  List<String> get _deviceIds =>
      List<String>.from(widget.area['device_ids'] as List? ?? const []);

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _setMembership(List<String> ids) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(areasApiProvider).setDevices(_id, ids);
      ref.invalidate(areasProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final devices = ref.watch(devicesProvider).value ?? const [];
    final byId = {for (final d in devices) d.id: d};

    final ids = _deviceIds;
    final idSet = ids.toSet();

    // In this room, resolved to devices (keep unresolved ids too — a device
    // may be offline or removed but still assigned).
    final inRoom = ids.map((id) => (id: id, dev: byId[id])).toList()
      ..sort((a, b) => _label(a.id, a.dev)
          .toLowerCase()
          .compareTo(_label(b.id, b.dev).toLowerCase()));

    // Candidates to add: everything not already in the room, filtered by search.
    final q = _search.trim().toLowerCase();
    final candidates = devices.where((d) => !idSet.contains(d.id)).where((d) {
      if (q.isEmpty) return true;
      return d.displayName.toLowerCase().contains(q) ||
          d.id.toLowerCase().contains(q) ||
          d.pluginId.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    return ListView(
      padding: EdgeInsets.all(t.space.lg),
      children: [
        // pane header: room name + rename
        Row(children: [
          Expanded(
            child: Text(humanize(_name),
                style: TextStyle(
                    color: t.surface.onBase,
                    fontSize: t.text.scaled(20),
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3)),
          ),
          IconButton(
            icon: Icon(Icons.edit_outlined,
                size: 18, color: t.surface.onBaseMuted),
            tooltip: 'Rename',
            onPressed: _rename,
          ),
        ]),
        SizedBox(height: t.space.md),

        // tiles
        Wrap(spacing: t.space.md, runSpacing: t.space.md, children: [
          _Tile(label: 'Devices in room', value: '${ids.length}'),
          _Tile(label: 'Area code', value: _name, mono: true),
        ]),
        SizedBox(height: t.space.lg),

        // devices in this room
        _SectionLabel('Devices in this room', trailing: '${ids.length}'),
        SizedBox(height: t.space.sm),
        if (inRoom.isEmpty)
          const _EmptyHint('No devices assigned yet — add one below.')
        else
          HcSurface(
            padding: EdgeInsets.symmetric(horizontal: t.space.md),
            child: Column(children: [
              for (var i = 0; i < inRoom.length; i++) ...[
                if (i > 0) Divider(height: 1, color: t.stroke.hairline),
                _RoomDeviceRow(
                  label: _label(inRoom[i].id, inRoom[i].dev),
                  id: inRoom[i].id,
                  onRemove: () => _setMembership(
                      ids.where((x) => x != inRoom[i].id).toList()),
                ),
              ],
            ]),
          ),
        SizedBox(height: t.space.lg),

        // add from the rest of the house
        _SectionLabel('Add a device',
            trailing: '${devices.length - ids.length} elsewhere'),
        SizedBox(height: t.space.sm),
        HcSurface(
          padding: EdgeInsets.all(t.space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchCtrl,
                style: t.text.bodyStyle.copyWith(color: t.surface.onBase),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search devices to add…',
                  hintStyle:
                      t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted),
                  prefixIcon: Icon(Icons.search,
                      size: 18, color: t.surface.onBaseMuted),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: t.stroke.hairline)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: t.accent.active)),
                ),
              ),
              SizedBox(height: t.space.sm),
              if (candidates.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: t.space.md),
                  child: Text(
                      q.isEmpty
                          ? 'Every device is already in a room.'
                          : 'No devices match "$_search".',
                      style: t.text.bodySmallStyle
                          .copyWith(color: t.surface.onBaseMuted)),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    itemBuilder: (_, i) {
                      final d = candidates[i];
                      return _AddDeviceRow(
                        label: d.displayName,
                        id: d.id,
                        onAdd: () => _setMembership([...ids, d.id]),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: t.space.xl),

        // danger
        _DangerZone(
            name: humanize(_name), count: ids.length, onDelete: _delete),
      ],
    );
  }

  String _label(String id, DeviceState? dev) => dev?.displayName ?? id;

  Future<void> _rename() async {
    final messenger = ScaffoldMessenger.of(context);
    final next = await _promptForName(context,
        title: 'Rename area', initial: humanize(_name));
    if (next == null || next.isEmpty || next == humanize(_name)) return;
    try {
      await ref.read(areasApiProvider).renameArea(_id, next);
      ref.invalidate(areasProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _delete() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok =
        await _confirmDelete(context, humanize(_name), _deviceIds.length);
    if (ok != true) return;
    try {
      await ref.read(areasApiProvider).deleteArea(_id);
      ref.invalidate(areasProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.mono = false});
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return HcSurface(
      padding: EdgeInsets.all(t.space.md),
      child: SizedBox(
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(),
                style: t.text.captionStyle.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: t.surface.onBaseMuted)),
            SizedBox(height: t.space.sm),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: mono ? 15 : 20,
                    fontWeight: FontWeight.w600,
                    fontFamily: mono ? 'monospace' : null,
                    color: t.surface.onBase,
                    fontFeatures: t.numericFontFeatures)),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {this.trailing});
  final String label;
  final String? trailing;
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Row(children: [
      Expanded(
        child: Text(label.toUpperCase(),
            style: t.text.captionStyle.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: t.surface.onBaseMuted)),
      ),
      if (trailing != null)
        Text(trailing!,
            style: t.text.bodySmallStyle.copyWith(
                color: t.surface.onBaseMuted,
                fontFeatures: t.numericFontFeatures)),
    ]);
  }
}

class _RoomDeviceRow extends StatelessWidget {
  const _RoomDeviceRow(
      {required this.label, required this.id, required this.onRemove});
  final String label;
  final String id;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.sm + 1),
      child: Row(children: [
        Expanded(
          child: Row(children: [
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.bodyStyle.copyWith(color: t.surface.onBase)),
            ),
            SizedBox(width: t.space.sm),
            Text(id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text
                    .resolve(t.text.caption, mono: true)
                    .copyWith(color: t.surface.onBaseMuted)),
          ]),
        ),
        IconButton(
          icon: Icon(Icons.close, size: 16, color: t.surface.onBaseMuted),
          tooltip: 'Remove from room',
          visualDensity: VisualDensity.compact,
          onPressed: onRemove,
        ),
      ]),
    );
  }
}

class _AddDeviceRow extends StatelessWidget {
  const _AddDeviceRow(
      {required this.label, required this.id, required this.onAdd});
  final String label;
  final String id;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return InkWell(
      onTap: onAdd,
      borderRadius: t.radius.smR,
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: t.space.xs, vertical: t.space.sm),
        child: Row(children: [
          Expanded(
            child: Row(children: [
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: t.text.bodyStyle.copyWith(color: t.surface.onBase)),
              ),
              SizedBox(width: t.space.sm),
              Text(id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.text
                      .resolve(t.text.caption, mono: true)
                      .copyWith(color: t.surface.onBaseMuted)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: t.radius.pillR,
              border: Border.all(color: t.accent.active.withValues(alpha: 0.4)),
            ),
            child: Text('+ Add',
                style: t.text.bodySmallStyle.copyWith(
                    color: t.accent.active, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

class _DangerZone extends StatelessWidget {
  const _DangerZone(
      {required this.name, required this.count, required this.onDelete});
  final String name;
  final int count;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        color: t.accent.danger.withValues(alpha: 0.04),
        borderRadius: t.radius.mdR,
        border: Border.all(color: t.accent.danger.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Delete this area',
              style: t.text.bodyStyle.copyWith(
                  color: t.accent.danger, fontWeight: FontWeight.w600)),
          SizedBox(height: t.space.xs),
          Text(
              count == 0
                  ? 'Removes $name. No devices are assigned to it.'
                  : 'Removes $name and clears it from its $count device${count == 1 ? '' : 's'}. The devices stay; they just lose their room.',
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(height: t.space.md),
          HcButton(
              label: 'Delete area',
              kind: HcButtonKind.danger,
              onPressed: onDelete),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return HcSurface(
      padding: EdgeInsets.all(t.space.md),
      child: Text(text,
          style: t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted)),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.meeting_room_outlined,
              size: 40, color: t.surface.onBaseMuted),
          SizedBox(height: t.space.md),
          Text('No areas yet',
              style: t.text.subtitleStyle.copyWith(color: t.surface.onBase)),
          SizedBox(height: t.space.xs),
          Text('Group devices by room.',
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(height: t.space.md),
          HcButton(
              label: 'Add area',
              kind: HcButtonKind.primary,
              icon: Icons.add_rounded,
              onPressed: onAdd),
        ],
      ),
    );
  }
}

// ── shared dialogs ──

Future<String?> _promptForName(BuildContext context,
    {required String title, String? initial}) async {
  final ctrl = TextEditingController(text: initial ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final t = HcTokens.of(ctx);
      void submit() => Navigator.pop(ctx, ctrl.text.trim());
      return HcDialog(
        title: title,
        actions: [
          HcButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx)),
          HcButton(
              label: 'Save', kind: HcButtonKind.primary, onPressed: submit),
        ],
        child: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: t.surface.onBase),
          decoration: InputDecoration(
            labelText: 'Name',
            labelStyle: TextStyle(color: t.surface.onBaseMuted),
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: t.stroke.hairline)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: t.accent.active)),
          ),
          onSubmitted: (_) => submit(),
        ),
      );
    },
  );
  ctrl.dispose();
  return result;
}

Future<bool?> _confirmDelete(BuildContext context, String name, int count) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => HcDialog(
      title: 'Delete $name?',
      description: count == 0
          ? 'This cannot be undone.'
          : 'Clears $name from its $count device${count == 1 ? '' : 's'}. This cannot be undone.',
      actions: [
        HcButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
        HcButton(
            label: 'Delete',
            kind: HcButtonKind.danger,
            onPressed: () => Navigator.pop(ctx, true)),
      ],
      child: const SizedBox.shrink(),
    ),
  );
}
