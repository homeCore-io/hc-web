import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/devices_provider.dart';
import '../../core/providers/modes_provider.dart';
import '../../design/components/hc_tile.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../devices/device_query.dart';
import '../devices/device_sheet.dart';
import '../../core/providers/dashboards_provider.dart';
import '../../design/components/hc_controls.dart';
import 'home_arrangement.dart';

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
            final rooms = _roomKeys(devices);
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

  static List<String> _roomKeys(List<DeviceState> devices) => runQuery(
        devices,
        const DeviceQuery(
            group: DeviceGroup.room, sort: DeviceSort.activeFirst),
      ).map((g) => g.key).toList();

  Future<void> _save() async {
    final draft = _draft;
    final dashboard = ref.read(defaultDashboardProvider);
    final devices = ref.read(devicesProvider).valueOrNull ?? const [];
    if (draft == null || dashboard == null) {
      setState(() => _draft = null);
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(dashboardsProvider.notifier).updateDashboard(
            draft.toDashboard(dashboard, _roomKeys(devices)),
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

class _House extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final notifier = ref.read(devicesProvider.notifier);

    // Rooms, not "sections". The house already has a structure; inventing a
    // second one in a dashboard document was the original mistake.
    final groups = runQuery(
      devices,
      const DeviceQuery(group: DeviceGroup.room, sort: DeviceSort.activeFirst),
    );
    final byKey = {for (final g in groups) g.key: g};

    // While arranging you see every room INCLUDING the hidden ones, or you could
    // never bring one back.
    final keys =
        arranging ? arrangement.all(byKey.keys) : arrangement.apply(byKey.keys);
    final rooms = [for (final k in keys) byKey[k]!];
    final problems = problemsIn(devices);

    if (arranging) {
      return ReorderableListView.builder(
        padding: EdgeInsets.fromLTRB(t.space.lg, t.space.lg, t.space.lg, 0),
        itemCount: rooms.length,
        onReorderItem: onReorder,
        itemBuilder: (context, i) {
          final key = rooms[i].key;
          final hidden = arrangement.hidden.contains(key);
          return _ArrangeRow(
            key: ValueKey(key),
            index: i,
            room: key,
            count: rooms[i].devices.length,
            hidden: hidden,
            onToggleHidden: () => onToggleHidden(key),
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
        for (final room in rooms)
          SliverToBoxAdapter(
            child: _Room(
              room: room,
              // A sheet OVER the house, not a route away from it. You look, you
              // act, you dismiss — and the house is still lit where it was.
              onTap: (d) => showDeviceSheet(context, d.id),
              onToggle: (d) => notifier.command(d.id, {'on': !isOn(d)}),
              // Scene duality: a plugin scene-device is activated by a
              // plugin-specific payload. Lutron wants {"activate": true};
              // Hue wants {"action": "activate_scene"}. There is no single
              // command, so pick by who owns the device.
              onActivate: (d) => notifier.command(
                d.id,
                d.pluginId.contains('hue')
                    ? {'action': 'activate_scene'}
                    : {'activate': true},
              ),
              onLevel: (d, v) =>
                  notifier.command(d.id, {'on': true, 'brightness': v.round()}),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: t.space.xl)),
      ],
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
    final modes = ref.watch(modesProvider).valueOrNull ?? const [];
    final active = modes
        .where((m) => m.on)
        .map((m) => m.id.replaceFirst('mode_', ''))
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
              _Stat(label: '$problems need attention', warn: true),
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
  const _Stat({required this.label, this.lit = false, this.warn = false});

  final String label;
  final bool lit;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: lit || warn ? FontWeight.w600 : FontWeight.w400,
        color: warn
            ? t.accent.warn
            : lit
                ? t.accent.active
                : t.surface.onBaseMuted,
        fontFeatures: t.numericFontFeatures,
      ),
    );
  }
}

class _Room extends StatelessWidget {
  const _Room({
    required this.room,
    required this.onTap,
    required this.onToggle,
    required this.onActivate,
    required this.onLevel,
  });

  final DeviceGroupResult room;
  final ValueChanged<DeviceState> onTap;
  final ValueChanged<DeviceState> onToggle;
  final ValueChanged<DeviceState> onActivate;
  final void Function(DeviceState, double) onLevel;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    // Scenes are not devices, even though a plugin registers them as one (Hue
    // publishes each scene as `device_type: "scene"`). Rendering them as tiles
    // put twenty of them — Arctic aurora, Bright, Concentrate, Dimmed… — in the
    // family room and buried the two lamps that actually live there. A scene is
    // a button you press, so it gets a chip, not a tile.
    final scenes = room.devices
        .where((d) => facetOf(d, d.schema) == DeviceFacet.scene)
        .toList();
    final things = room.devices
        .where((d) => facetOf(d, d.schema) != DeviceFacet.scene)
        .toList();

    final actuators =
        things.where((d) => facetOf(d, d.schema).isActuator).toList();
    final on = actuators.where(isOn).length;

    return Padding(
      padding: EdgeInsets.fromLTRB(t.space.lg, 0, t.space.lg, t.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                room.key.replaceAll('_', ' '),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: t.accent.primary,
                ),
              ),
              SizedBox(width: t.space.sm),
              if (actuators.isNotEmpty)
                Text(
                  '$on of ${actuators.length} on',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: t.surface.onBaseMuted,
                    fontFeatures: t.numericFontFeatures,
                  ),
                ),
            ],
          ),
          SizedBox(height: t.space.sm),
          LayoutBuilder(
            builder: (context, c) {
              // Tiles size themselves to the space, so the same surface is a
              // phone, a laptop and a wall panel without a breakpoint document
              // describing all three.
              const target = 210.0;
              final columns = (c.maxWidth / target).floor().clamp(1, 8);
              final width = (c.maxWidth - (columns - 1) * t.space.sm) / columns;

              return Wrap(
                spacing: t.space.sm,
                runSpacing: t.space.sm,
                children: [
                  for (final d in things)
                    SizedBox(
                      width: width,
                      height: 84,
                      child: HcTile(
                        device: d,
                        onTap: () => onTap(d),
                        onToggle: facetOf(d, d.schema).isActuator
                            ? () => onToggle(d)
                            : null,
                        onLevel: (v) => onLevel(d, v),
                      ),
                    ),
                ],
              );
            },
          ),
          if (scenes.isNotEmpty) ...[
            SizedBox(height: t.space.sm),
            Wrap(
              spacing: t.space.xs,
              runSpacing: t.space.xs,
              children: [
                for (final s in scenes)
                  _SceneChip(scene: s, onTap: () => onActivate(s)),
              ],
            ),
          ],
        ],
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
    required this.room,
    required this.count,
    required this.hidden,
    required this.onToggleHidden,
  });

  final int index;
  final String room;
  final int count;
  final bool hidden;
  final VoidCallback onToggleHidden;

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
                  room.replaceAll('_', ' '),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.surface.onBase,
                  ),
                ),
              ),
              Text(
                count == 1 ? '1 device' : '$count devices',
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
