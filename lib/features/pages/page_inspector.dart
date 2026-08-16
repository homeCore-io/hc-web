import 'package:flutter/material.dart';

import '../../core/dashboard/grid_engine.dart';
import '../../core/models/dashboard.dart';
import '../../design/tokens.dart';
import '../assets/asset_field.dart';
import 'inspector_controls.dart';

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
    required this.onFrameChanged,
    required this.snapToGrid,
    required this.onSnapChanged,
    this.sourceComposed = false,
    this.onBackgroundChanged,
  });

  final DashboardDefinition dashboard;
  final DashboardBreakpoint breakpoint;
  final DashboardLayout? layout;

  /// Whether the layout this one follows is itself a composition.
  ///
  /// Passed in rather than read off [dashboard], because the answer has to
  /// come from the *draft*: turning composition on for the desktop and then
  /// looking at the phone must say so before anything is saved.
  final bool sourceComposed;
  final int cardCount;
  final ValueChanged<GridFlow>? onFlowChanged;

  /// Turn composition on, or hand the layout back to the grid.
  final ValueChanged<bool>? onComposeChanged;

  /// Resize the canvas, or change what its height promises.
  final ValueChanged<DashboardFrame>? onFrameChanged;

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
    // Whether the layout this one follows is itself a composition. Following
    // an ordinary layout loses nothing; following a composed one loses the
    // free positions, and that is worth saying out loud.
    final sourceComposed = derived != null && widget.sourceComposed;

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
              InspectorToggle(
                label: 'Compose freely',
                value: layout?.isComposed ?? false,
                onChanged: derived != null ? null : onCompose,
              ),
              Text(
                derived != null
                    ? sourceComposed
                        // The one case where following costs something
                        // visible. Saying it here, where there is room, is
                        // what stops the phone reading as lost work.
                        ? 'This layout follows a composed one, so it has no '
                            'canvas of its own. That composition is packed '
                            'into these cells — the same cards in the same '
                            'order, at whatever size fits this grid. Arrange '
                            'it by hand to give it a canvas of its own.'
                        : 'This layout follows another one, so it has no '
                            'canvas of its own to compose on.'
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
              if (layout?.frame case final frame?) ...[
                SizedBox(height: t.space.xs),
                InspectorToggle(
                  label: 'Snap to the grid',
                  value: widget.snapToGrid,
                  onChanged: widget.onSnapChanged,
                ),
                SizedBox(height: t.space.md),
                _FrameControls(
                  frame: frame,
                  onChanged: widget.onFrameChanged,
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
        InspectorSlider(
          label: 'Blur',
          value: v.blur,
          max: 40,
          onChanged: (n) => widget.onChanged(v.copyWith(blur: n)),
        ),
        InspectorSlider(
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
/// The canvas's own size, and what its height promises.
///
/// **Presets first, then the numbers.** A wall layout is almost always a
/// display somebody owns, and the useful question is *which screen* — not what
/// 3840 divided by anything is. The fields are there for the case a preset does
/// not cover, which is real but rare.
class _FrameControls extends StatefulWidget {
  const _FrameControls({required this.frame, required this.onChanged});

  final DashboardFrame frame;
  final ValueChanged<DashboardFrame>? onChanged;

  @override
  State<_FrameControls> createState() => _FrameControlsState();
}

class _FrameControlsState extends State<_FrameControls> {
  late final _width = TextEditingController(text: _round(widget.frame.width));
  late final _height = TextEditingController(text: _round(widget.frame.height));

  /// The sizes people actually have on a wall, plus the shape a page is when
  /// it is meant to be read rather than watched.
  static const _presets = <String, (double, double)>{
    '720p': (1280, 720),
    '1080p': (1920, 1080),
    '1440p': (2560, 1440),
    '4K': (3840, 2160),
  };

  static String _round(double v) => v.toStringAsFixed(0);

  @override
  void didUpdateWidget(_FrameControls old) {
    super.didUpdateWidget(old);
    // Only when the frame really changed, or every rebuild would fight the
    // person typing into the field.
    if (old.frame.width != widget.frame.width) {
      _width.text = _round(widget.frame.width);
    }
    if (old.frame.height != widget.frame.height) {
      _height.text = _round(widget.frame.height);
    }
  }

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _commit() {
    final w = double.tryParse(_width.text);
    final h = double.tryParse(_height.text);
    // A canvas with no size would divide by zero on the way to the screen, and
    // core rejects it. Refusing here rather than clamping keeps the field
    // saying what was typed, so a stray keystroke is visible instead of
    // silently becoming a 1.
    if (w == null || h == null || w <= 0 || h <= 0) {
      _width.text = _round(widget.frame.width);
      _height.text = _round(widget.frame.height);
      return;
    }
    widget.onChanged?.call(widget.frame.copyWith(width: w, height: h));
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final onChanged = widget.onChanged;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('SIZE',
            style: t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted)),
        SizedBox(height: t.space.xs),
        Row(
          children: [
            Expanded(
                child: _Number(
                    label: 'Width', controller: _width, onDone: _commit)),
            SizedBox(width: t.space.xs),
            Expanded(
                child: _Number(
                    label: 'Height', controller: _height, onDone: _commit)),
          ],
        ),
        SizedBox(height: t.space.xs),
        Wrap(
          spacing: t.space.xs,
          runSpacing: t.space.xs / 2,
          children: [
            for (final entry in _presets.entries)
              _Preset(
                label: entry.key,
                selected: widget.frame.width == entry.value.$1 &&
                    widget.frame.height == entry.value.$2,
                onTap: onChanged == null
                    ? null
                    : () => onChanged(widget.frame.copyWith(
                        width: entry.value.$1, height: entry.value.$2)),
              ),
          ],
        ),
        SizedBox(height: t.space.xs),
        Text(
          'Changing the size does not move anything. A bigger canvas is more '
          'room, not a rearrangement.',
          style: t.text.captionStyle
              .copyWith(color: t.surface.onBaseMuted, height: 1.4),
        ),
        SizedBox(height: t.space.md),
        Text('HEIGHT',
            style: t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted)),
        SizedBox(height: t.space.xs),
        Row(
          children: [
            for (final fit in DashboardFrameFit.values)
              Padding(
                padding: EdgeInsets.only(right: t.space.xs),
                child: _Preset(
                  label: switch (fit) {
                    DashboardFrameFit.scroll => 'Grows',
                    DashboardFrameFit.fixed => 'Fixed',
                  },
                  selected: widget.frame.fit == fit,
                  onTap: onChanged == null
                      ? null
                      : () => onChanged(widget.frame.copyWith(fit: fit)),
                ),
              ),
          ],
        ),
        SizedBox(height: t.space.xs),
        Text(
          switch (widget.frame.fit) {
            DashboardFrameFit.scroll =>
              'The height is a starting point. The page carries on below it if '
                  'there is more on it, and scrolls.',
            DashboardFrameFit.fixed =>
              'The whole canvas is shown at once, scaled to whatever it is on, '
                  'and nothing scrolls. What a wall display is.',
          },
          style: t.text.captionStyle
              .copyWith(color: t.surface.onBaseMuted, height: 1.4),
        ),
      ],
    );
  }
}

class _Number extends StatelessWidget {
  const _Number({
    required this.label,
    required this.controller,
    required this.onDone,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: t.text.bodyStyle.copyWith(
          color: t.surface.onBase, fontFeatures: t.numericFontFeatures),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (_) => onDone(),
      // Also on losing focus: a number typed and then clicked away from is a
      // number that was meant.
      onTapOutside: (_) {
        onDone();
        FocusManager.instance.primaryFocus?.unfocus();
      },
    );
  }
}

class _Preset extends StatelessWidget {
  const _Preset({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: t.space.sm, vertical: t.space.xs / 2),
          decoration: BoxDecoration(
            color: selected ? t.surface.raised : null,
            borderRadius: BorderRadius.circular(t.radius.pill),
            border: Border.all(
              color: selected ? t.accent.active : t.stroke.hairline,
              width: t.stroke.width,
            ),
          ),
          child: Text(
            label,
            style: t.text.captionStyle.copyWith(
                color: selected ? t.surface.onBase : t.surface.onBaseMuted),
          ),
        ),
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
