import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../cameras/camera_store.dart';
import '../cameras/camera_tile.dart';

/// The cameras, as their own area on the house.
///
/// Cameras are not devices — they are go2rtc streams the user curates — so they
/// get their own card rather than a room. It reads the same wall the Cameras
/// page manages ([camerasProvider]), so a camera you add there shows here too,
/// and it sits in the masonry like any room card: collapsible, movable, live.
class HomeCamerasCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => context.go('/cameras'),
                          child: Text('Manage',
                              style: TextStyle(
                                  fontSize: 12, color: t.accent.active)),
                        ),
                      ),
                      SizedBox(width: t.space.sm),
                      Text('${cameras.length} live',
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
                child: LayoutBuilder(builder: (context, c) {
                  const gap = 8.0;
                  // Two up, but a single camera gets the full width.
                  final cols = cameras.length == 1 ? 1 : 2;
                  final w = (c.maxWidth - (cols - 1) * gap) / cols;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final cam in cameras)
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
}
