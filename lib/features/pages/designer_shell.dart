import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/dashboard/grid_engine.dart';
import '../../core/models/dashboard.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import 'breakpoint_bar.dart';
import 'card_inspector.dart';
import 'card_library.dart';
import 'page_inspector.dart';
import 'scaled_canvas.dart';

/// The design surface: a tool, not a page.
///
/// Phase 2 of `designer-plan.md`. What separates this from the editor it grew
/// out of is not the panel count — it is that the frame does not move.
///
/// **Nothing but a pane scrolls.** The window is a fixed frame: a top bar, a
/// row of three panes each with its own scroller, a status bar on the floor.
/// Scroll the canvas and the elements list stays put; that is the difference
/// between an application and a web page, and it is a layout decision rather
/// than a decoration one.
///
/// **Both panes stay open.** The editor showed one rail that was the library or
/// the inspector depending on selection, which meant adding a card hid the
/// thing you were about to configure and configuring one hid everything you
/// could add. A tool keeps its tools out.
///
/// **The status bar is the honest one.** Selection, size in cells, the column
/// count, and whether there is unsaved work — the things you would otherwise
/// have to guess at or discover by pressing something.
class DesignerShell extends StatefulWidget {
  const DesignerShell({
    super.key,
    required this.dashboard,
    required this.breakpoint,
    required this.layouts,
    required this.source,
    required this.columns,
    required this.saving,
    required this.dirty,
    required this.selectedCount,
    required this.selected,
    required this.selectedItem,
    required this.consequence,
    required this.onSelectBreakpoint,
    required this.onRevert,
    required this.onPick,
    required this.onChanged,
    required this.onRemoveSelected,
    required this.onDeselect,
    required this.onSave,
    required this.canvas,
    required this.canvasWidth,
    required this.cardCount,
    required this.onFlowChanged,
    required this.onAlign,
  });

  final DashboardDefinition dashboard;
  final DashboardBreakpoint breakpoint;
  final List<DashboardLayout>? layouts;
  final DashboardBreakpoint source;
  final int columns;
  final bool saving;
  final bool dirty;
  final int selectedCount;
  final DashboardWidgetModel? selected;
  final GridItem? selectedItem;
  final String? consequence;
  final ValueChanged<DashboardBreakpoint> onSelectBreakpoint;
  final VoidCallback? onRevert;
  final ValueChanged<DashboardWidgetModel> onPick;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onRemoveSelected;
  final VoidCallback onDeselect;
  final VoidCallback onSave;
  final Widget canvas;

  /// The width this breakpoint's layout is drawn at, or null when it is the
  /// viewport's own.
  final double? canvasWidth;
  final int cardCount;
  final ValueChanged<GridFlow>? onFlowChanged;

  /// Move the selection to one edge of the canvas, or to its middle.
  final ValueChanged<CanvasAlign>? onAlign;

  /// Fixed, because the frame is fixed. Panes that resized themselves would
  /// make the canvas scale jump while you worked in it.
  static const _libraryWidth = 260.0;
  static const _inspectorWidth = 340.0;

  @override
  State<DesignerShell> createState() => _DesignerShellState();
}

class _DesignerShellState extends State<DesignerShell> {
  /// The chosen zoom, or null for **Fit** — which is the default and was the
  /// only behaviour before. Fit is a *rule* rather than a number: it keeps
  /// re-deriving as the window changes, which a remembered 66% would not.
  ///
  /// This is view state, not document state. It never reaches the draft, is
  /// never saved, and does not mark the page dirty: how close you are standing
  /// to a page is not a fact about the page.
  double? _zoom;

  /// 50% to 200%, the range §3.1 asks for so a wall layout is designable on a
  /// laptop. Fit can go below the floor — a 1600px canvas in a 700px pane is
  /// 44% — because Fit is a promise to show the whole width, and refusing to
  /// keep it would be worse than a small number.
  static const _minZoom = 0.5;
  static const _maxZoom = 2.0;
  static const _stops = <double>[0.5, 0.75, 1.0, 1.5, 2.0];

