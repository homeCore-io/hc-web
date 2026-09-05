import '../../core/api/api_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/modes_provider.dart';
import '../../core/providers/active_sort_provider.dart';
import '../../core/providers/room_collapse_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../devices/device_query.dart';
import '../devices/device_sheet.dart';
import '../../core/providers/areas_provider.dart';
import '../../core/providers/dashboards_provider.dart';
import '../../design/components/hc_controls.dart';
import '../../design/components/hc_sensor_chip.dart';
import '../../shell/hc_sheet.dart';
import '../cameras/camera_store.dart';
import 'home_arrangement.dart';
import 'room_summary.dart';
import 'assign_rooms_sheet.dart';
import 'home_camera_card.dart';
import 'home_entity_row.dart';
import 'home_rich_cards.dart';
import 'home_thermostat.dart';

/// The house.
///
/// This is the app's one primary surface, and the change it represents is the
/// point of the whole redesign: you land on your home, not on a menu.
///
/// What was here before was a *dashboard CMS* — you navigated to a list of
/// dashboards, picked one, viewed it, and opened a separate 2,000-line editor
/// page to change it. That is a website's admin panel. Eight co-equal
/// destinations in a rail is a site menu. An app has one surface that IS the
/// thing, and everything else is either laid over it or tucked behind it.
///
/// So: rooms, devices, live, directly manipulable. Tap a light and it lights.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  /// Non-null while arranging — a working copy, so abandoning Arrange leaves the
  /// saved layout exactly as it was.
  HomeArrangement? _draft;
  bool _saving = false;

  bool get _arranging => _draft != null;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final devicesAsync = ref.watch(devicesProvider);
    final saved =
        HomeArrangement.fromDashboard(ref.watch(defaultDashboardProvider));
    // Only the cameras the user put on Home get a card; the rest live on the
    // Cameras page. Each is its own arrangeable card.
    final homeCams = ref.watch(homeCamerasProvider);

    return Scaffold(
      floatingActionButton: _arranging
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(HcIcons.grip, size: 16),
              label: const Text('Arrange'),
              onPressed: () => setState(() => _draft = saved),
            ),
      bottomNavigationBar: !_arranging
          ? null
          : _ArrangeBar(
              saving: _saving,
              onCancel: () => setState(() => _draft = null),
              onDone: _save,
            ),
      body: devicesAsync.when(
        // A skeleton, not a zero. The old dashboard rendered `0 Devices` while
        // loading, which is a confident lie about your house — and it fooled me
        // into reporting a data-corruption bug that did not exist.
        loading: () => const _HomeSkeleton(),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(HcIcons.warning, color: t.accent.danger, size: 22),
              SizedBox(height: t.space.sm),
              Text('Cannot reach homeCore',
                  style: TextStyle(color: t.surface.onBase)),
              SizedBox(height: t.space.xs),
              Text('$e',
                  style: t.text.bodySmallStyle
                      .copyWith(color: t.surface.onBaseMuted)),
            ],
          ),
        ),
        data: (allDevices) {
          // The house shows rooms of devices you live with — bridges and hubs
          // are infrastructure you manage from the plugin Studio, not tiles on
          // the wall. Filtering here keeps them out of the rooms, the arrange
          // order, the persisted layout, and the header counts alike.
          final devices =
              allDevices.where((d) => !isInfrastructureDevice(d)).toList();
          return _House(
            devices: devices,
            arrangement: _draft ?? saved,
            arranging: _arranging,
            onReorder: (from, to) => setState(() {
              final rooms = _orderKeys(devices, homeCams);
              final order = _draft!.all(rooms);
              if (to > from) to--;
              final moved = order.removeAt(from);
              order.insert(to, moved);
              _draft = _draft!.copyWith(order: order);
            }),
            onToggleHidden: (room) => setState(() {
              final hidden = {..._draft!.hidden};
              hidden.contains(room) ? hidden.remove(room) : hidden.add(room);
              _draft = _draft!.copyWith(hidden: hidden);
            }),
            onCommit: (order, columns) =>
                _persistLayout(devices, homeCams, order, columns),
          );
        },
      ),
    );
  }

  /// Save the layout from a direct card drag straight away — no Arrange mode.
  /// Hidden rooms are not in the dragged list (they are not on screen), so their
  /// hidden state is preserved and they append in the arrangement.
  Future<void> _persistLayout(
    List<DeviceState> devices,
    List<Camera> homeCams,
    List<String> order,
    Map<String, int> columns,
  ) async {
    final dashboard = ref.read(defaultDashboardProvider);
    if (dashboard == null) return;
    final current = HomeArrangement.fromDashboard(dashboard);
    final next = current.copyWith(order: order, columns: columns);
    try {
      await ref.read(dashboardsProvider.notifier).updateDashboard(
            next.toDashboard(dashboard, _orderKeys(devices, homeCams)),
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save order: ${apiMessage(e)}')));
      }
    }
  }

  /// Every draggable card's key, in default order: the rooms, then one key per
  /// camera the user put on Home. What Arrange reorders and the masonry lays out.
  static List<String> _orderKeys(
    List<DeviceState> devices,
    List<Camera> homeCams,
  ) =>
      [
        ...runQuery(
          devices,
          const DeviceQuery(
              group: DeviceGroup.room, sort: DeviceSort.activeFirst),
        ).map((g) => g.key),
        for (final c in homeCams) homeCameraKey(c.id),
      ];

  Future<void> _save() async {
    final draft = _draft;
    final dashboard = ref.read(defaultDashboardProvider);
    final devices = ref.read(devicesProvider).value ?? const [];
    final homeCams = ref.read(homeCamerasProvider);
    if (draft == null || dashboard == null) {
      setState(() => _draft = null);
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(dashboardsProvider.notifier).updateDashboard(
            draft.toDashboard(dashboard, _orderKeys(devices, homeCams)),
          );
      if (mounted) setState(() => _draft = null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save: ${apiMessage(e)}')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// The bar that owns Arrange mode, so there is always a way out of it.
class _ArrangeBar extends StatelessWidget {
  const _ArrangeBar({
    required this.saving,
    required this.onCancel,
    required this.onDone,
  });

  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Container(
      padding:
          EdgeInsets.fromLTRB(t.space.lg, t.space.sm, t.space.lg, t.space.sm),
      decoration: BoxDecoration(
        color: t.surface.raised,
        border: Border(top: BorderSide(color: t.stroke.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Icon(HcIcons.grip, size: 14, color: t.accent.primary),
            SizedBox(width: t.space.sm),
            Expanded(
              child: Text(
                'Drag a room to reorder it. Hide one with the eye.',
                style: t.text.bodySmallStyle
                    .copyWith(color: t.surface.onBaseMuted),
              ),
            ),
            TextButton(
                onPressed: saving ? null : onCancel,
                child: const Text('Cancel')),
            SizedBox(width: t.space.xs),
            FilledButton(
              onPressed: saving ? null : onDone,
              child: saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _House extends ConsumerStatefulWidget {
  const _House({
    required this.devices,
    required this.arrangement,
    required this.arranging,
    required this.onReorder,
    required this.onToggleHidden,
    required this.onCommit,
  });

  final List<DeviceState> devices;
  final HomeArrangement arrangement;
  final bool arranging;
  final void Function(int from, int to) onReorder;
  final ValueChanged<String> onToggleHidden;

  /// Persist a new layout after a direct card drag: the visible keys in their new
  /// sequence, and each dragged card's pinned column. Hidden rooms keep their
  /// state and append.
  final void Function(List<String> order, Map<String, int> columns) onCommit;

  @override
  ConsumerState<_House> createState() => _HouseState();
}

class _HouseState extends ConsumerState<_House> {
  /// Rooms the user has folded shut. A glance-time act, not part of the shared
  /// house layout — so it is kept as a local UI preference (roomCollapseProvider,
  /// SharedPreferences) that survives a reload without a dashboard write on every
  /// tap. Mirrored into this field each build so `_estimateHeight` can read it. A
  /// room absent from the set is open — a newly installed room is never folded by
  /// default.
  Set<String> _collapsed = const {};

  void _toggle(String key) =>
      ref.read(roomCollapseProvider.notifier).toggle(key);

  // Direct drag: long-press a card to lift it; a ghost chip follows the cursor
  // and a bright bar shows where it will land. The board holds still and settles
  // on drop. Crucially the card lands WHERE you drop it — the column and the slot
  // you chose — not wherever a balancer decides. Each card remembers its column
  // (HomeArrangement.columns); untouched cards auto-place into the shortest
  // column, so a fresh board is balanced and only what you move stays pinned.
  //
  // The drop is handled by DragTarget.onAccept (the target Flutter reports under
  // the pointer at release, robust across columns) and the landing bar by its
  // `candidateData` (rebuilt on its own — no hover state to lose mid-drag).

  /// Drop [dragged] into [col], just before [before], and save. A null [col]
  /// un-pins it (a full-width hero has no column).
  void _dropBefore(String dragged, String before, int? col, List<String> keys) {
    if (dragged == before) return;
    final order = [...keys]..remove(dragged);
    final at = order.indexOf(before);
    order.insert(at < 0 ? order.length : at, dragged);
    _commit(dragged, col, order);
  }

  /// Drop [dragged] at the BOTTOM of [col] — after [lastInCol], the column's
  /// current last card (null if the column is empty).
  void _dropIntoColumn(
    String dragged,
    int col,
    String? lastInCol,
    List<String> keys,
  ) {
    final order = [...keys]..remove(dragged);
    final anchor = (lastInCol != null && lastInCol != dragged)
        ? order.indexOf(lastInCol)
        : -1;
    order.insert(anchor < 0 ? order.length : anchor + 1, dragged);
    _commit(dragged, col, order);
  }

  /// The column every card currently renders in — recorded each build. A drop
  /// pins the WHOLE board to this, then moves only the dragged card, so nothing
  /// else shifts. Without it, an untouched card re-balances the moment any other
  /// card is pinned, and the board reshuffles under you.
  final Map<String, int> _renderedColumns = {};

  void _commit(String dragged, int? col, List<String> order) {
    final columns = {..._renderedColumns};
    if (col == null) {
      columns.remove(dragged);
    } else {
      columns[dragged] = col;
    }
    widget.onCommit(order, columns);
  }

  /// Wraps a card so it can be picked up and dropped onto. [label] names the
  /// ghost chip; [col] is the column this card sits in (null for a full-width
  /// hero); [keys] is the current sequence (stable during a drag).
  Widget _arrangeable(
    String key,
    String label,
    int? col,
    List<String> keys,
    Widget card,
  ) {
    final t = HcTokens.of(context);

    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != key,
      onAcceptWithDetails: (d) => _dropBefore(d.data, key, col, keys),
      builder: (context, candidate, rejected) {
        final active = candidate.any((c) => c != null && c != key);
        return LongPressDraggable<String>(
          data: key,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          hapticFeedbackOnStart: true,
          feedback: FractionalTranslation(
            translation: const Offset(0.08, 0.4),
            child: _DragChip(label: label),
          ),
          childWhenDragging:
              Opacity(opacity: 0.35, child: IgnorePointer(child: card)),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              card,
              // The landing bar sits at the top edge of the card the lift will
              // drop in front of — a clear "it goes here", no guessing.
              if (active)
                Positioned(
                  left: t.space.xs,
                  right: t.space.xs,
                  top: -3,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.accent.active,
                      borderRadius: t.radius.pillR,
                      boxShadow:
                          t.glow.halo(t.accent.active, blur: 6, alpha: 0.5),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// The drop zone at the bottom of a column: dropping here pins a card to this
  /// column, after its current last card. It stays a slim strip until a card is
  /// held over it, then opens into a labelled slot.
  Widget _columnTail(int col, String? lastInCol, List<String> keys) {
    final t = HcTokens.of(context);
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => true,
      onAcceptWithDetails: (d) => _dropIntoColumn(d.data, col, lastInCol, keys),
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: t.motion.d(t.motion.fast),
          height: active ? 60 : 24,
          margin: EdgeInsets.only(bottom: t.space.md),
          decoration: active
              ? BoxDecoration(
                  color: t.accent.active.withValues(alpha: 0.08),
                  border: Border.all(color: t.accent.active, width: 1.5),
                  borderRadius: t.radius.lgR,
                )
              : null,
          alignment: Alignment.center,
          child: active
              ? Text('Drop in this column',
                  style: t.text.bodySmallStyle.copyWith(
                      fontWeight: FontWeight.w600, color: t.accent.active))
              : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final notifier = ref.read(devicesProvider.notifier);
    final devices = widget.devices;
    // Folded rooms are a persisted local preference; mirror the watched set into
    // the field so the header taps and the masonry height estimate agree.
    _collapsed = ref.watch(roomCollapseProvider);

    // Rooms, not "sections". The house already has a structure; inventing a
    // second one in a dashboard document was the original mistake.
    final activeFirst = ref.watch(activeSortProvider);
    final groups = runQuery(
      devices,
      DeviceQuery(
        group: DeviceGroup.room,
        sort: activeFirst ? DeviceSort.activeFirst : DeviceSort.name,
      ),
    );
    final byKey = {for (final g in groups) g.key: g};
    final problems = problemsIn(devices);
    // Only the cameras chosen for Home get a card, each keyed by its id.
    final homeCams = ref.watch(homeCamerasProvider);
    final camById = {for (final c in homeCams) c.id: c};

    // Every arrangeable card: the rooms, plus one per Home camera. Cameras
    // order, hide, resize, and drag exactly like a room.
    final areaKeys = [
      ...byKey.keys,
      for (final c in homeCams) homeCameraKey(c.id),
    ];

    // While arranging you see every area INCLUDING the hidden ones, or you could
    // never bring one back.
    final keys = widget.arranging
        ? widget.arrangement.all(areaKeys)
        : widget.arrangement.apply(areaKeys);

    if (widget.arranging) {
      return ReorderableListView.builder(
        padding: EdgeInsets.fromLTRB(t.space.lg, t.space.lg, t.space.lg, 0),
        itemCount: keys.length,
        // Off: on desktop/web this list injects a trailing drag handle on every
        // row, which lands on top of the eye and makes it hard to hit. We supply
        // our own grip on the LEFT (ReorderableDragStartListener), so the built-in
        // one is redundant as well as in the way.
        buildDefaultDragHandles: false,
        onReorderItem: widget.onReorder,
        itemBuilder: (context, i) {
          final key = keys[i];
          final cam = camById[cameraIdFromKey(key) ?? ''];
          return _ArrangeRow(
            key: ValueKey(key),
            index: i,
            label: cam != null ? cam.name : humanize(key),
            count: cam != null ? 0 : (byKey[key]?.devices.length ?? 0),
            detail: cam != null
                ? (cam.homeLarge ? 'Large camera' : 'Camera')
                : null,
            hidden: widget.arrangement.hidden.contains(key),
            onToggleHidden: () => widget.onToggleHidden(key),
          );
        },
      );
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                t.space.lg, t.space.lg, t.space.lg, t.space.md),
            child: _HouseHeader(devices: devices, problems: problems.length),
          ),
        ),
        // The alarm, as a card rather than a count.
        //
        // It used to be a dotted-underline number in the stat line, which is a
        // footnote's weight for the one thing on this page that is asking for
        // something. Naming each device is also what makes the count checkable
        // — a wrong "11 need attention" hid behind its own vagueness for
        // months.
        if (problems.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  EdgeInsets.fromLTRB(t.space.lg, 0, t.space.lg, t.space.md),
              child: _AttentionCard(problems: problems),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: t.space.lg),
            child: LayoutBuilder(
              builder: (context, c) {
                // Rooms pack into balanced columns instead of each taking a
                // full-width band it only half fills. A one-lamp room and a
                // twelve-device room now sit side by side, so the house reads as
                // a dense board — not a ragged list dropped down the left edge.
                final colCount = (c.maxWidth / 360).floor().clamp(1, 4);
                final colW =
                    (c.maxWidth - (colCount - 1) * t.space.md) / colCount;

                Widget room(String key) => _Room(
                      room: byKey[key]!,
                      activeFirst: activeFirst,
                      collapsed: _collapsed.contains(key),
                      onToggleCollapse: () => _toggle(key),
                      // The bucket gets the one action that empties it.
                      onAssignRooms: byKey[key]!.key == HomeArrangement.kNoRoom
                          ? () =>
                              showAssignRoomsSheet(context, byKey[key]!.devices)
                          : null,
                      // "No room" is a dumping bucket, not an area, so it cannot
                      // be renamed.
                      onRename: byKey[key]!.key == HomeArrangement.kNoRoom
                          ? null
                          : () => _renameRoom(byKey[key]!.key),
                      // Scene duality: Lutron wants {"activate": true}; Hue
                      // wants {"action": "activate_scene"}. Pick by owner.
                      onActivate: (d) => notifier.command(
                        d.id,
                        d.pluginId.contains('hue')
                            ? {'action': 'activate_scene'}
                            : {'activate': true},
                      ),
                    );

                Widget smallCamera(String key, Camera cam) => HomeCameraCard(
                      camera: cam,
                      large: false,
                      collapsed: _collapsed.contains(key),
                      onToggleCollapse: () => _toggle(key),
                    );

                Widget cardFor(String key, int col, List<String> full) {
                  final cam = camById[cameraIdFromKey(key) ?? ''];
                  return cam != null
                      ? _arrangeable(
                          key, cam.name, col, full, smallCamera(key, cam))
                      : _arrangeable(key, humanize(key), col, full, room(key));
                }

                // Lay a run of single-column cards out into columns. A card the
                // user PINNED (dragged) goes to its column; an untouched card
                // fills the shortest column, so a fresh board self-balances. Each
                // column ends in a drop zone that pins a card to that column.
                Widget board(List<String> ks, List<String> full) {
                  final colKeys = List.generate(colCount, (_) => <String>[]);
                  final heights = List<double>.filled(colCount, 0);
                  for (final key in ks) {
                    final pinned = widget.arrangement.columnOf(key);
                    var col = 0;
                    if (pinned != null) {
                      col = pinned.clamp(0, colCount - 1);
                    } else {
                      for (var i = 1; i < colCount; i++) {
                        if (heights[i] < heights[col]) col = i;
                      }
                    }
                    final cam = camById[cameraIdFromKey(key) ?? ''];
                    heights[col] += cam != null
                        ? (_collapsed.contains(key)
                            ? 48
                            : 46 + colW / (16 / 10) + 14)
                        : _estimateHeight(byKey[key]!);
                    colKeys[col].add(key);
                    _renderedColumns[key] = col;
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < colCount; i++) ...[
                        if (i > 0) SizedBox(width: t.space.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final key in colKeys[i])
                                cardFor(key, i, full),
                              _columnTail(
                                  i,
                                  colKeys[i].isEmpty ? null : colKeys[i].last,
                                  full),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                }

                // Recompute where every card renders this frame; a drop reads it
                // to pin the whole board and move only the lifted card.
                _renderedColumns.clear();

                // A large camera is a full-width hero, so it breaks the column
                // flow: cards lay out into a band, a hero spans the whole width,
                // then the columns resume below it.
                final bands = <Widget>[];
                var band = <String>[];
                void flush() {
                  if (band.isNotEmpty) {
                    bands.add(board(band, keys));
                    band = [];
                  }
                }

                for (final key in keys) {
                  final cam = camById[cameraIdFromKey(key) ?? ''];
                  if (cam != null && cam.homeLarge) {
                    flush();
                    bands.add(_arrangeable(
                      key,
                      cam.name,
                      null,
                      keys,
                      HomeCameraCard(
                        camera: cam,
                        large: true,
                        collapsed: _collapsed.contains(key),
                        onToggleCollapse: () => _toggle(key),
                      ),
                    ));
                  } else {
                    band.add(key);
                  }
                }
                flush();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: bands,
                );
              },
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: t.space.xl)),
      ],
    );
  }

  /// Rename a room in plain English. Core renames the shared area and cascades
  /// the new name to every device in it (`PATCH /areas/:id`), so one rename fixes
  /// the whole room. The area's id comes from the areas list, keyed by its
  /// normalized name — which is exactly the room key the house groups on.
  Future<void> _renameRoom(String areaKey) async {
    final controller = TextEditingController(text: humanize(areaKey));
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final t = HcTokens.of(ctx);
        return AlertDialog(
          backgroundColor: t.surface.overlay,
          title: const Text('Rename room'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Room name'),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (newName == null || newName.isEmpty || newName == humanize(areaKey)) {
      return;
    }
    try {
      final areas = await ref.read(areasProvider.future);
      final match = areas.firstWhere(
        (a) =>
            a['name'] == areaKey ||
            humanize('${a['name']}') == humanize(areaKey),
        orElse: () => const <String, dynamic>{},
      );
      final id = match['id'];
      if (id is! String) throw 'Room not found';
      await ref.read(areasApiProvider).renameArea(id, newName);
      ref.invalidate(areasProvider);
      ref.invalidate(devicesProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not rename: $e')));
      }
    }
  }

  /// A rough height for a room card, only to balance the masonry columns —
  /// exactness does not matter, only which column is currently shortest. Each
  /// device is a ~44px row; scenes add a small block.
  double _estimateHeight(DeviceGroupResult room) {
    if (_collapsed.contains(room.key)) return 48;
    var rows = 0, scenes = 0, climate = 0, playing = 0;
    for (final d in room.devices) {
      final f = facetOf(d, d.schema);
      if (f == DeviceFacet.scene) {
        scenes++;
      } else {
        rows++;
        if (f == DeviceFacet.climate) climate++;
        if (f == DeviceFacet.mediaPlayer && d.playbackState == 'playing') {
          playing++;
        }
      }
    }
    // Thermostats are compact by default (a large one the user pinned throws the
    // estimate off a little, which only nudges column balance — harmless).
    return 46 +
        rows * 44 +
        climate * 16 +
        playing * 150 +
        (scenes > 0 ? 74 : 0) +
        12;
  }
}

/// The devices asking for something, named.
class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.problems});

  final List<DeviceProblem> problems;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    // Capped: a house with a flat battery in every sensor should not push the
    // rooms off the screen. The sheet behind "N more" has the rest.
    const cap = 4;
    final shown = problems.take(cap).toList();

    return Container(
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        color: t.accent.warn.withValues(alpha: 0.07),
        borderRadius: t.radius.mdR,
        border: Border.all(color: t.accent.warn.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(HcIcons.warning, size: 14, color: t.accent.warn),
              SizedBox(width: t.space.sm),
              Text(
                problems.length == 1
                    ? '1 thing needs you'
                    : '${problems.length} things need you',
                style: t.text.bodySmallStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: t.accent.warn,
                    fontFeatures: t.numericFontFeatures),
              ),
            ],
          ),
          SizedBox(height: t.space.sm),
          Wrap(
            spacing: t.space.sm,
            runSpacing: t.space.sm,
            children: [
              for (final p in shown)
                _AttentionChip(
                  problem: p,
                  onTap: () => showDeviceSheet(context, p.device.id),
                ),
              if (problems.length > cap)
                _MoreChip(
                  label: '+${problems.length - cap} more',
                  onTap: () => _showNeedsAttention(context, [
                    for (final p in problems) p.device,
                  ]),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttentionChip extends StatelessWidget {
  const _AttentionChip({required this.problem, required this.onTap});

  final DeviceProblem problem;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final offline = problem.reason == 'offline';
    final colour = offline ? t.accent.offline : t.accent.warn;

    return InkWell(
      onTap: onTap,
      borderRadius: t.radius.pillR,
      child: Container(
        padding:
            EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
        decoration: BoxDecoration(
          color: t.surface.raised,
          borderRadius: t.radius.pillR,
          border: Border.all(color: t.stroke.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
            ),
            SizedBox(width: t.space.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(
                problem.device.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.bodySmallStyle.copyWith(
                    fontWeight: FontWeight.w600, color: t.surface.onBase),
              ),
            ),
            SizedBox(width: t.space.sm),
            Text(
              problem.reason,
              style: t.text.captionStyle.copyWith(
                  color: t.surface.onBaseMuted,
                  fontFeatures: t.numericFontFeatures),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line that says how the house is, before any detail.
class _HouseHeader extends ConsumerWidget {
  const _HouseHeader({required this.devices, required this.problems});

  final List<DeviceState> devices;
  final int problems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final on = devices.where(isOn).length;
    final offline = devices.where((d) => !d.available).length;
    final modes = ref.watch(modesProvider).value ?? const [];
    final active = modes
        .where((m) => m.on)
        .map((m) => humanize(m.id.replaceFirst('mode_', '')))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Home',
          style: TextStyle(
              fontSize: t.text.scaled(30),
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              color: t.surface.onBase),
        ),
        SizedBox(height: t.space.xs),
        Wrap(
          spacing: t.space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Stat(label: on == 1 ? '1 thing on' : '$on things on', lit: on > 0),
            _dot(t),
            _Stat(label: '${devices.length} devices'),
            if (offline > 0) ...[
              _dot(t),
              _Stat(label: '$offline offline', warn: true),
            ],
            // No longer a link: the attention card directly below names each
            // device and is the door. Two doors to the same room, one of them a
            // dotted underline, is worse than one.
            if (problems > 0) ...[
              _dot(t),
              _Stat(label: '$problems need attention', warn: true),
            ],
            for (final m in active) ...[
              _dot(t),
              _Stat(label: m, lit: true),
            ],
            _dot(t),
            const _ActiveSortToggle(),
          ],
        ),
      ],
    );
  }

  Widget _dot(HcTokens t) => Text('·',
      style: TextStyle(color: t.surface.onBaseMuted.withValues(alpha: 0.5)));
}

/// Turns active-first sorting on and off, in the line that describes the house.
///
/// It belongs here rather than in a settings page because it is about *this*
/// view right now: you notice you want it the moment a room re-orders under
/// your hand, and a preference you have to go looking for is one you will not
/// find at that moment.
class _ActiveSortToggle extends ConsumerWidget {
  const _ActiveSortToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final on = ref.watch(activeSortProvider);

    return Tooltip(
      message: on
          ? 'On devices lead each room. Rooms re-order as things switch.'
          : 'Rooms stay in A–Z order.',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => ref.read(activeSortProvider.notifier).toggle(),
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? Icons.bolt_rounded : Icons.sort_by_alpha_rounded,
                size: 13,
                color: on ? t.accent.active : t.surface.onBaseMuted,
              ),
              SizedBox(width: t.space.xs),
              Text(
                on ? 'Active first' : 'A–Z',
                style: t.text.bodyStyle.copyWith(
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                    color: on ? t.accent.active : t.surface.onBaseMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    this.lit = false,
    this.warn = false,
  });

  final String label;
  final bool lit;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final colour = warn
        ? t.accent.warn
        : lit
            ? t.accent.active
            : t.surface.onBaseMuted;
    return Text(
      label,
      style: t.text.bodyStyle.copyWith(
          fontWeight: lit || warn ? FontWeight.w600 : FontWeight.w400,
          color: colour,
          fontFeatures: t.numericFontFeatures),
    );
  }
}

/// Opens the list behind the "N need attention" count — the offline and
/// low-battery devices, each a tap away from its own detail.
void _showNeedsAttention(BuildContext context, List<DeviceState> devices) {
  showHcSheet(
    context,
    title: 'Needs attention',
    child: _NeedsAttentionSheet(problems: problemsIn(devices)),
  );
}

class _NeedsAttentionSheet extends StatelessWidget {
  const _NeedsAttentionSheet({required this.problems});

  final List<DeviceProblem> problems;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HcSheetHeader(
          title: 'Needs attention',
          subtitle: problems.isEmpty
              ? 'Everything looks healthy'
              : '${problems.length} ${problems.length == 1 ? 'device' : 'devices'}',
        ),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(t.space.md, 0, t.space.md, t.space.lg),
            itemCount: problems.length,
            separatorBuilder: (_, __) => SizedBox(height: t.space.xs),
            itemBuilder: (context, i) {
              final p = problems[i];
              final offline = p.reason == 'offline';
              final colour = offline ? t.accent.offline : t.accent.warn;
              final area = humanize(p.device.effectiveArea ?? '');

              return InkWell(
                borderRadius: t.radius.mdR,
                onTap: () {
                  // Close this sheet first, then open the device's own — two
                  // stacked sheets read as clutter.
                  Navigator.of(context).maybePop();
                  showDeviceSheet(context, p.device.id);
                },
                child: Container(
                  padding: EdgeInsets.all(t.space.md),
                  decoration: BoxDecoration(
                    color: t.surface.raised,
                    borderRadius: t.radius.mdR,
                    border: Border.all(color: t.stroke.hairline),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        offline
                            ? HcIcons.warning
                            : facetOf(p.device, p.device.schema).icon,
                        size: 18,
                        color: colour,
                      ),
                      SizedBox(width: t.space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.device.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.text.subtitleStyle.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: t.surface.onBase),
                            ),
                            Text(
                              area.isEmpty ? p.reason : '$area · ${p.reason}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.text.bodySmallStyle.copyWith(
                                  color: colour,
                                  fontFeatures: t.numericFontFeatures),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Room extends StatelessWidget {
  const _Room({
    required this.room,
    required this.activeFirst,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.onActivate,
    this.onRename,
    this.onAssignRooms,
  });

  final DeviceGroupResult room;

  /// Whether the on ones lead. See [activeSortProvider] for why this is a
  /// choice and not a constant.
  final bool activeFirst;

  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final ValueChanged<DeviceState> onActivate;

  /// Rename this room in English. Null for the "No room" bucket, which is not an
  /// area and cannot be renamed.
  final VoidCallback? onRename;

  /// Only the "No room" bucket has this: the action that empties it. A room you
  /// cannot get devices out of is a list of problems, not a room.
  final VoidCallback? onAssignRooms;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    // A room is a container of rows now, not a loose grid: an icon and a name
    // on the left, its control or reading on the right, hairlines between. It
    // scans like the list it is, and the card's border is the room separation
    // the grid never had.
    final scenes = room.devices
        .where((d) => facetOf(d, d.schema) == DeviceFacet.scene)
        .toList();
    final devices = room.devices
        .where((d) => facetOf(d, d.schema) != DeviceFacet.scene)
        .toList();

    // Things you operate lead — the on ones first — then the sensors you read.
    final actuators =
        devices.where((d) => facetOf(d, d.schema).isActuator).toList()
          ..sort((a, b) {
            if (activeFirst) {
              final byOn = (isOn(b) ? 1 : 0).compareTo(isOn(a) ? 1 : 0);
              if (byOn != 0) return byOn;
            }
            return a.displayName.compareTo(b.displayName);
          });
    // A remote has no state worth a row of its own: a Pico reports only which
    // button last fired, and a keypad's LEDs mean nothing without the plate.
    // Eleven of them across the house were eleven lines saying nothing, so they
    // fold to one — still one tap from where they were.
    final buttons = devices
        .where((d) => facetOf(d, d.schema) == DeviceFacet.button)
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final sensors = devices
        .where((d) =>
            !facetOf(d, d.schema).isActuator &&
            facetOf(d, d.schema) != DeviceFacet.button)
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    // A thermostat is its own thing: a full dial when the room is just it, a
    // compact gauge when it shares the room. It never renders as a plain row.
    final climate = actuators
        .where((d) => facetOf(d, d.schema) == DeviceFacet.climate)
        .toList();
    // A speaker earns its space only when it has something to SHOW — then it
    // blooms into a now-playing card. Otherwise it stays a row.
    //
    // The condition used to be `playbackState == 'playing'`, which a Roku
    // breaks: neither the tuner nor an HDMI input goes through
    // `query/media-player`, so hc-roku reports `playing` for both (its own
    // comment says as much — the alternative is calling a TV showing a games
    // console "stopped"). A TV on HDMI therefore bloomed into a now-playing
    // card with no title, no artwork and no duration — and, because the card
    // carries no tap target, no way to open the device at all. Office TV was
    // unopenable while the idle soundbar beside it was fine.
    final playingMedia = actuators
        .where((d) =>
            facetOf(d, d.schema) == DeviceFacet.mediaPlayer &&
            d.playbackState == 'playing' &&
            ((d.cleanTitle ?? '').isNotEmpty || d.hasArtwork))
        .toList();
    final controls = actuators
        .where((d) =>
            facetOf(d, d.schema) != DeviceFacet.climate &&
            !playingMedia.contains(d))
        .toList();
    // Sensors leave the row list entirely: a reading is not a control, and
    // giving it the same 44px row made a room of eight sensors scan as a room
    // of eight things you could operate. They become a chip strip below.
    final entities = controls;
    final on = controls.where(isOn).length;

    // Not for the "No room" bucket: those devices share no room, so a
    // temperature or an "occupied" from one of them says nothing about the
    // others. `onAssignRooms` is the bucket's tell.
    final summary = onAssignRooms == null ? roomSummary(room.devices) : null;

    Widget divider() =>
        Divider(height: 1, thickness: 1, color: t.stroke.hairline);

    return Padding(
      padding: EdgeInsets.only(bottom: t.space.md),
      child: Container(
        decoration: BoxDecoration(
          color: t.surface.raised,
          borderRadius: t.radius.lgR,
          border: Border.all(color: t.stroke.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The header is also the fold — tap it to collapse the room to this
            // one line without hiding it for good.
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggleCollapse,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      t.space.md, t.space.sm + 2, t.space.md, t.space.sm + 2),
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: collapsed ? -0.25 : 0,
                        duration: t.motion.d(t.motion.fast),
                        child: Icon(HcIcons.caretDown,
                            size: 12, color: t.surface.onBaseMuted),
                      ),
                      SizedBox(width: t.space.sm),
                      Expanded(
                        child: Text(
                          // Normalised English, never the raw `family_room`.
                          humanize(room.key),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.text.bodyStyle.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.1,
                              color: t.surface.onBase),
                        ),
                      ),
                      if (onRename != null)
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                              width: 28, height: 28),
                          iconSize: 13,
                          color: t.surface.onBaseMuted,
                          tooltip: 'Rename room',
                          icon: const Icon(HcIcons.pencil),
                          onPressed: onRename,
                        ),
                      if (onAssignRooms != null)
                        Padding(
                          padding: EdgeInsets.only(right: t.space.sm),
                          child: GestureDetector(
                            onTap: onAssignRooms,
                            behavior: HitTestBehavior.opaque,
                            child: Text(
                              'Assign rooms',
                              style: t.text.captionStyle.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: t.accent.primary),
                            ),
                          ),
                        ),
                      SizedBox(width: t.space.sm),
                      // The room's own summary, so a COLLAPSED room still
                      // answers "is this room alright?". A count of what is on
                      // says nothing about the lock left open or how warm it is
                      // in there, which are the two things worth folding a room
                      // away without losing.
                      if (summary case final extra?) ...[
                        Text(extra.text,
                            style: t.text.captionStyle.copyWith(
                                fontWeight: extra.warn
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: extra.warn
                                    ? t.accent.warn
                                    : t.surface.onBaseMuted,
                                fontFeatures: t.numericFontFeatures)),
                        Text(' · ',
                            style: t.text.captionStyle.copyWith(
                                color: t.surface.onBaseMuted
                                    .withValues(alpha: 0.5))),
                      ],
                      if (controls.isNotEmpty)
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: '$on',
                              style: TextStyle(
                                color: on > 0
                                    ? t.accent.active
                                    : t.surface.onBaseMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: ' of ${controls.length} on'),
                          ]),
                          style: t.text.captionStyle.copyWith(
                              color: t.surface.onBaseMuted,
                              fontFeatures: t.numericFontFeatures),
                        )
                      else
                        Text(
                          room.devices.length == 1
                              ? '1 device'
                              : '${room.devices.length} devices',
                          style: t.text.captionStyle.copyWith(
                              color: t.surface.onBaseMuted,
                              fontFeatures: t.numericFontFeatures),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (!collapsed) ...[
              for (final c in climate) ...[
                divider(),
                HomeThermostat(device: c),
              ],
              for (final m in playingMedia) ...[
                divider(),
                Padding(
                  padding: EdgeInsets.all(t.space.sm),
                  child: HomeMediaCard(device: m),
                ),
              ],
              for (final d in entities) ...[
                divider(),
                HomeEntityRow(device: d),
              ],
              if (sensors.isNotEmpty) ...[
                divider(),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      t.space.md, t.space.sm + 2, t.space.md, t.space.md),
                  child: Wrap(
                    spacing: t.space.sm,
                    runSpacing: t.space.sm,
                    children: [
                      for (final d in sensors)
                        HcSensorChip(
                          device: d,
                          onTap: () => showDeviceSheet(context, d.id),
                        ),
                    ],
                  ),
                ),
              ],
              if (buttons.isNotEmpty) ...[
                divider(),
                _RemotesFold(devices: buttons),
              ],
              if (scenes.isNotEmpty) ...[
                divider(),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      t.space.md, t.space.sm + 2, t.space.md, t.space.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SCENES',
                        style: t.text.overlineStyle.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.3,
                            color: t.surface.onBaseMuted),
                      ),
                      SizedBox(height: t.space.sm),
                      _SceneChips(scenes: scenes, onActivate: onActivate),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// The room's remotes, keypads and Picos behind one line.
///
/// They are real devices and they belong to the room, but none of them has a
/// state a row can usefully show — a Pico reports which button last fired and
/// nothing else. Eleven of them across the house were eleven lines of noise
/// above the lamps people actually came for.
class _RemotesFold extends StatefulWidget {
  const _RemotesFold({required this.devices});

  final List<DeviceState> devices;

  @override
  State<_RemotesFold> createState() => _RemotesFoldState();
}

class _RemotesFoldState extends State<_RemotesFold> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final n = widget.devices.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: t.space.md, vertical: t.space.sm + 1),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _open ? 0 : -0.25,
                  duration: t.motion.d(t.motion.fast),
                  child: Icon(HcIcons.caretDown,
                      size: 11, color: t.surface.onBaseMuted),
                ),
                SizedBox(width: t.space.sm),
                Text(
                  n == 1 ? '1 remote or keypad' : '$n remotes & keypads',
                  style: t.text.bodySmallStyle
                      .copyWith(color: t.surface.onBaseMuted),
                ),
              ],
            ),
          ),
        ),
        if (_open)
          for (final d in widget.devices)
            Padding(
              padding: EdgeInsets.only(left: t.space.md),
              child: HomeEntityRow(device: d),
            ),
      ],
    );
  }
}

