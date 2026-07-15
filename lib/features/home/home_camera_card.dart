import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../cameras/camera_store.dart';
import '../cameras/camera_tile.dart';

/// A camera's arrangement key. Each Home camera is its own card now — it orders,
/// hides, resizes, and drags exactly like a room — so it needs a reserved key no
/// `area` can collide with, carrying the camera id so the card can be found.
const _kCamKeyPrefix = '__cam__';

String homeCameraKey(String id) => '$_kCamKeyPrefix$id';

/// The camera id inside a [homeCameraKey], or null for a room key.
String? cameraIdFromKey(String key) => key.startsWith(_kCamKeyPrefix)
    ? key.substring(_kCamKeyPrefix.length)
    : null;

/// One camera, as its own card on the house.
///
/// Cameras are not devices — they are go2rtc streams the user curates — so each
/// gets its own card rather than a device row. It sits in the masonry like any
/// room card: collapsible, movable, hideable, live. [large] makes it a
/// full-width hero (the user's "resize"); otherwise it is a single column.
class HomeCameraCard extends ConsumerWidget {
  const HomeCameraCard({
    super.key,
    required this.camera,
    required this.large,
    required this.collapsed,
    required this.onToggleCollapse,
  });

  final Camera camera;
  final bool large;
  final bool collapsed;
  final VoidCallback onToggleCollapse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);

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
                      t.space.md, t.space.sm + 2, t.space.sm, t.space.sm + 2),
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: collapsed ? -0.25 : 0,
                        duration: t.motion.d(t.motion.fast),
                        child: Icon(HcIcons.caretDown,
                            size: 12, color: t.surface.onBaseMuted),
                      ),
                      SizedBox(width: t.space.sm),
                      Icon(HcIcons.camera,
                          size: 14, color: t.surface.onBaseMuted),
                      SizedBox(width: t.space.xs + 2),
                      Expanded(
                        child: Text(camera.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.1,
                              color: t.surface.onBase,
                            )),
                      ),
                      // The resize: hero ⇄ compact. A single tap toggles it and
                      // saves, so the size you set is the size you come back to.
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                            width: 30, height: 30),
                        iconSize: 16,
                        color: t.surface.onBaseMuted,
                        tooltip: large ? 'Make small' : 'Make large',
                        icon: Icon(large
                            ? Icons.close_fullscreen
                            : Icons.open_in_full),
                        onPressed: () => ref
                            .read(camerasProvider.notifier)
                            .setHomeLarge(camera.id, !large),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!collapsed) ...[
              Divider(height: 1, thickness: 1, color: t.stroke.hairline),
              Padding(
                padding: EdgeInsets.all(t.space.sm + 2),
                child: _frame(
                  large: large,
                  child: GestureDetector(
                    onTap: () => context.go('/cameras'),
                    child: CameraTile(
                      name: camera.name,
                      url: camera.url,
                      sourceType: camera.sourceType,
                      refreshSecs: camera.refreshSecs,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A small camera fits its column at 16:10. A hero spans the whole board, so
  /// an aspect ratio would make it absurdly tall on a wide screen — it gets a
  /// fixed, generous height instead, and the stream fills it.
  Widget _frame({required bool large, required Widget child}) => large
      ? SizedBox(height: 400, width: double.infinity, child: child)
      : AspectRatio(aspectRatio: 16 / 10, child: child);
}