  /// The next stop past [from] in the direction of [delta].
  ///
  /// Stepping from Fit lands on the nearest stop rather than on Fit ± 25%, so
  /// the first press off Fit gives a round number instead of 91%.
  static double _step(double from, int delta) {
    if (delta > 0) {
      for (final stop in _stops) {
        if (stop > from + 0.001) return stop;
      }
      return _maxZoom;
    }
    for (final stop in _stops.reversed) {
      if (stop < from - 0.001) return stop;
    }
    return _minZoom;
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return Scaffold(
      backgroundColor: t.surface.base,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, frame) {
          // One scale for the whole shell: the canvas is drawn at it and the
          // status bar reports it. Computed here rather than inside the canvas
          // because a designer that silently shrinks what you are arranging,
          // without saying by how much, is lying about the size of it.
          final available = frame.maxWidth -
              DesignerShell._libraryWidth -
              DesignerShell._inspectorWidth -
              t.space.lg * 2;
          // Wall has no preview width — it *is* the big end — so it takes the
          // pane's own width. Before zoom that made it the one breakpoint the
          // scale never applied to; now it simply starts at 1:1 like the rest.
          final width =
              widget.canvasWidth ?? (available <= 0 ? 1.0 : available);
          final fit = (available / width).clamp(_minZoom, 1.0);
          final scale = _zoom ?? fit;

          return Column(
            children: [
              _TopBar(
                title: widget.dashboard.name,
                layouts: widget.layouts,
                breakpoint: widget.breakpoint,
                source: widget.source,
                saving: widget.saving,
                dirty: widget.dirty,
                onSelectBreakpoint: widget.onSelectBreakpoint,
                onRevert: widget.onRevert,
                onSave: widget.onSave,
                onLeave: () => context.go('/pages/${widget.dashboard.id}'),
                zoom: _zoom,
                effectiveZoom: scale,
                onZoom: (z) => setState(() => _zoom = z),
                onZoomStep: (delta) =>
                    setState(() => _zoom = _step(scale, delta)),
                onAlign: widget.selected == null ? null : widget.onAlign,
              ),
              if (widget.consequence case final line?)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                      horizontal: t.space.md, vertical: t.space.xs),
                  color: t.surface.sunken,
                  child: Text(line,
                      style: t.text.captionStyle
                          .copyWith(color: t.surface.onBaseMuted)),
                ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Pane(
                      width: DesignerShell._libraryWidth,
                      border: Border(
                          right: BorderSide(
                              color: t.stroke.hairline, width: t.stroke.width)),
                      child: CardLibrary(onPick: widget.onPick),
                    ),
                    // The canvas is the only thing allowed to be large. It
                    // scrolls inside itself; the frame around it never moves.
                    Expanded(
                      child: Container(
                        color: t.surface.sunken,
                        // Two scrollers, because zoom has two directions. The
                        // canvas draws the layout at the width that breakpoint
                        // really has — 1600 for desktop — which the middle pane
                        // is nowhere near once two panels take their 600; and
                        // above Fit it is wider still. Vertical alone would
                        // strand the right-hand edge of the page off-screen
                        // with no way to reach it.
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(t.space.lg),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ScaledCanvas(
                              scale: scale,
                              child:
                                  SizedBox(width: width, child: widget.canvas),
                            ),
                          ),
                        ),
                      ),
                    ),
                    _Pane(
                      width: DesignerShell._inspectorWidth,
                      border: Border(
                          left: BorderSide(
                              color: t.stroke.hairline, width: t.stroke.width)),
                      child: widget.selected == null
                          ? PageInspector(
                              dashboard: widget.dashboard,
                              breakpoint: widget.breakpoint,
                              layout: widget.layouts
                                  ?.where(
                                      (l) => l.breakpoint == widget.breakpoint)
                                  .firstOrNull,
                              cardCount: widget.cardCount,
                              onFlowChanged: widget.onFlowChanged,
                            )
                          : CardInspector(
                              model: widget.selected!,
                              onChanged: widget.onChanged,
                              onRemove: widget.onRemoveSelected,
                              onClose: widget.onDeselect,
                            ),
                    ),
                  ],
                ),
              ),
              _StatusBar(
                selectedCount: widget.selectedCount,
                item: widget.selectedItem,
                columns: widget.columns,
                flow: widget.layouts
                        ?.where((l) => l.breakpoint == widget.breakpoint)
                        .firstOrNull
                        ?.flow ??
                    GridFlow.packed,
                dirty: widget.dirty,
                saving: widget.saving,
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({required this.width, required this.border, required this.child});

  final double width;
  final Border border;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      width: width,
      decoration: BoxDecoration(color: t.surface.base, border: border),
      padding: EdgeInsets.all(t.space.sm),
      child: child,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.layouts,
    required this.breakpoint,
    required this.source,
    required this.saving,
    required this.dirty,
    required this.onSelectBreakpoint,
    required this.onRevert,
    required this.onSave,
    required this.onLeave,
    required this.zoom,
    required this.effectiveZoom,
    required this.onZoom,
    required this.onZoomStep,
    required this.onAlign,
  });

  final String title;
  final List<DashboardLayout>? layouts;
  final DashboardBreakpoint breakpoint;
  final DashboardBreakpoint source;
  final bool saving;
  final bool dirty;
  final ValueChanged<DashboardBreakpoint> onSelectBreakpoint;
  final VoidCallback? onRevert;
  final VoidCallback onSave;
  final VoidCallback onLeave;

  /// The chosen zoom, or null when it is Fit.
  final double? zoom;

  /// What Fit actually resolves to, so the control can show a number even when
  /// no number was chosen.
  final double effectiveZoom;
  final ValueChanged<double?> onZoom;
  final ValueChanged<int> onZoomStep;

  /// Null when nothing is selected — align acts on the selection, and a live
  /// button that quietly does nothing is worse than a dim one.
  final ValueChanged<CanvasAlign>? onAlign;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface.raised,
        border: Border(
            bottom:
                BorderSide(color: t.stroke.hairline, width: t.stroke.width)),
      ),
      padding:
          EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.xs),
      child: Row(
        children: [
          IconButton(
            onPressed: onLeave,
            icon: const Icon(HcIcons.caretLeft, size: 16),
            tooltip: 'Back to the page',
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(width: t.space.xs),
          Text(title,
              style: t.text.subtitleStyle.copyWith(
                  color: t.surface.onBase, fontWeight: FontWeight.w600)),
          SizedBox(width: t.space.md),
          if (layouts != null)
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: BreakpointBar(
                  layouts: layouts!,
                  selected: breakpoint,
                  source: source,
                  onSelect: onSelectBreakpoint,
                  onRevert: onRevert,
                ),
              ),
            ),
          const Spacer(),
          // Canvas tools. Align first, because it acts on the thing you have
          // in hand; zoom last, because it acts on where you are standing.
          for (final align in CanvasAlign.values)
            IconButton(
              onPressed: onAlign == null ? null : () => onAlign!(align),
              icon: Icon(align.icon, size: 16),
              tooltip: align.label,
              visualDensity: VisualDensity.compact,
            ),
          SizedBox(width: t.space.sm),
          _ZoomControl(
            zoom: zoom,
            effective: effectiveZoom,
            onZoom: onZoom,
            onStep: onZoomStep,
          ),
          SizedBox(width: t.space.md),
          if (dirty)
            Padding(
              padding: EdgeInsets.only(right: t.space.sm),
              child: Text('Unsaved',
                  style: t.text.captionStyle.copyWith(color: t.accent.active)),
            ),
          FilledButton(
            onPressed: saving ? null : onSave,
            child: Text(saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}

/// The floor of the window. Says what is true rather than what to do.
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.selectedCount,
    required this.item,
    required this.columns,
    required this.flow,
    required this.dirty,
    required this.saving,
  });

  final int selectedCount;
  final GridItem? item;
  final int columns;
  final GridFlow flow;
  final bool dirty;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final parts = <String>[
      // The zoom is deliberately NOT here. It used to be, back when nothing
      // else on screen said what the scale was; the control in the top bar now
      // shows the same number and can change it, and a status bar that repeats
      // a control is one more thing to keep in step for no gain.
      if (selectedCount == 0) 'Nothing selected' else '$selectedCount selected',
      if (item != null) '${item!.w}×${item!.h} at ${item!.x},${item!.y}',
      '$columns columns',
      // Named, because it changes what a drag does and there is nothing else
      // on screen that would tell you it flipped.
      flow == GridFlow.free ? 'gaps kept' : 'gaps closed',
      if (saving) 'Saving…' else if (dirty) 'Unsaved changes' else 'Saved',
    ];

    return Container(
      decoration: BoxDecoration(
        color: t.surface.raised,
        border: Border(
            top: BorderSide(color: t.stroke.hairline, width: t.stroke.width)),
      ),
      padding:
          EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.xs),
      child: Row(
        children: [
          for (final part in parts) ...[
            Text(part,
                style: t.text.captionStyle.copyWith(
                    color: t.surface.onBaseMuted,
                    fontFeatures: t.numericFontFeatures)),
            if (part != parts.last)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: t.space.sm),
                child: Text('·',
                    style: t.text.captionStyle
                        .copyWith(color: t.surface.onBaseMuted)),
              ),
          ],
        ],
      ),
    );
  }
}

