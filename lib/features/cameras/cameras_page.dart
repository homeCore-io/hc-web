import 'package:flutter/material.dart';

import '../../core/web/browser_env.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../../shared/widgets/section_scaffold.dart';
import 'camera_source.dart';
import 'camera_store.dart';
import 'wall_presentations.dart';

/// The camera wall you manage — add cameras, remove them, preview the wall, and
/// copy the kiosk link a device should load.
///
/// The wall itself is presented by [WallView]; this page is the desk you build
/// it from. The cameras are user data (persisted server-side as `camera_video`
/// cards), never shipped config — the whole point of a wall you assemble.
///
/// Display only, by design: the NVR already does motion, detection and
/// recording. This is a wall of live streams to watch, not a system to operate.
class CamerasPage extends ConsumerStatefulWidget {
  const CamerasPage({super.key});

  @override
  ConsumerState<CamerasPage> createState() => _CamerasPageState();
}

class _CamerasPageState extends ConsumerState<CamerasPage> {
  WallLayout _preview = WallLayout.spotlight;
  StripPosition _strip = StripPosition.bottom;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final cameras = ref.watch(camerasProvider);

    // The "+ Add camera" affordance every state shares, so an empty wall can be
    // filled and a full one grown from the same header the other Manage sections
    // use — no floating button that only some sections have.
    final addAction = SectionHeaderAction(
      icon: HcIcons.plus,
      label: 'Add camera',
      onPressed: () => _addCamera(context),
    );

