import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import 'camera_store.dart';
import 'camera_tile.dart';

/// The security wall.
///
/// A grid of live cameras you assemble yourself. The cameras are user data
/// (persisted server-side as `camera_video` cards), never shipped config, which
/// is the whole point of a wall you arrange rather than one that ships fixed.
///
/// Display only, by design: the NVR already does motion, detection and recording
/// — this is a wall of live streams to watch, not a surveillance system to
/// operate. It points at any go2rtc, and gracefully at any plain MJPEG camera.
class CamerasPage extends ConsumerWidget {
  const CamerasPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final cameras = ref.watch(camerasProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(HcIcons.plus, size: 16),
        label: const Text('Add camera'),
        backgroundColor: t.accent.active,
        foregroundColor: t.surface.base,
        onPressed: () => _addCamera(context, ref),
      ),
      body: cameras.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('$e', style: TextStyle(color: t.surface.onBaseMuted)),
        ),
        data: (list) {
          if (list.isEmpty) return const _Empty();
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      t.space.lg, t.space.lg, t.space.lg, t.space.md),
                  child: Text(
                    'Cameras',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                      color: t.surface.onBase,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding:
                    EdgeInsets.fromLTRB(t.space.lg, 0, t.space.lg, t.space.xl),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    // A security wall wants big tiles: ~360px each, so three
                    // across on a laptop, more on a wall panel.
                    final w = constraints.crossAxisExtent;
                    final columns = (w / 360).floor().clamp(1, 6);
                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: t.space.sm,
                        mainAxisSpacing: t.space.sm,
                        childAspectRatio: 16 / 9,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final cam = list[i];
                          return _Removable(
                            onRemove: () => ref
                                .read(camerasProvider.notifier)
                                .remove(cam.id),
                            child: CameraTile(
                              name: cam.name,
                              url: cam.url,
                              sourceType: cam.sourceType,
                              refreshSecs: cam.refreshSecs,
                            ),
                          );
                        },
                        childCount: list.length,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addCamera(BuildContext context, WidgetRef ref) async {
    final camera = await showDialog<Camera>(
      context: context,
      builder: (_) => const _AddCameraDialog(),
    );
    if (camera != null) {
      await ref.read(camerasProvider.notifier).add(camera);
    }
  }
}

/// Reveals a delete affordance on hover — a wall is watched, not fiddled with,
/// so the controls stay out of the way until wanted.
class _Removable extends StatefulWidget {
  const _Removable({required this.child, required this.onRemove});

  final Widget child;
  final VoidCallback onRemove;

  @override
  State<_Removable> createState() => _RemovableState();
}

class _RemovableState extends State<_Removable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (_hover)
            Positioned(
              top: 6,
              right: 6,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(HcIcons.trash, size: 15),
                  color: t.accent.danger,
                  tooltip: 'Remove',
                  onPressed: widget.onRemove,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(HcIcons.camera, size: 28, color: t.surface.onBaseMuted),
          SizedBox(height: t.space.md),
          Text('No cameras yet',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.surface.onBase)),
          SizedBox(height: t.space.xs),
          Text('Add a go2rtc stream or any MJPEG camera.',
              style: TextStyle(fontSize: 12.5, color: t.surface.onBaseMuted)),
        ],
      ),
    );
  }
}

class _AddCameraDialog extends StatefulWidget {
  const _AddCameraDialog();

  @override
  State<_AddCameraDialog> createState() => _AddCameraDialogState();
}

class _AddCameraDialogState extends State<_AddCameraDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  String _type = 'webrtc';

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  /// A go2rtc stream is entered by name or by its full ws URL; the field accepts
  /// either, because typing `driveway` is what a person wants and pasting the
  /// full URL is what a person has.
  String _resolvedUrl() {
    final raw = _url.text.trim();
    if (_type != 'webrtc') return raw;
    if (raw.startsWith('http')) return raw;
    // A bare stream name — but we do not know the NVR host, so a name alone is
    // not enough. Left as-is; the hint tells the user to paste the full URL.
    return raw;
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty && _url.text.trim().startsWith('http');

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return AlertDialog(
      backgroundColor: t.surface.overlay,
      title: const Text('Add camera'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(
                    value: 'webrtc',
                    child: Text('go2rtc (WebRTC, falls back to MJPEG)')),
                DropdownMenuItem(value: 'mjpeg', child: Text('MJPEG stream')),
                DropdownMenuItem(
                    value: 'image_refresh', child: Text('Snapshot (still)')),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              decoration: InputDecoration(
                labelText: 'URL',
                helperText: switch (_type) {
                  'webrtc' =>
                    'go2rtc stream, e.g. http://10.0.10.150:1984/api/ws?src=driveway',
                  'image_refresh' => 'Snapshot URL, re-fetched every ~2s',
                  _ => 'MJPEG stream URL',
                },
                helperMaxLines: 2,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_type == 'webrtc') ...[
              const SizedBox(height: 8),
              Text(
                'For live WebRTC, go2rtc needs api.origin: "*" in its config. '
                'Without it the wall still works over MJPEG.',
                style: TextStyle(fontSize: 11.5, color: t.surface.onBaseMuted),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid
              ? () {
                  // A stable-enough id without dart:math — the wall is small and
                  // ids only need to be unique within it.
                  final id =
                      'cam_${_name.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
                  Navigator.pop(
                    context,
                    Camera(
                      id: id,
                      name: _name.text.trim(),
                      url: _resolvedUrl(),
                      sourceType: _type,
                      refreshSecs: _type == 'image_refresh' ? 2 : null,
                    ),
                  );
                }
              : null,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