/// Where a card can be put, relative to the canvas rather than to its
/// neighbours.
///
/// §3.1 asks for align *and* distribute. Distribute is not here, and the reason
/// is that it has no meaning for one card: it spreads three or more evenly, so
/// it needs the multi-select §5.1 deferred. Align does not — "put this at the
/// left edge", "centre this" is a single-card operation, and it is the one that
/// cannot be done accurately by dragging: centring a 5-wide card in 12 columns
/// lands on 3.5, and a drag can only ever pick 3 or 4.
enum CanvasAlign {
  left('Align left', Icons.align_horizontal_left),
  centre('Centre', Icons.align_horizontal_center),
  right('Align right', Icons.align_horizontal_right);

  const CanvasAlign(this.label, this.icon);

  final String label;
  final IconData icon;

  /// The column this alignment puts a card of width [w] at, in a grid of
  /// [columns]. Never negative, and never past the right edge, so a card wider
  /// than the grid still lands somewhere legal.
  int xFor(int w, int columns) {
    final room = columns - w;
    if (room <= 0) return 0;
    return switch (this) {
      CanvasAlign.left => 0,
      // Rounds down: with an odd remainder something has to give, and the
      // extra column on the right reads as centred where the extra on the
      // left reads as nudged.
      CanvasAlign.centre => room ~/ 2,
      CanvasAlign.right => room,
    };
  }
}