    return cameras.when(
      loading: () => const SectionScaffold(
        title: 'Cameras',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => SectionScaffold(
        title: 'Cameras',
        child: Center(
            child: Text('$e', style: TextStyle(color: t.surface.onBaseMuted))),
      ),
      data: (list) {
        final onHome = list.where((c) => c.showOnHome).length;
        return SectionScaffold(
          title: 'Cameras',
          stats: [
            SectionStat(value: '${list.length}', label: 'cameras'),
            if (onHome > 0)
              SectionStat(
                value: '$onHome',
                label: 'on Home',
                tone: SectionTone.active,
                glow: true,
              ),
          ],
          actions: [
            // Wall-preview controls only mean something once there is a wall.
            if (list.isNotEmpty) ...[
              _LayoutToggle(
                value: _preview,
                onChanged: (v) => setState(() => _preview = v),
              ),
              if (_preview == WallLayout.spotlight) ...[
                const SizedBox(width: 8),
                _StripToggle(
                  value: _strip,
                  onChanged: (v) => setState(() => _strip = v),
                ),
              ],
              const SizedBox(width: 8),
              TextButton.icon(
                icon: const Icon(HcIcons.copy, size: 14),
                label: const Text('Kiosk link'),
                onPressed: () => _copyKioskLink(context, list),
              ),
              const SizedBox(width: 4),
            ],
            addAction,
          ],
          child: list.isEmpty
              ? const _Empty()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The wall as a device would see it, live, so what you build
                    // is what you get. Cameras below for management.
                    Expanded(
                      child: WallView(
                        cameras: list,
                        layout: _preview,
                        stripPosition: _strip,
                      ),
                    ),
                    _CameraStrip(
                      cameras: list,
                      onRemove: (id) =>
                          ref.read(camerasProvider.notifier).remove(id),
                      onToggleHome: (id, show) => ref
                          .read(camerasProvider.notifier)
                          .setShowOnHome(id, show),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _addCamera(BuildContext context) async {
    final camera = await showDialog<Camera>(
      context: context,
      builder: (_) => const _AddCameraDialog(),
    );
    if (camera != null) {
      await ref.read(camerasProvider.notifier).add(camera);
    }
  }

  Future<void> _copyKioskLink(
      BuildContext context, List<Camera> cameras) async {
    final link = await showDialog<String>(
      context: context,
      builder: (_) => _KioskLinkDialog(cameras: cameras, strip: _strip),
    );
    if (link != null) {
      await Clipboard.setData(ClipboardData(text: link));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kiosk link copied')),
        );
      }
    }
  }
}

/// Which presentation the preview (and the copied link) uses.
class _LayoutToggle extends StatelessWidget {
  const _LayoutToggle({required this.value, required this.onChanged});

  final WallLayout value;
  final ValueChanged<WallLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return SegmentedButton<WallLayout>(
      style: SegmentedButton.styleFrom(
        textStyle: t.text.bodySmallStyle,
        foregroundColor: t.surface.onBaseMuted,
        selectedForegroundColor: t.accent.onPrimary,
        selectedBackgroundColor: t.accent.active,
      ),
      segments: const [
        ButtonSegment(value: WallLayout.spotlight, label: Text('Spotlight')),
        ButtonSegment(value: WallLayout.grid, label: Text('Grid')),
      ],
      selected: {
        value == WallLayout.grid ? WallLayout.grid : WallLayout.spotlight
      },
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// Where the still filmstrip sits, in spotlight — a small compass of positions.
class _StripToggle extends StatelessWidget {
  const _StripToggle({required this.value, required this.onChanged});

  final StripPosition value;
  final ValueChanged<StripPosition> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return SegmentedButton<StripPosition>(
      style: SegmentedButton.styleFrom(
        textStyle: t.text.captionStyle,
        foregroundColor: t.surface.onBaseMuted,
        selectedForegroundColor: t.accent.onPrimary,
        selectedBackgroundColor: t.accent.active,
      ),
      segments: const [
        ButtonSegment(value: StripPosition.bottom, label: Text('Btm')),
        ButtonSegment(value: StripPosition.top, label: Text('Top')),
        ButtonSegment(value: StripPosition.left, label: Text('Left')),
        ButtonSegment(value: StripPosition.right, label: Text('Right')),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// The thin row of cameras along the bottom, where you manage each one: toggle
/// whether it appears on Home, and remove it. It is a Flutter strip UNDER the
/// wall, not an overlay on it — controls floated over a live iframe are
/// unclickable, because the platform view eats the pointer.
class _CameraStrip extends StatelessWidget {
  const _CameraStrip({
    required this.cameras,
    required this.onRemove,
    required this.onToggleHome,
  });

  final List<Camera> cameras;
  final ValueChanged<String> onRemove;
  final void Function(String id, bool show) onToggleHome;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
      decoration: BoxDecoration(
        color: t.surface.raised,
        border: Border(top: BorderSide(color: t.stroke.hairline)),
      ),
      child: Row(
        children: [
          Text('On Home',
              style: t.text.captionStyle.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: t.surface.onBaseMuted)),
          SizedBox(width: t.space.sm),
          Expanded(
            child: Wrap(
              spacing: t.space.sm,
              runSpacing: t.space.xs,
              children: [
                for (final cam in cameras)
                  _CameraChip(
                    camera: cam,
                    onToggleHome: () => onToggleHome(cam.id, !cam.showOnHome),
                    onRemove: () => onRemove(cam.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One camera in the strip: a Home eye that lights when the camera shows on the
/// house, its name, and a delete. The eye is the curation the combined Home card
/// used to hold — cameras page is where the wall is managed.
class _CameraChip extends StatelessWidget {
  const _CameraChip({
    required this.camera,
    required this.onToggleHome,
    required this.onRemove,
  });

  final Camera camera;
  final VoidCallback onToggleHome;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final on = camera.showOnHome;
    return Container(
      padding: EdgeInsets.only(left: t.space.xs, right: t.space.xs),
      decoration: BoxDecoration(
        color: t.surface.sunken,
        borderRadius: t.radius.smR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            iconSize: 15,
            color: on ? t.accent.active : t.surface.onBaseMuted,
            tooltip: on ? 'Showing on Home' : 'Hidden from Home',
            icon: Icon(on ? HcIcons.eye : HcIcons.eyeSlash),
            onPressed: onToggleHome,
          ),
          Text(camera.name,
              style: t.text.bodySmallStyle.copyWith(
                  color: on ? t.surface.onBase : t.surface.onBaseMuted)),
          SizedBox(width: t.space.xs),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 28),
            iconSize: 13,
            color: t.surface.onBaseMuted,
            tooltip: 'Remove',
            icon: const Icon(HcIcons.x),
            onPressed: onRemove,
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
              style: t.text.subtitleStyle.copyWith(
                  fontWeight: FontWeight.w600, color: t.surface.onBase)),
          SizedBox(height: t.space.xs),
          Text('Add a go2rtc stream or any MJPEG camera.',
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted)),
        ],
      ),
    );
  }
}

/// Builds the URL a device loads in Fully Kiosk, tuned per device.
class _KioskLinkDialog extends StatefulWidget {
  const _KioskLinkDialog({required this.cameras, required this.strip});
  final List<Camera> cameras;
  final StripPosition strip;

  @override
  State<_KioskLinkDialog> createState() => _KioskLinkDialogState();
}

class _KioskLinkDialogState extends State<_KioskLinkDialog> {
  WallLayout _layout = WallLayout.spotlight;
  late StripPosition _strip = widget.strip;
  final _included = <String>{};

  @override
  void initState() {
    super.initState();
    // All cameras, in order, by default.
    _included.addAll(widget.cameras.map((c) => _nameOf(c)));
  }

  String _nameOf(Camera c) => go2rtcStreamName(c.url) ?? c.id;

  String _link() {
    final origin = pageOrigin;
    final layout = switch (_layout) {
      WallLayout.spotlight => 'spotlight',
      WallLayout.grid => 'grid',
      WallLayout.solo => 'solo',
      WallLayout.auto => 'auto',
    };
    final ordered =
        widget.cameras.map(_nameOf).where(_included.contains).toList();
    final cams = ordered.join(',');
    final strip = _strip.name; // bottom|top|left|right
    final stripParam = _layout == WallLayout.spotlight ? '&strip=$strip' : '';
    return '$origin/#/wall?layout=$layout&cams=$cams$stripParam';
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final link = _link();

    return AlertDialog(
      backgroundColor: t.surface.overlay,
      title: const Text('Kiosk link'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Point Fully Kiosk on the device at this URL. Pick the layout the '
              'device can handle — Spotlight for a small tablet, Grid for a big '
              'display.',
              style:
                  t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted),
            ),
            SizedBox(height: t.space.md),
            SegmentedButton<WallLayout>(
              style: SegmentedButton.styleFrom(
                textStyle: t.text.bodySmallStyle,
                selectedBackgroundColor: t.accent.active,
                selectedForegroundColor: t.accent.onPrimary,
              ),
              segments: const [
                ButtonSegment(
                    value: WallLayout.spotlight, label: Text('Spotlight')),
                ButtonSegment(value: WallLayout.grid, label: Text('Grid')),
                ButtonSegment(value: WallLayout.auto, label: Text('Auto')),
              ],
              selected: {_layout},
              onSelectionChanged: (s) => setState(() => _layout = s.first),
            ),
            if (_layout == WallLayout.spotlight) ...[
              SizedBox(height: t.space.sm),
              Row(
                children: [
                  Text('Strip',
                      style: t.text.bodySmallStyle
                          .copyWith(color: t.surface.onBaseMuted)),
                  SizedBox(width: t.space.sm),
                  _StripToggle(
                    value: _strip,
                    onChanged: (v) => setState(() => _strip = v),
                  ),
                ],
              ),
            ],
            SizedBox(height: t.space.md),
            Text('Include',
                style: t.text.captionStyle.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: t.surface.onBaseMuted)),
            Wrap(
              spacing: t.space.xs,
              children: [
                for (final c in widget.cameras)
                  FilterChip(
                    label: Text(c.name, style: t.text.bodySmallStyle),
                    selected: _included.contains(_nameOf(c)),
                    onSelected: (on) => setState(() {
                      on
                          ? _included.add(_nameOf(c))
                          : _included.remove(_nameOf(c));
                    }),
                  ),
              ],
            ),
            SizedBox(height: t.space.md),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(t.space.sm),
              decoration: BoxDecoration(
                color: t.surface.sunken,
                borderRadius: t.radius.smR,
              ),
              child: SelectableText(
                link,
                style: t.text.resolve(t.text.caption, mono: true),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, link),
          child: const Text('Copy'),
        ),
      ],
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
                    value: 'webrtc', child: Text('go2rtc (WebRTC)')),
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
                    'The go2rtc stream page you can open in a browser, e.g. '
                        'http://10.0.10.150:1984/stream.html?src=driveway',
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
                'Embeds go2rtc\'s own player, so WebRTC works with no extra '
                'go2rtc config — it is the same page you open in a browser tab.',
                style:
                    t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
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
                  // Unique per add, NOT derived from the name — two cameras can
                  // share a name and a name-derived id made the second silently
                  // overwrite the first.
                  final id = 'cam_${DateTime.now().microsecondsSinceEpoch}';
                  Navigator.pop(
                    context,
                    Camera(
                      id: id,
                      name: _name.text.trim(),
                      url: _url.text.trim(),
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
