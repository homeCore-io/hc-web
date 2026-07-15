import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/modes_provider.dart';
import '../../core/text/humanize.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../devices/device_query.dart';
import '../devices/device_sheet.dart';
import '../../core/providers/areas_provider.dart';
import '../../core/providers/dashboards_provider.dart';
import '../../design/components/hc_controls.dart';
import '../../shell/hc_sheet.dart';
import '../cameras/camera_store.dart';
import 'home_arrangement.dart';
import 'home_camera_card.dart';
import 'home_color_light.dart';
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
                  style: TextStyle(color: t.surface.onBaseMuted, fontSize: 12)),
            ],
          ),
        ),
        data: (devices) => _House(
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
        ),
      ),
    );
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
    final devices = ref.read(devicesProvider).valueOrNull ?? const [];
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
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
                style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted),
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
  });

  final List<DeviceState> devices;
  final HomeArrangement arrangement;
  final bool arranging;
  final void Function(int from, int to) onReorder;
  final ValueChanged<String> onToggleHidden;

  @override
  ConsumerState<_House> createState() => _HouseState();
}

class _HouseState extends ConsumerState<_House> {
  /// Rooms the user has folded shut. Local and ephemeral on purpose: collapsing
  /// a room to see past it is a glance-time act, not a saved layout, and it must
  /// never fire a dashboard write on every tap. A room absent from this set is
  /// open — so a newly installed room is always visible, never folded by default.
  final Set<String> _collapsed = {};

  void _toggle(String key) => setState(() {
        _collapsed.contains(key) ? _collapsed.remove(key) : _collapsed.add(key);
      });

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final notifier = ref.read(devicesProvider.notifier);
    final devices = widget.devices;

