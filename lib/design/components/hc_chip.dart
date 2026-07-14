import 'package:flutter/material.dart';

import '../tokens.dart';

/// An inline, editable value.
///
/// This is the load-bearing primitive of the sentence editor: **the chip _is_
/// the field.** There is no label above it and no box around it, because it sits
/// inside a sentence — "when the *Bathroom Door Sensor* *closes*" — and a
/// labelled outlined box in the middle of a sentence stops being a sentence.
///
/// A device chip carries that device's *live* state ([on]), which is the point:
/// a rule then shows you the house, not merely its own configuration.
class HcChip extends StatefulWidget {
  const HcChip({
    super.key,
    required this.label,
    this.onTap,
    this.on = false,
    this.icon,
    this.style = HcChipStyle.solid,
    this.tooltip,
  });

  /// A device chip: live state drives the glow and the status dot.
  const HcChip.device({
    super.key,
    required this.label,
    required this.on,
    this.icon,
    this.onTap,
    this.tooltip,
  }) : style = HcChipStyle.device;

  /// A plain value — a duration, a number, a scene. Dashed, so it reads as
  /// "something you fill in" rather than "something that exists".
  const HcChip.value({
    super.key,
    required this.label,
    this.onTap,
    this.tooltip,
  })  : on = false,
        icon = null,
        style = HcChipStyle.value;

  final String label;
  final VoidCallback? onTap;
  final bool on;
  final IconData? icon;
  final HcChipStyle style;
  final String? tooltip;

  @override
  State<HcChip> createState() => _HcChipState();
}

enum HcChipStyle { solid, device, value }

class _HcChipState extends State<HcChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final isDevice = widget.style == HcChipStyle.device;
    final isValue = widget.style == HcChipStyle.value;
    final lit = isDevice && widget.on;

    final border = lit
        ? t.accent.active.withValues(alpha: 0.55)
        : _hover
            ? t.stroke.focus
            : t.stroke.hairline;

    final chip = AnimatedContainer(
      duration: t.motion.d(t.motion.fast),
      curve: t.motion.curve,
      transform:
          Matrix4.translationValues(0, _hover && t.motion.enabled ? -1 : 0, 0),
      padding: EdgeInsets.fromLTRB(
        isDevice ? t.space.sm : t.space.sm + 2,
        t.space.xs,
        t.space.sm + 2,
        t.space.xs,
      ),
      decoration: BoxDecoration(
        color: isValue ? Colors.transparent : t.surface.sunken,
        borderRadius: t.radius.smR,
        border: Border.all(
          color: isValue && !_hover ? t.stroke.hairline : border,
          width: t.stroke.width,
        ),
        boxShadow: [
          // A lit device chip bleeds light, exactly like its tile does. The
          // language has to be the same in both places or it isn't a language.
          if (lit && t.glow.enabled)
            BoxShadow(
              color: t.accent.active.withValues(alpha: 0.35),
              blurRadius: t.glow.radius * 0.5,
              spreadRadius: -6,
            ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDevice) ...[
            _StatusDot(on: widget.on),
            SizedBox(width: t.space.sm),
          ] else if (widget.icon != null) ...[
            Icon(widget.icon, size: 13, color: t.surface.onBaseMuted),
            SizedBox(width: t.space.xs + 1),
          ],
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isValue ? t.accent.primary : t.surface.onBase,
            ),
          ),
          SizedBox(width: t.space.xs + 1),
          Icon(Icons.expand_more, size: 13, color: t.surface.onBaseMuted),
        ],
      ),
    );

    final tappable = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, child: chip),
    );

    return widget.tooltip == null
        ? tappable
        : Tooltip(message: widget.tooltip!, child: tappable);
  }
}

/// The live dot on a device chip. It breathes when the device is on — a slow
/// pulse, not a blink, so a wall of chips doesn't strobe.
class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.on});

  final bool on;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Driven here rather than in build, so painting never starts a ticker — and
    // a reduced-motion skin never spins one at all.
    final animate = widget.on && HcTokens.of(context).motion.enabled;
    if (animate && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!animate && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void didUpdateWidget(covariant _StatusDot old) {
    super.didUpdateWidget(old);
    if (widget.on != old.on) didChangeDependencies();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final colour = widget.on ? t.accent.active : t.surface.onBaseMuted;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final fade =
            widget.on && t.motion.enabled ? 1.0 - (_c.value * 0.6) : 1.0;
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colour.withValues(alpha: fade),
          ),
        );
      },
    );
  }
}
