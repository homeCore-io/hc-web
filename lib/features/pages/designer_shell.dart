import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/dashboard/canvas_view.dart';
import '../../core/dashboard/free_layer.dart';
import '../../core/dashboard/grid_engine.dart';
import '../../core/models/dashboard.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import 'breakpoint_bar.dart';
import 'card_inspector.dart';
import 'card_library.dart';
import 'page_inspector.dart';
import 'page_background.dart';
import 'page_layers.dart';
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
    required this.selectedIds,
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
    this.onDistribute,
    this.onNudge,
    this.onDuplicate,
    this.onSelectAll,
    required this.items,
    required this.widgetsById,
    required this.onSelectCard,
    required this.onRename,
    required this.canUndo,
    required this.undoLabel,
    required this.onUndo,
    required this.onBackgroundChanged,
    this.onStack,
  });

  final DashboardDefinition dashboard;
  final DashboardBreakpoint breakpoint;
  final List<DashboardLayout>? layouts;
  final DashboardBreakpoint source;
  final int columns;
  final bool saving;
  final bool dirty;
  final int selectedCount;

  /// What is in hand, by id. The count answers "how many"; framing the
  /// selection needs to know *which*, because the rectangle it scrolls to is
  /// the box around those cards and nothing else.
  final Set<String> selectedIds;
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

  /// Spread three or more evenly. Null below three, because there is nothing
  /// to spread — see [GridEngine.distribute].
  final ValueChanged<bool>? onDistribute;

  /// Move the selection by a step, in cells.
  final void Function(int dx, int dy)? onNudge;

  /// Take a copy of everything in hand.
  final VoidCallback? onDuplicate;

  /// Everything on this layout.
  final VoidCallback? onSelectAll;

  /// What is on the page, for the layers strip.
  final List<GridItem> items;
  final Map<String, DashboardWidgetModel> widgetsById;
  final ValueChanged<String> onSelectCard;
  final ValueChanged<String> onRename;

  /// Undo, as a control rather than as a sentence that times out.
  final bool canUndo;

  /// What pressing it will undo, for the tooltip. Null when there is nothing.
  final String? undoLabel;
  final VoidCallback onUndo;

  /// What the page sits on.
  final ValueChanged<DashboardBackground> onBackgroundChanged;

  /// Lift the selection above the grid, put it back, or move it within the
  /// stack. The page owns the arithmetic; this only forwards the request.
  final ValueChanged<StackMove>? onStack;

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

  /// The layers strip starts open. It is one row tall and it is the only thing
  /// that names the elements which draw nothing — closing it by default would
  /// hide the answer to a question you do not know you have yet.
  bool _layersOpen = true;

  /// Space is down, so the canvas is a thing you drag rather than a thing you
  /// arrange. Held here rather than read from [HardwareKeyboard] on each event
  /// because the cursor has to change the moment the key goes down, before any
  /// pointer has moved.
  bool _panArmed = false;

  // Explicit controllers, because both scrollbars need one to stay visible and
  // the horizontal one has to be reachable at all.
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  /// Drag the canvas under the window.
  ///
  /// Both axes at once, because a canvas that only pans vertically is the
  /// problem this is here to solve: the wheel already does that, and the
  /// right-hand edge of a 1600px page is what you cannot get to.
  void _panBy(Offset delta) {
    if (_horizontal.hasClients) {
      final position = _horizontal.position;
      _horizontal
          .jumpTo(panned(position.pixels, delta.dx, position.maxScrollExtent));
    }
    if (_vertical.hasClients) {
      final position = _vertical.position;
      _vertical
          .jumpTo(panned(position.pixels, delta.dy, position.maxScrollExtent));
    }
  }

  /// Stand where you can see what is in hand.
  ///
  /// Two moves in one, and they have to be in that order: pick the scale that
  /// shows the selection whole, then scroll it into the middle. Scrolling first
  /// would aim at extents belonging to the old zoom.
  void _frameSelection(CanvasGeometry geometry, double padding) {
    final bounds = geometry.boundsOf(widget.items, widget.selectedIds);
    // Nothing in hand, or the selection is not on this breakpoint's layout.
    // Doing nothing is right: the alternative is a canvas that jumps somewhere
    // you did not ask for and cannot name.
    if (bounds == null) return;

    final viewport = Size(
      _horizontal.hasClients ? _horizontal.position.viewportDimension : 0,
      // The vertical scroller measures the whole pane; the padding is inside
      // its content, so it is not room the canvas actually gets.
      _vertical.hasClients
          ? _vertical.position.viewportDimension - padding * 2
          : 0,
    );
    final scale = scaleToShow(bounds, viewport,
        min: _minZoom, max: _maxZoom, margin: padding);

    setState(() => _zoom = scale);
    // The scroll extents only tell the truth once the canvas has been laid out
    // at the new scale, so the second half waits a frame.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _centre(bounds, scale, padding));
  }

  void _centre(Rect bounds, double scale, double padding) {
    if (!mounted) return;
    if (_horizontal.hasClients) {
      final position = _horizontal.position;
      _horizontal.jumpTo(centreOn(
        start: bounds.left * scale,
        extent: bounds.width * scale,
        viewport: position.viewportDimension,
        maxScroll: position.maxScrollExtent,
      ));
    }
    if (_vertical.hasClients) {
      final position = _vertical.position;
      _vertical.jumpTo(centreOn(
        // Down by the padding, which is part of the scrolled content on this
        // axis and not on the other one.
        start: bounds.top * scale + padding,
        extent: bounds.height * scale,
        viewport: position.viewportDimension,
        maxScroll: position.maxScrollExtent,
      ));
    }
  }

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

          final layout = widget.layouts
              ?.where((l) => l.breakpoint == widget.breakpoint)
              .firstOrNull;
          // The canvas in pixels, at 1:1. Framing works in these units and
          // applies the scale itself, so a selection lands in the same place
          // whatever you were standing at when you asked.
          final geometry = CanvasGeometry(
            width: width,
            columns: widget.columns,
            rowHeight: layout?.rowHeight ?? 120,
            gap: layout?.gap ?? 12,
          );

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
                onFrameSelection: () => _frameSelection(geometry, t.space.lg),
                canFrame: widget.selectedCount > 0,
                // Align works on one card or on many; distribute needs three.
                onAlign: widget.selectedCount == 0 ? null : widget.onAlign,
                onDistribute:
                    widget.selectedCount < 3 ? null : widget.onDistribute,
                canUndo: widget.canUndo,
                undoLabel: widget.undoLabel,
                onUndo: widget.onUndo,
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
                      child: _CanvasKeys(
                        onNudge: widget.onNudge,
                        onDuplicate: widget.onDuplicate,
                        onSelectAll: widget.onSelectAll,
                        onRemove: widget.selectedCount == 0
                            ? null
                            : widget.onRemoveSelected,
                        onDeselect: widget.onDeselect,
                        onFit: () => setState(() => _zoom = null),
                        onFrameSelection: () =>
                            _frameSelection(geometry, t.space.lg),
                        onPanKey: (down) {
                          if (down == _panArmed) return;
                          setState(() => _panArmed = down);
                        },
                        child: _PanArea(
                          armed: _panArmed,
                          onPan: _panBy,
                          child: Container(
                            color: t.surface.sunken,
                            // The page's own background, behind the canvas: you are
                            // arranging cards *on* it, so it has to be visible
                            // while you arrange them.
                            child: PageBackground(
                              background: widget.dashboard.background,
                              // Two scrollers, because zoom has two directions. The
                              // canvas draws the layout at the width that breakpoint
                              // really has — 1600 for desktop — which the middle pane
                              // is nowhere near once two panels take their 600; and
                              // above Fit it is wider still. Vertical alone would
                              // strand the right-hand edge of the page off-screen
                              // with no way to reach it.
                              // Both bars always drawn, both reachable.
                              //
                              // The nesting alone was not enough: Flutter web draws
                              // no scrollbar for an unmanaged scroll view, and a
                              // mouse wheel only ever reaches the vertical one — so
                              // at any zoom where the canvas is wider than the pane,
                              // the right-hand side of the page existed and could not
                              // be got to. `ScaledCanvas` made the extent honest,
                              // which is precisely what turned a slightly clipped
                              // card into unreachable content.
                              child: Scrollbar(
                                controller: _vertical,
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  controller: _vertical,
                                  padding: EdgeInsets.all(t.space.lg),
                                  child: Scrollbar(
                                    controller: _horizontal,
                                    thumbVisibility: true,
                                    child: SingleChildScrollView(
                                      controller: _horizontal,
                                      scrollDirection: Axis.horizontal,
                                      child: ScaledCanvas(
                                        scale: scale,
                                        child: SizedBox(
                                            width: width, child: widget.canvas),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
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
                      child: widget.selected == null && widget.selectedCount > 1
                          ? _ManySelected(
                              count: widget.selectedCount,
                              onDistribute: widget.selectedCount < 3
                                  ? null
                                  : widget.onDistribute,
                              onAlign: widget.onAlign,
                              onRemove: widget.onRemoveSelected,
                              onDeselect: widget.onDeselect,
                            )
                          : widget.selected == null
                              ? PageInspector(
                                  dashboard: widget.dashboard,
                                  breakpoint: widget.breakpoint,
                                  layout: widget.layouts
                                      ?.where((l) =>
                                          l.breakpoint == widget.breakpoint)
                                      .firstOrNull,
                                  cardCount: widget.cardCount,
                                  onFlowChanged: widget.onFlowChanged,
                                  onBackgroundChanged:
                                      widget.onBackgroundChanged,
                                )
                              : CardInspector(
                                  model: widget.selected!,
                                  onChanged: widget.onChanged,
                                  onRemove: widget.onRemoveSelected,
                                  onClose: widget.onDeselect,
                                  onRename: widget.onRename,
                                  floating:
                                      widget.selectedItem?.floating ?? false,
                                  z: widget.selectedItem?.z ?? 0,
                                  onStack: widget.onStack,
                                ),
                    ),
                  ],
                ),
              ),
              PageLayers(
                items: widget.items,
                widgetsById: widget.widgetsById,
                selectedId: widget.selected?.id,
                onSelect: widget.onSelectCard,
                open: _layersOpen,
                onToggle: () => setState(() => _layersOpen = !_layersOpen),
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
                panning: _panArmed,
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
    required this.onFrameSelection,
    required this.canFrame,
    required this.onAlign,
    this.onDistribute,
    required this.canUndo,
    required this.undoLabel,
    required this.onUndo,
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
  final VoidCallback onFrameSelection;
  final bool canFrame;

  /// Null when nothing is selected — align acts on the selection, and a live
  /// button that quietly does nothing is worse than a dim one.
  final ValueChanged<CanvasAlign>? onAlign;

  /// Null below three selected, for the same reason.
  final ValueChanged<bool>? onDistribute;

  final bool canUndo;
  final String? undoLabel;
  final VoidCallback onUndo;

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
          // Undo first: it is the one control here that is about the past.
          // Dim until there is something to undo, and named — "Undo" alone
          // makes you press it to find out what it does.
          IconButton(
            onPressed: canUndo ? onUndo : null,
            // Material, like the zoom and align controls beside it. HcIcons
            // has no undo glyph and the file's own rule is that a codepoint is
            // verified by rasterising the font, never guessed.
            icon: const Icon(Icons.undo, size: 16),
            tooltip: canUndo
                ? 'Undo ${undoLabel!.toLowerCase()}'
                : 'Nothing to undo',
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(width: t.space.sm),
          // Canvas tools. Align first, because it acts on the thing you have
          // in hand; zoom last, because it acts on where you are standing.
          for (final align in CanvasAlign.values)
            IconButton(
              onPressed: onAlign == null ? null : () => onAlign!(align),
              icon: Icon(align.icon, size: 16),
              tooltip: align.label,
              visualDensity: VisualDensity.compact,
            ),
          // Distribute sits beside align because they are the same kind of
          // move, and stays dim until there are three things to spread — the
          // count is the whole precondition, so the control says it by being
          // unavailable rather than by explaining itself.
          IconButton(
            onPressed: onDistribute == null ? null : () => onDistribute!(true),
            icon: const Icon(Icons.horizontal_distribute, size: 16),
            tooltip: onDistribute == null
                ? 'Spread evenly — pick three or more'
                : 'Spread evenly across',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: onDistribute == null ? null : () => onDistribute!(false),
            icon: const Icon(Icons.vertical_distribute, size: 16),
            tooltip: onDistribute == null
                ? 'Spread evenly — pick three or more'
                : 'Spread evenly down',
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(width: t.space.sm),
          _ZoomControl(
            zoom: zoom,
            effective: effectiveZoom,
            onZoom: onZoom,
            onStep: onZoomStep,
            onFrameSelection: onFrameSelection,
            canFrame: canFrame,
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

/// What the right pane says when you are holding a crowd.
///
/// The inspector edits *a card* — a title, a config, a style — and none of
/// those have a single answer for three cards. Before this the pane fell back
/// to the page's own properties, which was quietly wrong: it looked as though
/// nothing was selected while the canvas showed three cards outlined.
///
/// So it reports the count and offers the operations that *do* mean something
/// for a crowd, which are precisely the ones the toolbar grew for it.
class _ManySelected extends StatelessWidget {
  const _ManySelected({
    required this.count,
    required this.onAlign,
    required this.onDistribute,
    required this.onRemove,
    required this.onDeselect,
  });

  final int count;
  final ValueChanged<CanvasAlign>? onAlign;
  final ValueChanged<bool>? onDistribute;
  final VoidCallback onRemove;
  final VoidCallback onDeselect;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(t.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('$count selected',
                    style: t.text.subtitleStyle.copyWith(
                        color: t.surface.onBase, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                onPressed: onDeselect,
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Let go',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Text('Arrow keys nudge them. Shift-click to add or remove one.',
              style: t.text.captionStyle
                  .copyWith(color: t.surface.onBaseMuted, height: 1.4)),
          SizedBox(height: t.space.md),
          Text('ALIGN',
              style:
                  t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(height: t.space.xs),
          Row(
            children: [
              for (final align in CanvasAlign.values)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: t.space.xs / 2),
                    child: Tooltip(
                      message: align.label,
                      child: OutlinedButton(
                        onPressed:
                            onAlign == null ? null : () => onAlign!(align),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: t.space.xs),
                          minimumSize: Size.zero,
                          side: BorderSide(
                              color: t.stroke.hairline, width: t.stroke.width),
                        ),
                        child:
                            Icon(align.icon, size: 15, color: t.surface.onBase),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: t.space.md),
          Text('SPREAD',
              style:
                  t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(height: t.space.xs),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      onDistribute == null ? null : () => onDistribute!(true),
                  child: const Text('Across'),
                ),
              ),
              SizedBox(width: t.space.xs),
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      onDistribute == null ? null : () => onDistribute!(false),
                  child: const Text('Down'),
                ),
              ),
            ],
          ),
          SizedBox(height: t.space.xs),
          Text(
            onDistribute == null
                ? 'Spreading evenly needs three or more — with two, the one gap '
                    'is already even.'
                : 'The outermost two stay put; everything between them is '
                    'spaced evenly.',
            style: t.text.captionStyle
                .copyWith(color: t.surface.onBaseMuted, height: 1.4),
          ),
          SizedBox(height: t.space.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onRemove,
              child: Text('Remove all $count',
                  style: TextStyle(color: t.accent.danger)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The keyboard, over the canvas and nowhere else.
///
/// **Scoped deliberately.** These bindings live around the canvas rather than
/// around the window, so an arrow key means "nudge the selection" while you are
/// arranging and "move the caret" the moment you are typing a card's name.
/// Shortcuts resolve from the focused node upward, so a focused text field
/// takes its own keys first and this never has to guess.
///
/// Arrows step one cell; with shift, ten — the same pair of gestures every
/// design tool has, and the reason a cell-accurate position no longer needs a
/// drag to reach it.
class _CanvasKeys extends StatelessWidget {
  const _CanvasKeys({
    required this.onNudge,
    required this.onDuplicate,
    required this.onSelectAll,
    required this.onRemove,
    required this.onDeselect,
    required this.onFit,
    required this.onFrameSelection,
    required this.onPanKey,
    required this.child,
  });

  final void Function(int dx, int dy)? onNudge;
  final VoidCallback? onDuplicate;
  final VoidCallback? onSelectAll;
  final VoidCallback? onRemove;
  final VoidCallback onDeselect;
  final VoidCallback onFit;
  final VoidCallback onFrameSelection;

  /// Space went down, or came back up.
  final ValueChanged<bool> onPanKey;
  final Widget child;

  void _step(int dx, int dy) => onNudge?.call(dx, dy);

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-1, 0),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(1, 0),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _step(0, -1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _step(0, 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): () =>
            _step(-10, 0),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): () =>
            _step(10, 0),
        const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): () =>
            _step(0, -10),
        const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): () =>
            _step(0, 10),
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () =>
            onDuplicate?.call(),
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): () =>
            onDuplicate?.call(),
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () =>
            onSelectAll?.call(),
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () =>
            onSelectAll?.call(),
        const SingleActivator(LogicalKeyboardKey.delete): () =>
            onRemove?.call(),
        const SingleActivator(LogicalKeyboardKey.backspace): () =>
            onRemove?.call(),
        const SingleActivator(LogicalKeyboardKey.escape): onDeselect,
        // Bound to the *character*, not to shift-plus-a-digit. On this
        // keyboard those are the same thing; on a layout where the digit row
        // is shifted the other way round they are not, and a shortcut that
        // silently does nothing on someone's keyboard is worse than one they
        // have to find in the menu. Both are also in the zoom menu, which is
        // where anyone finds them the first time.
        const CharacterActivator('!'): onFit,
        const CharacterActivator('@'): onFrameSelection,
      },
      // Autofocus, because the canvas is what you are working in the moment the
      // designer opens — a tool whose keyboard needs a click first is a tool
      // whose keyboard nobody finds.
      child: Focus(
        autofocus: true,
        // Space is held, not pressed, so it cannot be a shortcut: the canvas
        // has to know while it is down and again when it comes up.
        onKeyEvent: (node, event) {
          if (event.logicalKey != LogicalKeyboardKey.space) {
            return KeyEventResult.ignored;
          }
          if (event is KeyDownEvent) onPanKey(true);
          if (event is KeyUpEvent) onPanKey(false);
          // Handled either way, including the repeats, so space does not also
          // reach whatever a button would have done with it.
          return KeyEventResult.handled;
        },
        // Alt-tab away mid-pan and the key-up lands in another window. Without
        // this the canvas stays armed and the next click drags the page
        // instead of selecting a card, with nothing on screen to explain why.
        onFocusChange: (has) {
          if (!has) onPanKey(false);
        },
        child: child,
      ),
    );
  }
}

/// The canvas as something you can drag under the window.
///
/// Two ways in, because they suit different hands. **Middle-drag** works at any
/// time and costs nothing: a plain [Listener] does not consume what it sees, so
/// cards below still get their clicks, and Flutter's pan recognisers only
/// accept the primary button — so a middle-drag on a card cannot also move it.
/// **Space-drag** is the one that needs a mode, and while it is held this puts
/// an opaque layer over the whole canvas: that is what stops the drag reaching
/// a card, and it is also what makes the grab cursor honest, since the cursor
/// would otherwise change over the background and not over a card.
class _PanArea extends StatefulWidget {
  const _PanArea({
    required this.armed,
    required this.onPan,
    required this.child,
  });

  final bool armed;
  final ValueChanged<Offset> onPan;
  final Widget child;

  @override
  State<_PanArea> createState() => _PanAreaState();
}

class _PanAreaState extends State<_PanArea> {
  bool _dragging = false;

  @override
  void didUpdateWidget(_PanArea old) {
    super.didUpdateWidget(old);
    // Space came up mid-drag: the overlay goes away and the pointer stream with
    // it, so nothing else will ever tell us the drag ended.
    if (!widget.armed && _dragging) _dragging = false;
  }

  @override
  Widget build(BuildContext context) {
    final canvas = Listener(
      onPointerMove: (event) {
        if (event.buttons & kMiddleMouseButton != 0) widget.onPan(event.delta);
      },
      child: widget.child,
    );

    if (!widget.armed) return canvas;

    return Stack(
      children: [
        canvas,
        Positioned.fill(
          child: MouseRegion(
            cursor: _dragging
                ? SystemMouseCursors.grabbing
                : SystemMouseCursors.grab,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => setState(() => _dragging = true),
              onPointerMove: (event) => widget.onPan(event.delta),
              onPointerUp: (_) => setState(() => _dragging = false),
              onPointerCancel: (_) => setState(() => _dragging = false),
            ),
          ),
        ),
      ],
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
    required this.panning,
  });

  final int selectedCount;
  final GridItem? item;
  final int columns;
  final GridFlow flow;
  final bool dirty;
  final bool saving;

  /// Space is down. Worth saying because it changes what a drag does — the
  /// same reason the flow is named here — and because the only other signal is
  /// a cursor, which you are not looking at when you are about to drag.
  final bool panning;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final parts = <String>[
      // The zoom is deliberately NOT here. It used to be, back when nothing
      // else on screen said what the scale was; the control in the top bar now
      // shows the same number and can change it, and a status bar that repeats
      // a control is one more thing to keep in step for no gain.
      // First, because while it is true it is the thing that decides what the
      // next drag does.
      if (panning) 'Panning',
      if (selectedCount == 0) 'Nothing selected' else '$selectedCount selected',
      if (item != null) '${item!.w}×${item!.h} at ${item!.x},${item!.y}',
      // Only when it is true. A card in the grid has no height to report and a
      // status bar that says "grid" on every card is a word you stop reading.
      if (item?.floating == true) 'floating · z${item!.z}',
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

/// The two entries in the zoom menu that are rules rather than numbers.
enum _ZoomChoice { fit, selection }

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
    required this.onFrameSelection,
    required this.canFrame,
  });

  final double? zoom;
  final double effective;
  final ValueChanged<double?> onZoom;
  final ValueChanged<int> onStep;

  /// Stand where the selection is. Disabled with nothing in hand, because
  /// there is nowhere to stand.
  final VoidCallback onFrameSelection;
  final bool canFrame;

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
        PopupMenuButton<Object?>(
          // The one place the navigation keys are written down. A shortcut
          // nobody can discover is a shortcut nobody has.
          tooltip: 'Zoom · shift 1 fits, shift 2 frames the selection,\n'
              'space or middle-drag pans',
          onSelected: (choice) {
            if (choice is double) return onZoom(choice);
            if (choice == _ZoomChoice.selection) return onFrameSelection();
            onZoom(null);
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
                value: _ZoomChoice.fit, child: Text('Fit  ·  shift 1')),
            PopupMenuItem(
              value: _ZoomChoice.selection,
              enabled: canFrame,
              child: const Text('Zoom to selection  ·  shift 2'),
            ),
            const PopupMenuDivider(),
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
