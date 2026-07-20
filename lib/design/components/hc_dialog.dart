import 'dart:ui';

import 'package:flutter/material.dart';

import '../tokens.dart';

/// A dialog in the house style.
///
/// The tokens always described dialogs — `surface.overlay` is documented as
/// "sheets, dialogs, the command palette", and `elevation.overlay` exists for
/// exactly this — but no component ever consumed them, so every dialog in the
/// app was a stock `AlertDialog` wearing Material's default blue. This is that
/// missing component.
///
/// It honours the skin: on a glass skin the backdrop blurs behind the panel,
/// and on a flat skin `glassBlur == 0` collapses that to a plain fill with no
/// separate code path.
class HcDialog extends StatelessWidget {
  const HcDialog({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.trailing,
    this.actions = const [],
    this.width = 520,
  });

  final String title;

  /// Prose under the title — an action's description, a confirmation's stakes.
  final String? description;

  /// Sits opposite the title: a spinner while work runs, a status icon after.
  final Widget? trailing;

  final Widget child;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    final panel = Container(
      width: width,
      decoration: BoxDecoration(
        color: t.surface.isGlass ? t.surface.glassTint : t.surface.overlay,
        borderRadius: BorderRadius.circular(t.radius.lg),
        border: Border.all(color: t.stroke.hairline, width: t.stroke.width),
        boxShadow: t.elevation.overlay,
      ),
      padding: EdgeInsets.all(t.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: t.surface.onBase,
                  ),
                ),
              ),
              if (trailing != null) ...[SizedBox(width: t.space.md), trailing!],
            ],
          ),
          if (description != null) ...[
            SizedBox(height: t.space.sm),
            Text(
              description!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: t.surface.onBaseMuted,
              ),
            ),
          ],
          SizedBox(height: t.space.md),
          Flexible(child: SingleChildScrollView(child: child)),
          if (actions.isNotEmpty) ...[
            SizedBox(height: t.space.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final a in actions) ...[
                  a,
                  if (a != actions.last) SizedBox(width: t.space.sm),
                ],
              ],
            ),
          ],
        ],
      ),
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.all(t.space.lg),
      child: t.surface.isGlass
          ? ClipRRect(
              borderRadius: BorderRadius.circular(t.radius.lg),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: t.surface.glassBlur,
                  sigmaY: t.surface.glassBlur,
                ),
                child: panel,
              ),
            )
          : panel,
    );
  }
}

/// The emphasis a button carries — what it does, not what colour it is, so a
/// skin change repaints every button without touching a call site.
enum HcButtonKind {
  /// The one action the dialog exists to perform.
  primary,

  /// A secondary path: Cancel, Close, Skip.
  ghost,

  /// Destructive and irreversible — deleting, unpairing, forgetting.
  danger,
}

/// A button in the house style, sized and coloured from tokens.
class HcButton extends StatelessWidget {
  const HcButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = HcButtonKind.ghost,
    this.icon,
  });

  final String label;

  /// Null disables the button — the standard Flutter contract.
  final VoidCallback? onPressed;
  final HcButtonKind kind;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final enabled = onPressed != null;

    final accent = switch (kind) {
      HcButtonKind.primary => t.accent.active,
      HcButtonKind.danger => t.accent.danger,
      HcButtonKind.ghost => t.surface.onBaseMuted,
    };

    final filled = kind == HcButtonKind.primary;
    // A disabled primary must still read as the primary action, just
    // unavailable — dropping it to the ghost treatment would move the eye.
    final fg = filled
        ? (enabled ? t.accent.onPrimary : t.surface.onBaseMuted)
        : accent;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: filled
            ? (enabled ? accent : t.surface.raised)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(t.radius.pill),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(t.radius.pill),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: t.space.lg,
              vertical: t.space.sm + 2,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radius.pill),
              border: filled
                  ? null
                  : Border.all(
                      color: kind == HcButtonKind.danger
                          ? accent.withValues(alpha: 0.5)
                          : t.stroke.hairline,
                      width: t.stroke.width,
                    ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  SizedBox(width: t.space.sm),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
