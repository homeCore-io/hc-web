import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// The one card in the system.
///
/// It reads `surface.glassBlur` to decide whether to frost its backdrop, so the
/// Ambient Glass skin gets real translucency while the flat skins skip the
/// (expensive) [BackdropFilter] entirely — same widget, no `if (skin == ...)`.
///
/// [glowColor] + [glowIntensity] draw the signature halo: an active device
/// bleeds its own light onto the card. Intensity is typically the device's
/// brightness, so a lamp at 10% glows faintly and the same lamp at 100% blooms.
class HcSurface extends StatelessWidget {
  const HcSurface({
    super.key,
    required this.child,
    this.padding,
    this.glowColor,
    this.glowIntensity = 0,
    this.selected = false,
    this.onTap,
    this.borderRadius,
    this.filled = true,
    this.bordered = true,
    this.tint,
    this.blur = 0,
    this.image,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// Light the card emits. Null means no halo.
  final Color? glowColor;

  /// 0–1. Scales the halo's spread and opacity.
  final double glowIntensity;

  final bool selected;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  /// Draw the fill and the card's elevation. False leaves the page showing
  /// through — and takes the shadow with it, because a shadow under nothing is
  /// a card you can see the edge of and not the face.
  ///
  /// Added for the dashboard designer's style pane: a page where every element
  /// is the same filled, bordered rectangle reads as a grid of boxes no matter
  /// what is inside them.
  final bool filled;

  /// Draw the hairline. A selected surface keeps its outline whatever this
  /// says — losing the selection marker is a worse trade than honouring the
  /// style exactly.
  final bool bordered;

  /// Overrides the fill colour. Null takes the skin's own raised surface,
  /// which is what every card had before there was a style pane.
  final Color? tint;

  /// Frosts the backdrop, 0–20. The glass skin does this for every card; this
  /// is the same capability offered to one card on any skin.
  final double blur;

  /// A picture on the card, under its contents and inside its corners.
  final DecorationImage? image;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final radius = borderRadius ?? t.radius.mdR;
    final intensity = glowIntensity.clamp(0.0, 1.0);
    final glows = t.glow.enabled && glowColor != null && intensity > 0;

    // The halo is a shadow rather than a painted blur: it renders outside the
    // card's bounds, which is what makes the light look like it's spilling.
    final haloShadows = glows
        ? [
            BoxShadow(
              color: glowColor!.withValues(
                alpha: 0.42 * intensity * t.glow.strength,
              ),
              blurRadius: t.glow.radius * (0.45 + 0.55 * intensity),
              spreadRadius: -4,
            ),
          ]
        : const <BoxShadow>[];

    Widget body = AnimatedContainer(
      duration: t.motion.d(t.motion.base),
      curve: t.motion.curve,
      padding: padding ?? EdgeInsets.all(t.density.cardPadding),
      decoration: BoxDecoration(
        // On a glass skin the fill is a sheer tint over the blurred backdrop;
        // on a flat skin it is the opaque raised surface.
        color: filled
            ? (tint ??
                (t.surface.isGlass ? t.surface.glassTint : t.surface.raised))
            : null,
        image: image,
        borderRadius: radius,
        border: bordered || selected
            ? Border.all(
                color: selected ? t.stroke.focus : t.stroke.hairline,
                width: selected ? t.stroke.width * 2 : t.stroke.width,
              )
            : null,
        boxShadow: [if (filled) ...t.elevation.card, ...haloShadows],
      ),
      child: child,
    );

    // Frosted when the skin says so, or when this card asks for it. A card
    // with no fill still frosts — that is the whole look — but one with
    // neither has nothing to blur behind and skips the expensive filter.
    if ((t.surface.isGlass || blur > 0) && (filled || blur > 0)) {
      body = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: blur > 0 ? blur : t.surface.glassBlur,
            sigmaY: blur > 0 ? blur : t.surface.glassBlur,
          ),
          child: body,
        ),
      );
      // ClipRRect would crop the halo, so it is re-hung on an outer box.
      if (glows) {
        body = DecoratedBox(
          decoration:
              BoxDecoration(borderRadius: radius, boxShadow: haloShadows),
          child: body,
        );
      }
    }

    if (onTap == null) return body;
    return _Pressable(onTap: onTap!, borderRadius: radius, child: body);
  }
}

/// Gives a surface physical weight: it sinks slightly under a press and springs
/// back on release, using the skin's own emphasized curve. On Control Room
/// (whose curve does not overshoot) it reads as a crisp click instead.
class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.child,
    required this.onTap,
    required this.borderRadius,
  });

  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down && t.motion.enabled ? 0.975 : 1,
          duration: t.motion.d(t.motion.fast),
          curve: t.motion.emphasized,
          child: widget.child,
        ),
      ),
    );
  }
}

/// A value readout that will not make the layout twitch as it updates.
///
/// Live numbers change constantly on a wall panel; proportional digits cause a
/// visible shimmy every tick. Tabular figures come from the skin's tokens.
class HcValue extends StatelessWidget {
  const HcValue(
    this.value, {
    super.key,
    this.unit,
    this.style,
    this.muted = false,
  });

  final String value;
  final String? unit;
  final TextStyle? style;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final base =
        (style ?? Theme.of(context).textTheme.titleMedium ?? const TextStyle())
            .copyWith(
      fontFeatures: t.numericFontFeatures,
      color: muted ? t.surface.onBaseMuted : t.surface.onBase,
    );

    if (unit == null) return Text(value, style: base);

    return RichText(
      text: TextSpan(
        style: base,
        children: [
          TextSpan(text: value),
          TextSpan(
            text: unit,
            style: base.copyWith(
              color: t.surface.onBaseMuted,
              fontSize: (base.fontSize ?? 16) * 0.62,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading placeholder with a travelling sheen. Reads as "content is coming",
/// where a spinner reads as "something is wrong".
class HcShimmer extends StatefulWidget {
  const HcShimmer({super.key, this.width, this.height = 14, this.radius});

  final double? width;
  final double height;
  final BorderRadius? radius;

  @override
  State<HcShimmer> createState() => _HcShimmerState();
}

class _HcShimmerState extends State<HcShimmer>
    with SingleTickerProviderStateMixin {
  // Eager, for the same reason as _PulseRing: a lazy `late final` would be
  // constructed by `dispose` on the reduced-motion path, which asserts.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Driven here rather than in `build`, so we never start a ticker as a
    // side effect of painting — and so a reduced-motion skin never spins one.
    final animate = HcTokens.of(context).motion.enabled;
    if (animate && !_c.isAnimating) {
      _c.repeat();
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
    // Under reduced motion a travelling sheen is exactly the kind of thing we
    // promised not to do — fall back to a static block.
    if (!t.motion.enabled) return _box(t);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: widget.radius ?? t.radius.smR,
          gradient: LinearGradient(
            begin: Alignment(-1 - 2 * (1 - _c.value), 0),
            end: Alignment(1 - 2 * (1 - _c.value), 0),
            colors: [
              t.surface.sunken,
              Color.lerp(t.surface.sunken, t.surface.onBase, 0.08)!,
              t.surface.sunken,
            ],
          ),
        ),
      ),
    );
  }

  Widget _box(HcTokens t) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: t.surface.sunken,
          borderRadius: widget.radius ?? t.radius.smR,
        ),
      );
}
