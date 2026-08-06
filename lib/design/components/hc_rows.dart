import 'package:flutter/material.dart';

import '../tokens.dart';
import 'hc_controls.dart';
import 'hc_surface.dart';

/// The row list every settings-shaped screen needs, and every one of them had
/// written for itself.
///
/// System, Data, Maintenance and Configuration each carried a private
/// `_RowsSurface`/`_KvRow`/`_Card` pair — same idea, four geometries, four
/// hover behaviours (mostly none). They were built on [HcSurface], so they were
/// the right *colour* and nothing else, which is how Administration ended up
/// looking like Material in a dark box while `HcChip`, `HcToggle` and
/// `HcIconButton` sat unused next door.
///
/// The house pages settled this already: rows are separated by a hairline and
/// react to the pointer, rather than each being boxed into its own card. These
/// carry that same language into the system half of Manage.
class HcRows extends StatelessWidget {
  const HcRows(this.rows, {super.key});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    if (rows.isEmpty) return const SizedBox.shrink();
    return HcSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Padding(
                // Inset from the icon gutter, so the rule reads as separating
                // rows in one list rather than slicing the card in half.
                padding: EdgeInsets.only(left: t.space.md * 2 + 18),
                child: Divider(height: 1, color: t.stroke.hairline),
              ),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// One row: an icon gutter, a label (with optional second line), and whatever
/// belongs on the right — a value, a toggle, a chip, a button.
///
/// Hover is only drawn when the row actually does something. A settings screen
/// is mostly inert readouts, and lighting those up on hover promises a click
/// that never comes.
class HcRow extends StatefulWidget {
  const HcRow({
    super.key,
    this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final IconData? icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Tints the icon and label — for rows that destroy something.
  final bool danger;

  @override
  State<HcRow> createState() => _HcRowState();
}

class _HcRowState extends State<HcRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final interactive = widget.onTap != null;
    final fg = widget.danger ? t.accent.danger : t.surface.onBase;

    final body = AnimatedContainer(
      duration: t.motion.d(t.motion.fast),
      curve: t.motion.curve,
      constraints: BoxConstraints(minHeight: t.density.rowHeight),
      padding: EdgeInsets.symmetric(
        horizontal: t.space.md,
        vertical: t.space.sm + 2,
      ),
      color: interactive && _hover ? t.surface.sunken : Colors.transparent,
      child: Row(
        children: [
          if (widget.icon != null) ...[
            Icon(
              widget.icon,
              size: 18,
              color: widget.danger ? t.accent.danger : t.surface.onBaseMuted,
            ),
            SizedBox(width: t.space.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: t.text.bodyStyle.copyWith(color: fg),
                ),
                if (widget.subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      widget.subtitle!,
                      style: t.text.bodySmallStyle.copyWith(
                        color: t.surface.onBaseMuted,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.trailing != null) ...[
            SizedBox(width: t.space.md),
            widget.trailing!,
          ],
          if (interactive) ...[
            SizedBox(width: t.space.sm),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: t.surface.onBaseMuted),
          ],
        ],
      ),
    );

    if (!interactive) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, child: body),
    );
  }
}

/// A read-only fact: label on the left, value on the right, figures aligned by
/// the skin's tabular numerals so a column of counts stays a column.
class HcKvRow extends StatelessWidget {
  const HcKvRow({
    super.key,
    this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.tone,
  });

  final IconData? icon;
  final String label;
  final String value;
  final String? subtitle;

  /// Colours the value — for a figure that means something is wrong.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return HcRow(
      icon: icon,
      label: label,
      subtitle: subtitle,
      trailing: Text(
        value,
        style: t.text.bodyStyle.copyWith(
          color: tone ?? t.surface.onBase,
          fontWeight: FontWeight.w600,
          fontFeatures: t.numericFontFeatures,
        ),
      ),
    );
  }
}

/// A setting you flip — the app's own [HcToggle], not Material's switch.
class HcToggleRow extends StatelessWidget {
  const HcToggleRow({
    super.key,
    this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData? icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return HcRow(
      icon: icon,
      label: label,
      subtitle: subtitle,
      trailing: HcToggle(
        value: value,
        onChanged: onChanged,
        semanticLabel: label,
      ),
    );
  }
}

/// Placeholder rows while the real ones load.
///
/// Shaped like the content that replaces them, so the pane does not jump — the
/// spinner-in-a-box these pages used told you nothing about what was coming and
/// resized the moment it arrived.
class HcRowsLoading extends StatelessWidget {
  const HcRowsLoading({super.key, this.rows = 3});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return HcRows([
      for (var i = 0; i < rows; i++)
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: t.space.md,
            vertical: t.space.sm + 6,
          ),
          child: Row(
            children: [
              const HcShimmer(width: 18, height: 18),
              SizedBox(width: t.space.md),
              // Staggered so it reads as a list of different things rather
              // than a loading bar.
              HcShimmer(width: 90.0 + (i % 3) * 34, height: 12),
              const Spacer(),
              const HcShimmer(width: 46, height: 12),
            ],
          ),
        ),
    ]);
  }
}

/// What a section shows when it has nothing, or could not load.
///
/// One widget for both because they are the same shape and were written three
/// times each (`_Empty`, `_Error`, `_ErrorSurface`) across these pages.
class HcRowsNotice extends StatelessWidget {
  const HcRowsNotice({
    super.key,
    required this.title,
    this.detail,
    this.icon,
    this.danger = false,
    this.action,
  });

  const HcRowsNotice.error({
    super.key,
    required this.title,
    this.detail,
    this.action,
  })  : icon = Icons.error_outline,
        danger = true;

  final String title;
  final String? detail;
  final IconData? icon;
  final bool danger;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return HcSurface(
      padding: EdgeInsets.all(t.space.md),
      child: Row(
        children: [
          Icon(
            icon ?? Icons.inbox_outlined,
            size: 18,
            color: danger ? t.accent.danger : t.surface.onBaseMuted,
          ),
          SizedBox(width: t.space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: t.text.bodyStyle.copyWith(color: t.surface.onBase),
                ),
                if (detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      detail!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: t.text.bodySmallStyle.copyWith(
                        color: t.surface.onBaseMuted,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (action != null) ...[SizedBox(width: t.space.md), action!],
        ],
      ),
    );
  }
}
