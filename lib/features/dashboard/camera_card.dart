import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/hc_icons.dart';
import '../../design/tokens.dart';

/// The URL to actually fetch for a given frame.
///
/// An `image_refresh` source is a still that must be re-fetched, and browsers
/// cache aggressively — without a buster the same frame is served forever and a
/// live camera looks frozen, which on a security wall is the worst possible
/// failure. Streaming sources are fetched once and left alone.
String cameraSrc(String url, String sourceType, int frame) {
  if (sourceType != 'image_refresh') return url;
  return '$url${url.contains('?') ? '&' : '?'}_=$frame';
}

/// Whether we can render this source at all.
///
/// MJPEG is a never-ending image and the browser handles it natively. HLS and
/// WebRTC need a real player, which we do not ship yet — and saying so is far
/// better than a black rectangle the user would mistake for a dark garden.
bool cameraRenderable(String sourceType) =>
    sourceType == 'image_refresh' || sourceType == 'mjpeg';

/// A live camera, as a dashboard card.
///
/// Display only. The NVR (go2rtc) already does motion, detection and recording,
/// so the frontend does none of it — this is a wall of live streams you arrange
/// yourself. A camera is just another registered card, so a "Security" page is a
/// dashboard whose cards all happen to be cameras, and **Arrange** is the same
/// packing grid every other dashboard uses.
///
/// It lands on core's existing `camera_video` type, which already validates
/// `source_type` ∈ `image_refresh | mjpeg | hls | webrtc` plus a `url`. Nothing
/// new is invented and no plugin is needed.
class CameraCard extends StatefulWidget {
  const CameraCard({
    super.key,
    required this.name,
    required this.url,
    required this.sourceType,
    this.refreshSecs,
  });

  final String name;
  final String url;
  final String sourceType;

  /// Only meaningful for `image_refresh`.
  final int? refreshSecs;

  @override
  State<CameraCard> createState() => _CameraCardState();
}

class _CameraCardState extends State<CameraCard> {
  Timer? _tick;

  /// Cache-buster for `image_refresh`. Without it the browser serves the same
  /// frame forever and the camera looks frozen rather than live.
  int _frame = 0;

  bool _down = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant CameraCard old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url ||
        old.sourceType != widget.sourceType ||
        old.refreshSecs != widget.refreshSecs) {
      _start();
    }
  }

  void _start() {
    _tick?.cancel();
    if (widget.sourceType != 'image_refresh') return;

    final secs = (widget.refreshSecs ?? 2).clamp(1, 300);
    _tick = Timer.periodic(Duration(seconds: secs), (_) {
      if (mounted) setState(() => _frame++);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  bool get _renderable => cameraRenderable(widget.sourceType);

  String get _src => cameraSrc(widget.url, widget.sourceType, _frame);

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return ClipRRect(
      borderRadius: t.radius.mdR,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF05070A)),
          if (_renderable && !_down)
            Image.network(
              _src,
              fit: BoxFit.cover,
              gaplessPlayback: true, // no flicker between refreshed frames
              errorBuilder: (_, __, ___) {
                // Schedule, don't setState during build.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_down) setState(() => _down = true);
                });
                return const SizedBox.shrink();
              },
            )
          else
            _Placeholder(
              // A dead stream is a fault, and it says so. A black rectangle is
              // indistinguishable from a quiet night, which is the one thing a
              // security wall must never be.
              message: _down
                  ? 'Stream down'
                  : '${widget.sourceType.toUpperCase()} needs a player',
              fault: _down,
            ),

          // Legibility over any frame, bright or dark.
          const _Scrim(),

          Positioned(
            top: 8,
            left: 10,
            right: 10,
            child: Row(
              children: [
                if (_renderable && !_down) const _LiveBadge(),
                if (_renderable && !_down) SizedBox(width: t.space.sm),
                Expanded(
                  child: Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.text.bodySmallStyle.copyWith(
                        fontWeight: FontWeight.w600,
                        color: _down ? t.accent.danger : Colors.white,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 4),
                        ]),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 7,
            right: 10,
            child: Text(
              widget.sourceType,
              style: t.text.overlineStyle.copyWith(
                  color: Colors.white54,
                  shadows: const [
                    Shadow(color: Colors.black87, blurRadius: 3)
                  ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0x8C000000),
              Color(0x00000000),
              Color(0x00000000),
              Color(0xB3000000),
            ],
            stops: [0, 0.32, 0.6, 1],
          ),
        ),
      );
}

class _LiveBadge extends StatefulWidget {
  const _LiveBadge();

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = HcTokens.of(context).motion.enabled;
    if (animate && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!animate && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: t.accent.success.withValues(alpha: 0.2),
        borderRadius: t.radius.xsR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.accent.success.withValues(alpha: 1 - (_c.value * 0.7)),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'LIVE',
            style: TextStyle(
                fontSize: t.text.scaled(9),
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: t.accent.success),
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.message, required this.fault});

  final String message;
  final bool fault;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final colour = fault ? t.accent.danger : t.surface.onBaseMuted;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(fault ? HcIcons.warning : HcIcons.camera,
              size: 20, color: colour),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: t.text.captionStyle
                .copyWith(fontWeight: FontWeight.w600, color: colour),
          ),
        ],
      ),
    );
  }
}
