import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../cameras/camera_store.dart';
import '../cameras/camera_tile.dart';

/// The cameras, as their own area on the house.
///
/// Cameras are not devices — they are go2rtc streams the user curates — so they
/// get their own card rather than a room. It reads the same wall the Cameras
/// page manages ([camerasProvider]), but shows only the subset the user has
/// picked for Home ([Camera.showOnHome]); the full wall stays on the Cameras
/// page. It sits in the masonry like any room card: collapsible, movable, live.
///
/// [cameras] is the FULL wall so the picker can offer every camera; the card
/// itself renders only the shown ones.
class HomeCamerasCard extends ConsumerWidget {
  const HomeCamerasCard({
    super.key,
    required this.cameras,
    required this.collapsed,
    required this.onToggleCollapse,
  });

  final List<Camera> cameras;
  final bool collapsed;
  final VoidCallback onToggleCollapse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final shown = cameras.where((c) => c.showOnHome).toList();

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
                        child: Text('Cameras',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.1,
                              color: t.surface.onBase,
                            )),
                      ),
                      // Curate which cameras Home shows — only offered when there
                      // is a real choice to make (more than one on the wall).
                      if (cameras.length > 1)
                        _HeaderAction(
                          label: 'Choose',
                          onTap: () => _pick(context, ref),
                        ),
                      _HeaderAction(
                        label: 'Manage',
                        onTap: () => context.go('/cameras'),
                      ),
                      SizedBox(width: t.space.sm),
                      Text(
                          cameras.length > shown.length
                              ? '${shown.length} of ${cameras.length}'
                              : '${shown.length} live',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: t.surface.onBaseMuted,
                              fontFeatures: t.numericFontFeatures)),
                    ],
                  ),
                ),
              ),
            ),
            if (!collapsed) ...[
              Divider(height: 1, thickness: 1, color: t.stroke.hairline),
              Padding(
                padding: EdgeInsets.all(t.space.sm + 2),
                child: shown.isEmpty
                    ? _EmptyHome(onChoose: () => _pick(context, ref))
                    : LayoutBuilder(builder: (context, c) {
                        const gap = 8.0;
                        // Two up, but a single camera gets the full width.
                        final cols = shown.length == 1 ? 1 : 2;
                        final w = (c.maxWidth - (cols - 1) * gap) / cols;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final cam in shown)
                              SizedBox(
                                width: w,
                                child: AspectRatio(
                                  aspectRatio: 16 / 10,
                                  child: GestureDetector(
                                    onTap: () => context.go('/cameras'),
                                    child: CameraTile(
                                      name: cam.name,
                                      url: cam.url,
                                      sourceType: cam.sourceType,
                                      refreshSecs: cam.refreshSecs,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: HcTokens.of(context).surface.overlay,
      showDragHandle: true,
      builder: (_) => const _HomeCameraPicker(),
    );
  }
}

/// A quiet accent-coloured text action in the card header.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(left: t.space.sm),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Text(label,
              style: TextStyle(fontSize: 12, color: t.accent.active)),
        ),
      ),
    );
  }
}

/// Shown when the wall has cameras but the user hid them all from Home — keeps
/// the entry point alive so the area never becomes a dead, un-curatable box.
class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.onChoose});
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.md),
      child: Column(
        children: [
          Icon(HcIcons.camera, size: 22, color: t.surface.onBaseMuted),
          SizedBox(height: t.space.sm),
          Text('No cameras on Home',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: t.surface.onBase)),
          const SizedBox(height: 2),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onChoose,
              child: Text('Choose cameras to show',
                  style: TextStyle(fontSize: 12, color: t.accent.active)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The picker: every wall camera with a switch for whether it appears on Home.
/// Toggling writes straight through to the wall, so the choice is saved as you
/// make it and the Home card updates live behind the sheet.
class _HomeCameraPicker extends ConsumerWidget {
  const _HomeCameraPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final cameras = ref.watch(camerasProvider).valueOrNull ?? const <Camera>[];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.space.lg, 0, t.space.lg, t.space.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Show on Home',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: t.surface.onBase,
                )),
            const SizedBox(height: 2),
            Text(
                'Pick the cameras you want to glance at from Home. The full '
                'wall stays on the Cameras page.',
                style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted)),
            SizedBox(height: t.space.sm),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final cam in cameras)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      activeThumbColor: t.accent.active,
                      title: Text(cam.name,
                          style:
                              TextStyle(fontSize: 14, color: t.surface.onBase)),
                      value: cam.showOnHome,
                      onChanged: (v) => ref
                          .read(camerasProvider.notifier)
                          .setShowOnHome(cam.id, v),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
