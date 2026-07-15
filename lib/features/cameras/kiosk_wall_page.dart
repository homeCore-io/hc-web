import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import 'camera_source.dart';
import 'camera_store.dart';
import 'wall_presentations.dart';

/// The camera wall as a device loads it — no app chrome, just cameras.
///
/// This is the URL you point Fully Kiosk at. It lives OUTSIDE the app shell (no
/// nav rail, no bars), so an 8-inch tablet mounted by the door shows the wall
/// edge to edge, and it is driven entirely by the query string so each device
/// gets the presentation that fits it without any per-device config:
///
///   /#/wall                         auto: spotlight on a small screen, grid on big
///   /#/wall?layout=spotlight        one live + tappable stills (the tablet)
///   /#/wall?layout=grid             every camera live (a big display)
///   /#/wall?layout=solo&cam=drive   one camera, full screen
///   /#/wall?cams=drive,garage       only these cameras, in this order
///   /#/wall?active=garage           which camera starts live
///
/// A camera is named by the `src` in its URL (its go2rtc stream name), so the
/// links stay readable and stable even though the camera's real id is a
/// timestamp.
class KioskWallPage extends ConsumerWidget {
  const KioskWallPage({super.key, required this.params});

  final Map<String, String> params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameras = ref.watch(camerasProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: cameras.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message('Cannot load cameras.\n$e'),
        data: (all) {
          final chosen = _select(all, params['cams']);
          if (chosen.isEmpty) {
            return const _Message('No cameras to show.');
          }

          var layout = wallLayoutFrom(params['layout']);
          // solo needs exactly one camera in focus.
          final soloId = params['cam'] ?? params['active'];
          if (layout == WallLayout.solo && soloId != null) {
            final one = _byName(chosen, soloId);
            if (one != null) {
              return WallView(
                cameras: [one],
                layout: WallLayout.solo,
              );
            }
          }

          return WallView(
            cameras: chosen,
            layout: layout,
            initialActiveId: _byName(chosen, params['active'])?.id,
          );
        },
      ),
    );
  }

  /// The chosen cameras, in the requested order, or all of them.
  List<Camera> _select(List<Camera> all, String? cams) {
    if (cams == null || cams.trim().isEmpty) return all;
    final wanted = cams.split(',').map((s) => s.trim()).toList();
    final out = <Camera>[];
    for (final name in wanted) {
      final cam = _byName(all, name);
      if (cam != null) out.add(cam);
    }
    return out;
  }

  /// Matches a camera by its go2rtc stream name (the `src`) or its display name,
  /// so a link can say `driveway` rather than `cam_1720999999`.
  Camera? _byName(List<Camera> cameras, String? name) {
    if (name == null) return null;
    final n = name.toLowerCase();
    for (final c in cameras) {
      final src = go2rtcStreamName(c.url)?.toLowerCase();
      if (src == n || c.name.toLowerCase() == n || c.id == name) return c;
    }
    return null;
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: HcTokens.of(context).surface.onBaseMuted),
        ),
      );
}
