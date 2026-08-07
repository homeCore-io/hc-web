import 'package:flutter/material.dart';

import '../tokens.dart';
import 'hc_surface.dart';

/// A live device card.
///
/// Three things here are the difference between "web page" and "app":
///
/// 1. **It emits light.** An on device tints its own surface and casts a halo
///    scaled by [intensity], so a dimmed lamp looks dimmed from across a room.
/// 2. **It glides.** [intensity] is tweened, so a brightness change arriving on
///    the WebSocket ramps rather than snapping. State you can watch move is
///    state you believe.
/// 3. **It reacts to reality, not to you.** Bump [pulse] whenever a change
///    arrives from *outside* this client and the tile flashes a ring — so a
///    light someone else turned on visibly announces itself.
///
/// Offline is deliberately not "off": an unreachable device is a fault, and it
/// gets its own colour and a dashed border rather than quietly reading as off.
class HcDeviceTile extends StatelessWidget {
  const HcDeviceTile({
    super.key,
    required this.name,
    required this.icon,
    this.subtitle,
    this.on = false,
    this.intensity = 1.0,
    this.offline = false,
    this.pulse = 0,
    this.onTap,
    this.onToggle,
    this.trailing,
  });

  final String name;
  final IconData icon;
  final String? subtitle;

  /// Whether the device is doing something (light on, lock unlocked, playing).
  final bool on;

  /// 0–1. Brightness, volume, openness — whatever "how much" means here.
  /// Drives the halo and the tint, so the tile is a readout, not just a button.
  final double intensity;

  final bool offline;

  /// Increment to flash the tile. Wire it to the WS event sequence for this
  /// device so *remote* changes announce themselves.
  final int pulse;

  final VoidCallback? onTap;
  final VoidCallback? onToggle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    final lit = on && !offline;
    final level = lit ? intensity.clamp(0.0, 1.0) : 0.0;

    final fg = offline
        ? t.accent.offline
        : lit
            ? t.accent.active
            : t.surface.onBaseMuted;

    return TweenAnimationBuilder<double>(
      // The glide. Omitting `begin` makes each rebuild animate from the value
      // currently on screen to the new one, so a brightness change arriving on
      // the WebSocket ramps instead of snapping. Everything downstream reads
      // `v`, not `level`, so halo, tint and icon all ramp together.
      tween: Tween(end: level),
      duration: t.motion.d(t.motion.base),
      curve: t.motion.curve,
      builder: (context, v, _) => _PulseRing(
        pulse: pulse,
        color: t.accent.primary,
        child: HcSurface(
          onTap: onTap,
          glowColor: t.accent.active,
          glowIntensity: v,
          child: Row(
            children: [
              _Bulb(icon: icon, color: fg, level: v, offline: offline),
              SizedBox(width: t.space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: offline
                                ? t.surface.onBaseMuted
                                : t.surface.onBase,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (subtitle != null || offline)
                      Padding(
                        padding: EdgeInsets.only(top: t.space.xs),
                        child: Text(
                          offline ? 'Offline' : subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: offline
                                        ? t.accent.offline
                                        : t.surface.onBaseMuted,
                                    fontFeatures: t.numericFontFeatures,
                                  ),
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              if (trailing == null && onToggle != null && !offline)
                _Switch(on: on, onChanged: (_) => onToggle!()),
            ],
          ),
        ),
      ),
    );
  }
}

/// The icon, wrapped in a disc that fills with light as the device brightens.
class _Bulb extends StatelessWidget {
  const _Bulb({
    required this.icon,
    required this.color,
    required this.level,
    required this.offline,
  });

  final IconData icon;
  final Color color;
  final double level;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final size = t.density.controlHeight;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // The disc itself brightens — the tile's own little lamp.
        color: Color.lerp(
          t.surface.sunken,
          t.accent.active.withValues(alpha: 0.28),
          level,
        ),
        border: offline
            ? Border.all(color: t.accent.offline.withValues(alpha: 0.5))
            : null,
      ),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}

/// A toggle with the skin's own weight — it does not fall back to Material's
/// stock switch, which would drag its own design language in with it.
class _Switch extends StatelessWidget {
  const _Switch({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final h = (t.density.controlHeight * 0.56).clamp(20.0, 34.0);
    final w = h * 1.75;

    return Semantics(
      toggled: on,
      child: GestureDetector(
        onTap: () => onChanged(!on),
        child: AnimatedContainer(
          duration: t.motion.d(t.motion.fast),
          curve: t.motion.curve,
          width: w,
          height: h,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: on ? t.accent.active : t.accent.inactive,
            borderRadius: t.radius.pillR,
          ),
          child: AnimatedAlign(
            duration: t.motion.d(t.motion.fast),
            // The knob overshoots slightly on skins whose emphasized curve
            // does — a small thing that reads as physical.
            curve: t.motion.emphasized,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: h - 6,
              height: h - 6,
              decoration: BoxDecoration(
                color: t.surface.raised,
                shape: BoxShape.circle,
                boxShadow: t.elevation.card,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Flashes a ring when [pulse] changes — the visual echo of a WebSocket event.
class _PulseRing extends StatefulWidget {
  const _PulseRing({
    required this.child,
    required this.pulse,
    required this.color,
  });

  final Widget child;
  final int pulse;
  final Color color;

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  // Constructed eagerly, not with a `late final` initializer: under reduced
  // motion `build` returns before ever touching the controller, and a lazy
  // field would then be *created* by `dispose` — which asserts.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void didUpdateWidget(covariant _PulseRing old) {
    super.didUpdateWidget(old);
    if (widget.pulse != old.pulse) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    if (!t.motion.enabled) return widget.child;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = _c.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: t.radius.mdR,
            border: Border.all(
              // Fades out as it finishes, so the ring reads as a ripple rather
              // than a border that appeared.
              color: widget.color.withValues(alpha: v == 0 ? 0 : (1 - v) * 0.9),
              width: 2,
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
