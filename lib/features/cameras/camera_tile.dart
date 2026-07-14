import 'package:flutter/material.dart';

import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import 'camera_view.dart';

/// One camera on the wall: the live picture, its name, and which transport is
/// actually carrying it.
///
/// The transport badge is not decoration. On a security wall the difference
/// between "RTC" (sub-second) and "MJPEG" (a second or two behind) is the
/// difference between watching something happen and watching a recording of it,
/// and it also tells you at a glance whether your NVR's cross-origin WebSocket is
/// open. "unreachable" is louder than the rest, because a black tile that is
/// silent is indistinguishable from a quiet night.
class CameraTile extends StatefulWidget {
  const CameraTile({
    super.key,
    required this.name,
    required this.url,
    required this.sourceType,
    this.refreshSecs,
  });

  final String name;
  final String url;
  final String sourceType;
  final int? refreshSecs;

  @override
  State<CameraTile> createState() => _CameraTileState();
}

class _CameraTileState extends State<CameraTile> {
  /// null while connecting; then 'RTC' | 'MSE' | 'MJPEG' | 'still' | 'unreachable'.
  String? _transport;

  bool get _down => _transport == 'unreachable';
  bool get _connecting => _transport == null;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return ClipRRect(
      borderRadius: t.radius.mdR,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF05070A)),

          CameraView(
            url: widget.url,
            sourceType: widget.sourceType,
            refreshSecs: widget.refreshSecs,
            onTransport: (v) {
              if (mounted) setState(() => _transport = v);
            },
          ),

          if (_connecting)
            const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),

          if (_down)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(HcIcons.warning, size: 20, color: t.accent.danger),
                  SizedBox(height: t.space.xs),
                  Text('Unreachable',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: t.accent.danger)),
                ],
              ),
            ),

          // Legibility over any frame, bright or dark.
          const _Scrim(),

          Positioned(
            top: 8,
            left: 10,
            right: 10,
            child: Row(
              children: [
                if (!_connecting && !_down) _TransportBadge(label: _transport!),
                if (!_connecting && !_down) SizedBox(width: t.space.sm),
                Expanded(
                  child: Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _down ? t.accent.danger : Colors.white,
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransportBadge extends StatelessWidget {
  const _TransportBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    // RTC/MSE are real-time and green; MJPEG/still are alive-but-behind and amber.
    final live = label == 'RTC' || label == 'MSE' || label == 'live';
    final colour = live ? t.accent.success : t.accent.warn;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
          ),
          const SizedBox(width: 5),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: colour,
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
            colors: [Color(0x8C000000), Color(0x00000000)],
            stops: [0, 0.35],
          ),
        ),
      );
}