/// A room's scenes, capped so a Hue room's twenty presets don't become a wall.
///
/// Shows the first few and rolls the rest up behind a "+N more" — a family room
/// with a dozen scenes was three rows of chips that buried the two lamps above
/// them.
class _SceneChips extends StatefulWidget {
  const _SceneChips({required this.scenes, required this.onActivate});

  final List<DeviceState> scenes;
  final ValueChanged<DeviceState> onActivate;

  @override
  State<_SceneChips> createState() => _SceneChipsState();
}

class _SceneChipsState extends State<_SceneChips> {
  static const _cap = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final all = widget.scenes;
    final shown = _expanded ? all : all.take(_cap).toList();
    final hidden = all.length - shown.length;

    return Wrap(
      spacing: t.space.xs,
      runSpacing: t.space.xs,
      children: [
        for (final s in shown)
          _SceneChip(scene: s, onTap: () => widget.onActivate(s)),
        if (hidden > 0)
          _MoreChip(
            label: '+$hidden more',
            onTap: () => setState(() => _expanded = true),
          )
        else if (_expanded && all.length > _cap)
          _MoreChip(
            label: 'Less',
            onTap: () => setState(() => _expanded = false),
          ),
      ],
    );
  }
}

/// The "+N more" / "Less" chip that rolls the scene overflow up.
class _MoreChip extends StatelessWidget {
  const _MoreChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: t.radius.lgR,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: t.space.sm + 2, vertical: t.space.xs + 1),
        decoration: BoxDecoration(
          borderRadius: t.radius.lgR,
          border: Border.all(color: t.stroke.hairline),
        ),
        child: Text(
          label,
          style: t.text.bodySmallStyle.copyWith(
              fontWeight: FontWeight.w600, color: t.surface.onBaseMuted),
        ),
      ),
    );
  }
}