/// `−  100%  +`, with the middle opening the stops.
///
/// The number is always shown, including under Fit, because "Fit" alone
/// answers *how* the scale was chosen and not *what it is* — and the second is
/// the one you need when you are judging whether a card is too small.
class _ZoomControl extends StatelessWidget {
  const _ZoomControl({
    required this.zoom,
    required this.effective,
    required this.onZoom,
    required this.onStep,
  });

  final double? zoom;
  final double effective;
  final ValueChanged<double?> onZoom;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final percent = '${(effective * 100).round()}%';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => onStep(-1),
          icon: const Icon(Icons.remove, size: 15),
          tooltip: 'Zoom out',
          visualDensity: VisualDensity.compact,
        ),
        PopupMenuButton<double?>(
          tooltip: 'Zoom',
          onSelected: onZoom,
          itemBuilder: (context) => [
            const PopupMenuItem(value: null, child: Text('Fit')),
            for (final stop in _DesignerShellState._stops)
              PopupMenuItem(
                value: stop,
                child: Text('${(stop * 100).round()}%'),
              ),
          ],
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: t.space.sm, vertical: t.space.xs),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radius.sm),
              border:
                  Border.all(color: t.stroke.hairline, width: t.stroke.width),
            ),
            child: Text(
              zoom == null ? 'Fit · $percent' : percent,
              style: t.text.captionStyle.copyWith(
                  color: t.surface.onBase, fontFeatures: t.numericFontFeatures),
            ),
          ),
        ),
        IconButton(
          onPressed: () => onStep(1),
          icon: const Icon(Icons.add, size: 15),
          tooltip: 'Zoom in',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
