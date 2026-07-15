import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'camera_source.dart';
import 'camera_still.dart';
import 'camera_tile.dart';
import 'camera_store.dart';

/// The camera wall, in whichever shape the device asked for.
///
/// The same set of cameras is presented differently on different screens, and
/// which presentation is used is a property of the DEVICE, not the wall — so it
/// is chosen by the URL a device loads (see the kiosk route), never baked in.
///
///   * [WallLayout.spotlight] — one live, the rest as tappable stills. Only one
///     stream decodes at a time, which is what lets a small tablet cope.
///   * [WallLayout.grid] — every camera live. For a display with the bandwidth.
///   * [WallLayout.solo] — one camera, full screen.
///   * [WallLayout.auto] — spotlight on a narrow viewport, grid on a wide one.
class WallView extends StatefulWidget {
  const WallView({
    super.key,
    required this.cameras,
    required this.layout,
    this.initialActiveId,
  });

  final List<Camera> cameras;
  final WallLayout layout;

  /// Which camera starts live, in spotlight/solo. Defaults to the first.
  final String? initialActiveId;

  @override
  State<WallView> createState() => _WallViewState();
}

class _WallViewState extends State<WallView> {
  String? _activeId;

  @override
  void initState() {
    super.initState();
    _activeId = widget.initialActiveId ?? widget.cameras.firstOrNull?.id;
  }

  Camera get _active => widget.cameras.firstWhere(
        (c) => c.id == _activeId,
        orElse: () => widget.cameras.first,
      );

  @override
  Widget build(BuildContext context) {
    if (widget.cameras.isEmpty) return const SizedBox.shrink();

    final layout = widget.layout == WallLayout.auto
        ? (MediaQuery.sizeOf(context).width < 900
            ? WallLayout.spotlight
            : WallLayout.grid)
        : widget.layout;

    return switch (layout) {
      WallLayout.solo => _Solo(camera: _active),
      WallLayout.grid => _Grid(cameras: widget.cameras),
      _ => _Spotlight(
          active: _active,
          others: widget.cameras.where((c) => c.id != _active.id).toList(),
          onSelect: (c) => setState(() => _activeId = c.id),
        ),
    };
  }
}

/// One live, the rest as stills. Tap a still to make it the live one.
class _Spotlight extends StatelessWidget {
  const _Spotlight({
    required this.active,
    required this.others,
    required this.onSelect,
  });

  final Camera active;
  final List<Camera> others;
  final ValueChanged<Camera> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Column(
      children: [
        // The live feed takes the space; the filmstrip is a fixed strip beneath.
        Expanded(
          child: Padding(
            padding: EdgeInsets.all(t.space.sm),
            child: CameraTile(
              key: ValueKey(active.id),
              name: active.name,
              url: active.url,
              sourceType: active.sourceType,
              refreshSecs: active.refreshSecs,
            ),
          ),
        ),
        if (others.isNotEmpty)
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: t.space.sm),
              itemCount: others.length,
              separatorBuilder: (_, __) => SizedBox(width: t.space.sm),
              itemBuilder: (context, i) {
                final cam = others[i];
                return AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _StillCell(camera: cam, onTap: () => onSelect(cam)),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _StillCell extends StatelessWidget {
  const _StillCell({required this.camera, required this.onTap});

  final Camera camera;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return ClipRRect(
      borderRadius: t.radius.smR,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF05070A)),
          CameraStill(
            url: camera.url,
            sourceType: camera.sourceType,
            onTap: onTap,
          ),
          Positioned(
            left: 6,
            right: 6,
            bottom: 4,
            child: Text(
              camera.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Every camera live. The span each carries becomes its width in the grid.
class _Grid extends StatelessWidget {
  const _Grid({required this.cameras});

  final List<Camera> cameras;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return LayoutBuilder(
      builder: (context, c) {
        // A base unit ~360px wide; a camera's span multiplies it.
        final columns = (c.maxWidth / 360).floor().clamp(1, 6);
        final unit = (c.maxWidth - (columns + 1) * t.space.sm) / columns;

        return SingleChildScrollView(
          padding: EdgeInsets.all(t.space.sm),
          child: Wrap(
            spacing: t.space.sm,
            runSpacing: t.space.sm,
            children: [
              for (final cam in cameras)
                SizedBox(
                  width: (unit * cam.span.clamp(1, columns)) +
                      (cam.span.clamp(1, columns) - 1) * t.space.sm,
                  height: unit * 9 / 16,
                  child: CameraTile(
                    key: ValueKey(cam.id),
                    name: cam.name,
                    url: cam.url,
                    sourceType: cam.sourceType,
                    refreshSecs: cam.refreshSecs,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Solo extends StatelessWidget {
  const _Solo({required this.camera});

  final Camera camera;

  @override
  Widget build(BuildContext context) => CameraTile(
        key: ValueKey(camera.id),
        name: camera.name,
        url: camera.url,
        sourceType: camera.sourceType,
        refreshSecs: camera.refreshSecs,
      );
}