/// A scene, as the button it is.
class _SceneChip extends StatelessWidget {
  const _SceneChip({required this.scene, required this.onTap});

  final DeviceState scene;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: t.radius.lgR,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: t.space.sm + 2, vertical: t.space.xs + 1),
        decoration: BoxDecoration(
          color: t.surface.raised,
          borderRadius: t.radius.lgR,
          border: Border.all(color: t.stroke.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HcIcons.forFacet(DeviceFacet.scene),
                size: 13, color: t.surface.onBaseMuted),
            SizedBox(width: t.space.xs),
            Text(
              scene.displayName,
              style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
            ),
          ],
        ),
      ),
    );
  }
}

/// One room, while you are arranging the house.
///
/// Deliberately NOT the room itself with its tiles: dragging a 200px-tall grid
/// of live devices around is fiddly and slow, and you cannot see the shape of
/// the house while you do it. Arranging is about ORDER, so it shows order.
/// The ghost that follows the cursor while a card is being dragged — a compact,
/// elevated pill naming what you picked up. The whole card can't be the feedback:
/// in the drag overlay it has no bounded height, so its column fails to lay out
/// and nothing paints — which is why the drag had no visible mirror at all.
class _DragChip extends StatelessWidget {
  const _DragChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        padding:
            EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
        decoration: BoxDecoration(
          color: t.surface.raised,
          borderRadius: t.radius.mdR,
          border: Border.all(color: t.accent.active, width: 1.5),
          boxShadow: t.elevation.overlay,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HcIcons.grip, size: 14, color: t.accent.active),
            SizedBox(width: t.space.sm),
            Text(
              label,
              style: t.text.subtitleStyle.copyWith(
                  fontWeight: FontWeight.w700, color: t.surface.onBase),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrangeRow extends StatelessWidget {
  const _ArrangeRow({
    super.key,
    required this.index,
    required this.label,
    required this.count,
    required this.hidden,
    required this.onToggleHidden,
    this.detail,
  });

  final int index;
  final String label;
  final int count;
  final bool hidden;
  final VoidCallback onToggleHidden;

  /// Shown instead of the device count for cards that are not rooms (a camera).
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm),
      child: AnimatedOpacity(
        opacity: hidden ? 0.4 : 1,
        duration: t.motion.fast,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: t.space.md, vertical: t.space.sm + 2),
          decoration: BoxDecoration(
            color: t.surface.raised,
            borderRadius: t.radius.mdR,
            border: Border.all(color: t.stroke.hairline),
          ),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Icon(HcIcons.grip,
                      size: 15, color: t.surface.onBaseMuted),
                ),
              ),
              SizedBox(width: t.space.md),
              Expanded(
                child: Text(
                  label,
                  style: t.text.subtitleStyle.copyWith(
                      fontWeight: FontWeight.w600, color: t.surface.onBase),
                ),
              ),
              Text(
                detail ?? (count == 1 ? '1 device' : '$count devices'),
                style: t.text.bodySmallStyle.copyWith(
                    color: t.surface.onBaseMuted,
                    fontFeatures: t.numericFontFeatures),
              ),
              SizedBox(width: t.space.sm),
              HcIconButton(
                icon: hidden ? HcIcons.eyeSlash : HcIcons.eye,
                tooltip: hidden ? 'Show on Home' : 'Hide from Home',
                onPressed: onToggleHidden,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return ListView(
      padding: EdgeInsets.all(t.space.lg),
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: EdgeInsets.only(bottom: t.space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 12,
                  decoration: BoxDecoration(
                    color: t.surface.raised,
                    borderRadius: t.radius.smR,
                  ),
                ),
                SizedBox(height: t.space.sm),
                Wrap(
                  spacing: t.space.sm,
                  runSpacing: t.space.sm,
                  children: [
                    for (var j = 0; j < 4; j++)
                      Container(
                        width: 200,
                        height: 84,
                        decoration: BoxDecoration(
                          color: t.surface.raised,
                          borderRadius: t.radius.mdR,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
