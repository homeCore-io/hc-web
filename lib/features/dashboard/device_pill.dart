import 'package:flutter/material.dart';

import '../../core/devices/presentation.dart';
import '../../core/models/device_state.dart';
import '../../design/components/hc_surface.dart';
import '../../design/components/hc_tile.dart' show summarise;
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';

/// One device, as wide as its name.
///
/// **A tile is more box than some rooms need.** A card with a glyph, a name, a
/// state and a control in it, repeated across a row under a heading, reads as a
/// row of blocks — and the name is the part that gives way, because the box is
/// fixed and the contents are not. John: *"I don't like the box look for
/// devices and they look contorted with names cut off in the boxes for lights
/// and switches."*
///
/// So: a pill. It takes the width its name asks for and wraps onto the next
/// line when it runs out, which means nothing is ever cut off and a room with
/// two lights does not get a row sized for four.
class DevicePill extends StatelessWidget {
  const DevicePill({
    super.key,
    required this.device,
    this.label,
    this.selected = false,
    this.onTap,
    this.onToggle,
  });

  final DeviceState device;

  /// What to call it, when that is not its full name — a room page hands over
  /// the name with the room's own name taken off the front.
  final String? label;

  /// Whether this is the device the page's controls are aimed at.
  final bool selected;

  final VoidCallback? onTap;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final offline = !device.available;
    final on = !offline && isOn(device);
    // A colour light lit its real colour, the way every other surface reads it.
    final tint = on ? lightColorOf(device) : null;
    final accent = tint ?? t.accent.active;
    final ink = offline
        ? t.accent.offline
        : on
            ? accent
            : t.surface.onBaseMuted;

    return HcSurface(
      onTap: onTap,
      selected: selected,
      glowColor: accent,
      glowIntensity: on ? (levelOf(device) ?? 1.0) : 0,
      borderRadius: t.radius.pillR,
      padding:
          EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The glyph alone, as on the tiles: a disc behind it would put a
          // second shape inside a shape, which is the thing this is replacing.
          Icon(
            HcIcons.forFacet(
                deviceIconOverride(device) ?? facetOf(device, device.schema),
                on: on),
            size: 17,
            color: ink,
          ),
          SizedBox(width: t.space.sm),
          Text(
            label ?? device.displayName,
            style: t.text.bodySmallStyle.copyWith(
              color: offline ? t.accent.offline : t.surface.onBase,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: t.space.sm),
          Text(
            offline ? 'offline' : summarise(device),
            style: t.text.captionStyle.copyWith(color: ink),
          ),
          if (onToggle != null) ...[
            SizedBox(width: t.space.sm),
            // A tap on the pill picks it; the switch is how you turn it on,
            // and the two must not be the same gesture.
            GestureDetector(
              onTap: onToggle,
              child: Container(
                width: 30,
                height: 17,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: on ? t.accent.active : t.accent.inactive,
                  borderRadius: t.radius.pillR,
                ),
                child: AnimatedAlign(
                  duration: t.motion.d(t.motion.fast),
                  // Not the overshooting curve: a knob that springs past the
                  // end of its track reads as a glitch at this size.
                  curve: t.motion.curve,
                  alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: t.surface.raised,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
