import 'package:flutter/material.dart';

import '../../core/dashboard/grid_engine.dart';
import '../../core/models/dashboard.dart';
import '../../design/tokens.dart';

/// The page itself, when no card is selected.
///
/// The right pane used to say "Select a card to change what it shows." and
/// nothing else, which meant a 340px column sat blank for most of a session —
/// a panel that is dead by default teaches you to stop looking at it.
///
/// A design tool's inspector always has a subject: the selection, or the
/// document. This is the document.
///
/// **It is also where the flow control lives**, and that matters more than it
/// looks. Whether gaps are kept was until now settable only as a side effect of
/// dragging a card, and readable only in the status bar. A property of the page
/// that you can trip over but not set is a property nobody controls.
class PageInspector extends StatelessWidget {
  const PageInspector({
    super.key,
    required this.dashboard,
    required this.breakpoint,
    required this.layout,
    required this.cardCount,
    required this.onFlowChanged,
  });

  final DashboardDefinition dashboard;
  final DashboardBreakpoint breakpoint;
  final DashboardLayout? layout;
  final int cardCount;
  final ValueChanged<GridFlow>? onFlowChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final flow = layout?.flow ?? GridFlow.packed;
    final derived = layout?.derivedFrom;

    return SingleChildScrollView(
      padding: EdgeInsets.all(t.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(dashboard.name,
              style: t.text.subtitleStyle.copyWith(
                  color: t.surface.onBase, fontWeight: FontWeight.w600)),
          Text('This page',
              style:
                  t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(height: t.space.md),
          _Row(label: 'Cards', value: '$cardCount'),
          _Row(label: 'Columns', value: '${layout?.columns ?? 12}'),
          _Row(
            label: 'Arranging',
            value: switch (breakpoint) {
              DashboardBreakpoint.mobile => 'Mobile',
              DashboardBreakpoint.tablet => 'Tablet',
              DashboardBreakpoint.desktop => 'Desktop',
              DashboardBreakpoint.tv => 'Wall',
            },
          ),
          SizedBox(height: t.space.md),
          Text('SPACE',
              style:
                  t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(height: t.space.xs),
          if (derived != null)
            Text(
              'This layout follows another one, so it is packed for its own '
              'width. Arrange it by hand to give it gaps of its own.',
              style: t.text.captionStyle
                  .copyWith(color: t.surface.onBaseMuted, height: 1.4),
            )
          else ...[
            _Choice(
              value: flow,
              onChanged: onFlowChanged,
            ),
            SizedBox(height: t.space.xs),
            Text(
              flow == GridFlow.free
                  ? 'Cards stay where you put them. Empty space is part of the '
                      'design.'
                  : 'Cards float up to close gaps, the way a dashboard packs '
                      'itself.',
              style: t.text.captionStyle
                  .copyWith(color: t.surface.onBaseMuted, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: t.text.bodySmallStyle
                    .copyWith(color: t.surface.onBaseMuted)),
          ),
          Text(value,
              style: t.text.bodySmallStyle.copyWith(
                  color: t.surface.onBase,
                  fontFeatures: t.numericFontFeatures)),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.value, required this.onChanged});

  final GridFlow value;
  final ValueChanged<GridFlow>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Row(
      children: [
        for (final option in GridFlow.values)
          Padding(
            padding: EdgeInsets.only(right: t.space.xs),
            child: Semantics(
              button: true,
              selected: option == value,
              child: GestureDetector(
                onTap: onChanged == null ? null : () => onChanged!(option),
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: t.space.sm, vertical: t.space.xs / 2),
                  decoration: BoxDecoration(
                    color: option == value ? t.surface.raised : null,
                    borderRadius: BorderRadius.circular(t.radius.pill),
                    border: Border.all(
                      color:
                          option == value ? t.accent.active : t.stroke.hairline,
                      width: t.stroke.width,
                    ),
                  ),
                  // Named for what they do, not for the enum: "packed" and
                  // "free" are the document's words, not a person's.
                  child: Text(
                    option == GridFlow.free ? 'Keep gaps' : 'Close gaps',
                    style: t.text.captionStyle.copyWith(
                        color: option == value
                            ? t.surface.onBase
                            : t.surface.onBaseMuted),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
