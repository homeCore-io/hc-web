import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'camera_source.dart';
import 'camera_view.dart';

/// One camera on the wall: the live picture with its name over it.
///
/// A go2rtc camera renders through go2rtc's own embedded player (see
/// [CameraView]), which shows its own connection state and mode inside the
/// frame — so the tile does not second-guess it with a badge it cannot actually
/// read across the iframe boundary. It just names the camera.
class CameraTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final go2rtc = transportFor(sourceType) == CameraTransport.go2rtc;

    return ClipRRect(
      borderRadius: t.radius.mdR,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF05070A)),

          CameraView(
              url: url, sourceType: sourceType, refreshSecs: refreshSecs),

          // A scrim only over the top strip, so the name stays legible without
          // dimming the picture.
          const Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 44,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x8C000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            top: 8,
            left: 10,
            right: 10,
            child: Row(
              children: [
                if (go2rtc) ...[
                  const _LiveDot(),
                  SizedBox(width: t.space.sm),
                ],
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.text.bodySmallStyle.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 4)
                        ]),
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

class _LiveDot extends StatelessWidget {
  const _LiveDot();

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
          Container(
            width: 5,
            height: 5,
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: t.accent.success),
          ),
          const SizedBox(width: 5),
          Text('LIVE',
              style: TextStyle(
                  fontSize: t.text.scaled(9),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                  color: t.accent.success)),
        ],
      ),
    );
  }
}