    // Rooms, not "sections". The house already has a structure; inventing a
    // second one in a dashboard document was the original mistake.
    final groups = runQuery(
      devices,
      const DeviceQuery(group: DeviceGroup.room, sort: DeviceSort.activeFirst),
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
                      collapsed: _collapsed.contains(key),
                      onToggleCollapse: () => _toggle(key),
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

                // Pack a run of single-column cards (rooms + small cameras) into
                // balanced columns.
                Widget masonry(List<String> ks) {
                  final columns = List.generate(colCount, (_) => <Widget>[]);
                  final heights = List<double>.filled(colCount, 0);
                  for (final key in ks) {
                    var shortest = 0;
                    for (var i = 1; i < colCount; i++) {
                      if (heights[i] < heights[shortest]) shortest = i;
                    }
                    final cam = camById[cameraIdFromKey(key) ?? ''];
                    if (cam != null) {
                      heights[shortest] += _collapsed.contains(key)
                          ? 48
                          : 46 + colW / (16 / 10) + 14;
                      columns[shortest].add(smallCamera(key, cam));
                    } else {
                      heights[shortest] += _estimateHeight(byKey[key]!);
                      columns[shortest].add(room(key));
                    }
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < colCount; i++) ...[
                        if (i > 0) SizedBox(width: t.space.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: columns[i],
                          ),
                        ),
                      ],
                    ],
                  );
                }

                // A large camera is a full-width hero, so it breaks the column
                // flow: small cards pack into a masonry band, a hero spans the
                // whole width, then packing resumes below it.
                final bands = <Widget>[];
                var band = <String>[];
                void flush() {
                  if (band.isNotEmpty) {
                    bands.add(masonry(band));
                    band = [];
                  }
                }

                for (final key in keys) {
                  final cam = camById[cameraIdFromKey(key) ?? ''];
                  if (cam != null && cam.homeLarge) {
                    flush();
                    bands.add(HomeCameraCard(
                      camera: cam,
                      large: true,
                      collapsed: _collapsed.contains(key),
                      onToggleCollapse: () => _toggle(key),
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
    final modes = ref.watch(modesProvider).valueOrNull ?? const [];
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
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            color: t.surface.onBase,
          ),
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
            if (problems > 0) ...[
              _dot(t),
              // A count is only useful if it takes you to the things it counts.
              // This is the one stat that is a door, not a fact.
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _showNeedsAttention(context, devices),
                  child: _Stat(
                    label: '$problems need attention',
                    warn: true,
                    link: true,
                  ),
                ),
              ),
            ],
            for (final m in active) ...[
              _dot(t),
              _Stat(label: m, lit: true),
            ],
          ],
        ),
      ],
    );
  }

  Widget _dot(HcTokens t) => Text('·',
      style: TextStyle(color: t.surface.onBaseMuted.withValues(alpha: 0.5)));
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    this.lit = false,
    this.warn = false,
    this.link = false,
  });

  final String label;
  final bool lit;
  final bool warn;

  /// A stat you can tap. A dotted underline says so without a button's weight.
  final bool link;

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
      style: TextStyle(
        fontSize: 13,
        fontWeight: lit || warn ? FontWeight.w600 : FontWeight.w400,
        color: colour,
        fontFeatures: t.numericFontFeatures,
        decoration: link ? TextDecoration.underline : null,
        decorationColor: link ? colour.withValues(alpha: 0.5) : null,
        decorationStyle: TextDecorationStyle.dotted,
      ),
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
              final area = humanize(p.device.area ?? '');

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
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: t.surface.onBase,
                              ),
                            ),
                            Text(
                              area.isEmpty ? p.reason : '$area · ${p.reason}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: colour,
                                fontFeatures: t.numericFontFeatures,
                              ),
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
    required this.collapsed,
    required this.onToggleCollapse,
    required this.onActivate,
    this.onRename,
  });

  final DeviceGroupResult room;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final ValueChanged<DeviceState> onActivate;

  /// Rename this room in English. Null for the "No room" bucket, which is not an
  /// area and cannot be renamed.
  final VoidCallback? onRename;

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
            final byOn = (isOn(b) ? 1 : 0).compareTo(isOn(a) ? 1 : 0);
            return byOn != 0 ? byOn : a.displayName.compareTo(b.displayName);
          });
    final sensors = devices
        .where((d) => !facetOf(d, d.schema).isActuator)
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    // A thermostat is its own thing: a full dial when the room is just it, a
    // compact gauge when it shares the room. It never renders as a plain row.
    final climate = actuators
        .where((d) => facetOf(d, d.schema) == DeviceFacet.climate)
        .toList();
    // A speaker earns its space only when it is playing — then it blooms into a
    // now-playing card. Idle, it stays a row (with a play button).
    final playingMedia = actuators
        .where((d) =>
            facetOf(d, d.schema) == DeviceFacet.mediaPlayer &&
            d.playbackState == 'playing')
        .toList();
    final controls = actuators
        .where((d) =>
            facetOf(d, d.schema) != DeviceFacet.climate &&
            !playingMedia.contains(d))
        .toList();
    final entities = [...controls, ...sensors];
    final on = controls.where(isOn).length;

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
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                            color: t.surface.onBase,
                          ),
                        ),
                      ),
                      if (onRename != null)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                              width: 28, height: 28),
                          iconSize: 13,
                          color: t.surface.onBaseMuted,
                          tooltip: 'Rename room',
                          icon: const Icon(HcIcons.pencil),
                          onPressed: onRename,
                        ),
                      SizedBox(width: t.space.sm),
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
                          style: TextStyle(
                            fontSize: 11.5,
                            color: t.surface.onBaseMuted,
                            fontFeatures: t.numericFontFeatures,
                          ),
                        )
                      else
                        Text(
                          room.devices.length == 1
                              ? '1 device'
                              : '${room.devices.length} devices',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: t.surface.onBaseMuted,
                            fontFeatures: t.numericFontFeatures,
                          ),
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
                if (facetOf(d, d.schema) == DeviceFacet.colorLight)
                  HomeColorLight(device: d)
                else
                  HomeEntityRow(device: d),
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
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.3,
                          color: t.surface.onBaseMuted,
                        ),
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
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: t.space.sm + 2, vertical: t.space.xs + 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.stroke.hairline),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: t.surface.onBaseMuted,
          ),
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
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: t.space.sm + 2, vertical: t.space.xs + 1),
        decoration: BoxDecoration(
          color: t.surface.raised,
          borderRadius: BorderRadius.circular(20),
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
              style: TextStyle(fontSize: 12, color: t.surface.onBase),
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
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.surface.onBase,
                  ),
                ),
              ),
              Text(
                detail ?? (count == 1 ? '1 device' : '$count devices'),
                style: TextStyle(
                  fontSize: 12,
                  color: t.surface.onBaseMuted,
                  fontFeatures: t.numericFontFeatures,
                ),
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
