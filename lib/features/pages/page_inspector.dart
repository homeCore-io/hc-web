import 'package:flutter/material.dart';

import '../../core/dashboard/grid_engine.dart';
import '../../core/models/dashboard.dart';
import '../../design/components/hc_controls.dart';
import '../../design/tokens.dart';
import '../assets/asset_field.dart';

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
class PageInspector extends StatefulWidget {
  const PageInspector({
    super.key,
    required this.dashboard,
    required this.breakpoint,
    required this.layout,
    required this.cardCount,
    required this.onFlowChanged,
    required this.onComposeChanged,
    required this.snapToGrid,
    required this.onSnapChanged,
    this.onBackgroundChanged,
  });

  final DashboardDefinition dashboard;
  final DashboardBreakpoint breakpoint;
  final DashboardLayout? layout;
  final int cardCount;
  final ValueChanged<GridFlow>? onFlowChanged;

  /// Turn composition on, or hand the layout back to the grid.
  final ValueChanged<bool>? onComposeChanged;

  /// Whether a composed drag is pulled to the cell edges. View state — how you
  /// are working on a page, not a fact about the page.
  final bool snapToGrid;
  final ValueChanged<bool>? onSnapChanged;

  /// Null outside the designer — the page inspector also renders where there is
  /// nothing to save into.
  final ValueChanged<DashboardBackground>? onBackgroundChanged;

  @override
  State<PageInspector> createState() => _PageInspectorState();
}

class _PageInspectorState extends State<PageInspector> {
  /// See [CardInspector]: an unmanaged scroll view draws no scrollbar on web,
  /// so a pane with more in it than fits says nothing about the fact.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = widget.dashboard;
    final layout = widget.layout;
    final breakpoint = widget.breakpoint;
    final cardCount = widget.cardCount;
    final onFlowChanged = widget.onFlowChanged;
    final onBackgroundChanged = widget.onBackgroundChanged;
    final t = HcTokens.of(context);
    final flow = layout?.flow ?? GridFlow.packed;
    final derived = layout?.derivedFrom;

    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scroll,
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
                style: t.text.overlineStyle
                    .copyWith(color: t.surface.onBaseMuted)),
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
            if (widget.onComposeChanged case final onCompose?) ...[
              SizedBox(height: t.space.lg),
              Text('CANVAS',
                  style: t.text.overlineStyle
                      .copyWith(color: t.surface.onBaseMuted)),
              SizedBox(height: t.space.xs),
              _Toggle(
                label: 'Compose freely',
                value: layout?.isComposed ?? false,
                onChanged: derived != null ? null : onCompose,
              ),
              Text(
                derived != null
                    ? 'This layout follows another one, so it has no canvas of '
                        'its own to compose on.'
                    : layout?.isComposed ?? false
                        ? 'Cards sit anywhere on the canvas at any size. The '
                            'grid is still here as something to line up with, '
                            'and the cells are kept alongside so the page still '
                            'opens as a grid anywhere that cannot read a canvas.'
                        : 'Cards are whole cells of the grid. Turn this on to '
                            'put them anywhere and at any size — nothing moves '
                            'when you do.',
                style: t.text.captionStyle
                    .copyWith(color: t.surface.onBaseMuted, height: 1.4),
              ),
              if (layout?.isComposed ?? false) ...[
                SizedBox(height: t.space.xs),
                _Toggle(
                  label: 'Snap to the grid',
                  value: widget.snapToGrid,
                  onChanged: widget.onSnapChanged,
                ),
              ],
            ],
            if (onBackgroundChanged != null) ...[
              SizedBox(height: t.space.lg),
              Text('BACKGROUND',
                  style: t.text.overlineStyle
                      .copyWith(color: t.surface.onBaseMuted)),
              SizedBox(height: t.space.xs),
              _BackgroundControls(
                value: dashboard.background ?? const DashboardBackground(),
                onChanged: onBackgroundChanged,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Image, blur and dim — with the two sliders present from the start.
///
/// They are not "advanced". A photograph behind live content is unreadable
/// without them, so hiding them behind a disclosure would mean the first thing
/// anyone sees after pasting a URL is a page they cannot read, and the fix one
/// click away and invisible.
class _BackgroundControls extends StatefulWidget {
  const _BackgroundControls({required this.value, required this.onChanged});

  final DashboardBackground value;
  final ValueChanged<DashboardBackground> onChanged;

  @override
  State<_BackgroundControls> createState() => _BackgroundControlsState();
}

class _BackgroundControlsState extends State<_BackgroundControls> {
  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final v = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AssetField(
          value: v.image ?? '',
          onChanged: (s) =>
              widget.onChanged(v.copyWith(image: s.isEmpty ? null : s)),
        ),
        SizedBox(height: t.space.xs),
        _Slider(
          label: 'Blur',
          value: v.blur,
          max: 40,
          onChanged: (n) => widget.onChanged(v.copyWith(blur: n)),
        ),
        _Slider(
          label: 'Dim',
          value: v.dim * 100,
          max: 100,
          onChanged: (n) => widget.onChanged(v.copyWith(dim: n / 100)),
        ),
        Text(
          v.isEmpty
              ? 'A picture behind the whole page. Blur and dim are what keep '
                  'the cards readable on top of it.'
              : 'Blurred and dimmed behind the cards; the cards stay sharp.',
          style: t.text.captionStyle
              .copyWith(color: t.surface.onBaseMuted, height: 1.4),
        ),
      ],
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(label,
              style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            max: max,
            divisions: max.round(),
            label: '${value.round()}',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 28,
          child: Text('${value.round()}',
              textAlign: TextAlign.right,
              style: t.text.captionStyle.copyWith(
                  color: t.surface.onBaseMuted,
                  fontFeatures: t.numericFontFeatures)),
        ),
      ],
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

/// A labelled switch, using the house control rather than Material's.
///
/// `SwitchListTile` paints its background on the nearest `Material` ancestor,
/// and this pane is a `DecoratedBox` — which Flutter asserts about, loudly,
/// in every test that opens the designer.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xs / 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: t.text.bodyStyle.copyWith(
                    color: onChanged == null
                        ? t.surface.onBaseMuted
                        : t.surface.onBase)),
          ),
          HcToggle(
            value: value,
            onChanged: onChanged,
            semanticLabel: label,
          ),
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
