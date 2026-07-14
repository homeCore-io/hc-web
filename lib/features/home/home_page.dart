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
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final devicesAsync = ref.watch(devicesProvider);

    return Scaffold(
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
        data: (devices) => _House(devices: devices),
      ),
    );
  }
}

class _House extends ConsumerWidget {
  const _House({required this.devices});

  final List<DeviceState> devices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final notifier = ref.read(devicesProvider.notifier);

    // Rooms, not "sections". The house already has a structure; inventing a
    // second one in a dashboard document was the original mistake.
    final rooms = runQuery(
      devices,
      const DeviceQuery(group: DeviceGroup.room, sort: DeviceSort.activeFirst),
    );
    final problems = problemsIn(devices);

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
