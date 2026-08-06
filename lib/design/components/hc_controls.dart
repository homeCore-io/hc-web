import 'package:flutter/material.dart';

import '../tokens.dart';

/// An on/off control, on the token layer.
///
/// Material's `Switch` was the loudest thing on the automations list: 42 of them
/// down the page, each a saturated blue pill, in an app whose accent is amber.
/// It shouted the *least* interesting fact about each rule (that it exists and
/// is on) louder than the rule's own name.
///
/// This is the same affordance at the weight it deserves — and it takes its
/// colour from the theme, so it cannot drift away from the rest of the app the
/// way a hard-coded Material primary did.
class HcToggle extends StatelessWidget {
  const HcToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final enabled = onChanged != null;
    final on = value;

    final track = on
        ? t.accent.active.withValues(alpha: enabled ? 0.9 : 0.4)
        : t.surface.sunken;
    final knob = on ? t.accent.onPrimary : t.surface.onBaseMuted;

    return Semantics(
      toggled: on,
      label: semanticLabel,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          onTap: enabled ? () => onChanged!(!on) : null,
          child: AnimatedContainer(
            duration: t.motion.fast,
            curve: Curves.easeOutCubic,
            width: 34,
            height: 20,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              color: track,
              borderRadius: t.radius.smR,
              border: Border.all(
                color: on ? Colors.transparent : t.stroke.hairline,
              ),
            ),
            child: AnimatedAlign(
              duration: t.motion.fast,
              curve: Curves.easeOutCubic,
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  color: knob,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small, flat icon control.
///
/// Deliberately not `IconButton`: its 48px minimum tap target made every row of
/// controls taller than the content it decorated, which is how a list of 42
/// rules turned into a wall of chrome.
///
/// Pair it with [HcHoverControls] so it stays quiet until reached for.
class HcIconButton extends StatelessWidget {
  const HcIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
    this.size = 15,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool danger;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onPressed,
        borderRadius: t.radius.smR,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(
            icon,
            size: size,
            color: onPressed == null
                ? t.surface.onBaseMuted.withValues(alpha: 0.4)
                : danger
                    ? t.accent.danger
                    : t.surface.onBaseMuted,
          ),
        ),
      ),
    );
  }
}

/// Row controls that stay quiet until you reach for them.
///
/// Idle opacity is deliberately not zero: a touch screen has no hover, and a
/// control you cannot discover is a control you do not have.
class HcHoverControls extends StatelessWidget {
  const HcHoverControls({
    super.key,
    required this.shown,
    required this.children,
  });

  final bool shown;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final t = HcTokens.of(context);

    return AnimatedOpacity(
      opacity: shown ? 1 : 0.25,
      duration: t.motion.fast,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
