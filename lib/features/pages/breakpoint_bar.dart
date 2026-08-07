import 'package:flutter/material.dart';

import '../../core/models/dashboard.dart';
import '../../design/tokens.dart';

/// Which layout you are arranging, and what its relationship to the others is.
///
/// This bar is the whole point of the per-device work being visible. A save
/// writes to exactly one breakpoint and recomputes the ones following it, and
/// none of that is legible from the canvas — four layouts of the same page look
/// alike until you notice one of them is a different shape.
///
/// The wireframe in `dashboard-editor-plan.md` put a palette-and-inspector rail
/// down the left. This is deliberately a bar instead: a rail cannot exist at
/// 430px, and brief principle 4 says branch on shell rather than viewport, so a
/// chrome that only works on one of the three shells is the wrong chrome. The
/// bar reads the same on a phone, a laptop and a wall.
String breakpointLabel(DashboardBreakpoint b) => switch (b) {
      DashboardBreakpoint.mobile => 'Mobile',
      DashboardBreakpoint.tablet => 'Tablet',
      DashboardBreakpoint.desktop => 'Desktop',
      DashboardBreakpoint.tv => 'Wall',
    };

class BreakpointBar extends StatelessWidget {
  const BreakpointBar({
    super.key,
    required this.layouts,
    required this.selected,
    required this.source,
    required this.onSelect,
    required this.onRevert,
  });

  /// The working layouts, in whatever state the draft has them.
  final List<DashboardLayout> layouts;
  final DashboardBreakpoint selected;

  /// The breakpoint the others may follow. Never offered a revert of its own —
  /// it cannot follow itself.
  final DashboardBreakpoint source;

  final ValueChanged<DashboardBreakpoint> onSelect;

  /// Hand the selected layout back to [source]. Null when that is not on offer:
  /// the source itself, or a layout already following.
  final VoidCallback? onRevert;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final present = [
      for (final b in DashboardBreakpoint.values)
        if (layouts.any((l) => l.breakpoint == b)) b,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final b in present) ...[
                _Segment(
                  label: breakpointLabel(b),
                  state: _stateOf(b),
                  selected: b == selected,
                  onTap: () => onSelect(b),
                ),
                SizedBox(width: t.space.xs),
              ],
            ],
          ),
        ),
        if (onRevert != null) ...[
          SizedBox(height: t.space.xs),
          _RevertRow(source: source, onRevert: onRevert!),
        ],
      ],
    );
  }

  _SegmentState _stateOf(DashboardBreakpoint b) {
    final layout = layouts.where((l) => l.breakpoint == b).firstOrNull;
    if (b == source) return _SegmentState.source;
    if (layout?.derivedFrom != null) return _SegmentState.following;
    return _SegmentState.own;
  }
}

enum _SegmentState { source, following, own }

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.state,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final _SegmentState state;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    // "Follows" is the quiet state and "Yours" the notable one — a layout
    // someone arranged by hand is the one that will not move when you edit
    // desktop, and that is the surprise worth marking.
    final (caption, captionColor) = switch (state) {
      _SegmentState.source => (null, null),
      _SegmentState.following => ('Follows', t.surface.onBaseMuted),
      _SegmentState.own => ('Yours', t.accent.active),
    };

    return Semantics(
      button: true,
      selected: selected,
      label: caption == null ? label : '$label, $caption',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.radius.sm),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: t.density.minTapTarget),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: t.space.sm, vertical: t.space.xs),
            decoration: BoxDecoration(
              color: selected ? t.surface.raised : null,
              borderRadius: BorderRadius.circular(t.radius.sm),
              border: Border.all(
                color: selected ? t.accent.active : t.stroke.hairline,
                width: t.stroke.width,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: t.text.bodySmallStyle.copyWith(
                    color: selected ? t.surface.onBase : t.surface.onBaseMuted,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (caption != null)
                  Text(
                    caption,
                    style: t.text.captionStyle.copyWith(color: captionColor),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RevertRow extends StatelessWidget {
  const _RevertRow({required this.source, required this.onRevert});

  final DashboardBreakpoint source;
  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    // No icon: the vocabulary has no revert glyph, and guessing a Phosphor
    // codepoint risks a blank box that the glyph-fallback ratchet exists to
    // catch. The label says the whole thing anyway.
    return TextButton(
      onPressed: onRevert,
      child: Text(
        'Follow ${breakpointLabel(source).toLowerCase()} again',
        style: t.text.captionStyle.copyWith(color: t.accent.active),
      ),
    );
  }
}
