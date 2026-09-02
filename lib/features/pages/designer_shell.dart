import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/dashboard/canvas_view.dart';
import '../../core/dashboard/design_tools.dart';
import '../../core/dashboard/device_slot.dart';
import '../../core/dashboard/frame.dart';
import '../../core/dashboard/free_layer.dart';
import '../../core/dashboard/grid_engine.dart';
import '../../core/dashboard/transform.dart';
import '../../core/dashboard/groups.dart';
import '../../core/models/dashboard.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import 'breakpoint_bar.dart';
import 'canvas_rulers.dart';
import 'card_inspector.dart';
import 'assets_panel.dart';
import 'devices_panel.dart';
import 'wiring_panel.dart';
import 'inspector_controls.dart';
import 'layer_tree_panel.dart';
import 'page_inspector.dart';
import 'page_background.dart';
import 'scaled_canvas.dart';
import 'tool_palette.dart';

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
    required this.emptyStart,
    required this.canvasWidth,
    required this.cardCount,
    required this.onFlowChanged,
    required this.onComposeChanged,
    required this.onFrameChanged,
    required this.snapToGrid,
    required this.onSnapChanged,
    required this.onAlign,
    this.onDistribute,
    this.onNudge,
    this.onDuplicate,
    this.onCopy,
    this.onPaste,
    this.onSelectAll,
    this.onGroup,
    this.onUngroup,
    this.onRenameGroup,
    this.onEnterGroup,
    this.groupBox,
    this.onGroupBox,
    this.onSelectMany,
    this.onEnterGroupId,
    required this.groupInHand,
    required this.inside,
    required this.items,
    required this.widgetsById,
    required this.onSelectCard,
    required this.onRename,
    required this.canUndo,
    required this.undoLabel,
    required this.onUndo,
    required this.canRedo,
    required this.redoLabel,
    required this.onRedo,
    required this.history,
    required this.historyAt,
    required this.onJumpHistory,
    required this.onBackgroundChanged,
    required this.tool,
    required this.onTool,
    this.onStack,
    this.onRect,
    this.onWire,
    this.onRotate,
    this.onFade,
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

  /// Replace the selection outright. The layers tree selects a whole group in
  /// one click, which no per-card callback can express.
  final ValueChanged<Set<String>>? onSelectMany;

  /// Step inside the group that [id] belongs to.
  final ValueChanged<String>? onEnterGroupId;

  /// What is in hand, in the toolbar sense.
  ///
  /// Held by the screen rather than by the strip, because it changes what the
  /// canvas does with a drag and what a bare letter key means. A tool that only
  /// the toolbar knew about would be a toolbar that highlights buttons.
  final DesignTool tool;
  final ValueChanged<DesignTool> onTool;

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

  /// What a page with nothing on it offers instead of a canvas.
  ///
  /// Rendered **unscaled**, in place of the board rather than on it: these are
  /// chrome, not content. Drawn inside the canvas they inherit its zoom, so at
  /// the Fit a 1600px layout gets on a laptop they came out at half size in the
  /// corner of an empty board — an offer you have to lean in to read.
  final Widget? emptyStart;

  /// The width this breakpoint's layout is drawn at, or null when it is the
  /// viewport's own.
  final double? canvasWidth;
  final int cardCount;
  final ValueChanged<GridFlow>? onFlowChanged;

  /// Turn composition on for this layout, or hand it back to the grid.
  final ValueChanged<bool>? onComposeChanged;

  /// Resize the canvas, or change what its height promises.
  final ValueChanged<DashboardFrame>? onFrameChanged;

  /// Whether a composed drag is pulled to the cell edges.
  final bool snapToGrid;
  final ValueChanged<bool>? onSnapChanged;

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

  /// Put what is in hand on the system clipboard, and take whatever is there
  /// and land it on this page. Null when there is nothing to copy, but paste
  /// stays live with an empty selection — that is the whole point of it.
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;

  /// Hold the selection as one thing, or stop.
  final VoidCallback? onGroup;
  final VoidCallback? onUngroup;
  final ValueChanged<String>? onRenameGroup;

  /// Step into the group in hand, so its members can be picked apart.
  final VoidCallback? onEnterGroup;

  /// The one group every selected element is in, as a path, or null.
  final String? groupInHand;

  /// How the group in hand is styled, or null while it is only a name.
  final GroupBox? groupBox;

  /// Restyle the group in hand.
  final ValueChanged<GroupBox>? onGroupBox;

  /// The group you have stepped into, as a path. Null at the top of the page.
  final String? inside;

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

  /// The other direction. Undo without it is a stack you can walk off the end
  /// of — one press too many and the change is gone.
  final bool canRedo;
  final String? redoLabel;
  final VoidCallback onRedo;

  /// Every position the draft has stood in, oldest first, and which one it is
  /// standing in now.
  final List<HistoryEntry> history;
  final int historyAt;
  final ValueChanged<int> onJumpHistory;

  /// What the page sits on.
  final ValueChanged<DashboardBackground> onBackgroundChanged;

  /// Lift the selection above the grid, put it back, or move it within the
  /// stack. The page owns the arithmetic; this only forwards the request.
  final ValueChanged<StackMove>? onStack;

  /// Point one unwired reference at a device. Null outside the designer.
  ///
  /// Three arguments rather than a model, because the panel is editing ONE
  /// field of one element and a whole config would invite a caller to send
  /// back more than the person changed.
  final void Function(String widgetId, String field, String id)? onWire;

  /// Move or resize the selected element by typing. Null outside the designer,
  /// and ignored for a card the grid engine packs, which has no x to be told.
  final ValueChanged<DashboardRect>? onRect;

  /// Turn or fade the selected card. Null outside the designer.
  final ValueChanged<double?>? onRotate;
  final ValueChanged<double?>? onFade;

  /// Fixed, because the frame is fixed. Panes that resized themselves would
  /// make the canvas scale jump while you worked in it.
  static const _libraryWidth = 260.0;
  static const _inspectorWidth = 340.0;

  @override
  State<DesignerShell> createState() => _DesignerShellState();
}

class _DesignerShellState extends State<DesignerShell> {
  /// Whether each side panel is out.
  ///
  /// Both, because a laptop laying out a wall display is spending four hundred
  /// pixels of a fourteen-hundred-pixel window on furniture, and the canvas is
  /// the only thing on this screen that is actually the work. The tool rail is
  /// deliberately not one of these: you are always holding a tool.
  bool _leftOpen = true;
  bool _rightOpen = true;

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

  /// Everything in the window that is not canvas: the top bar, the layers
  /// strip, the status bar and the horizontal ruler.
  ///
  /// An estimate, and deliberately one. Measuring it exactly would mean laying
  /// the canvas out twice — and the only thing it feeds is the *initial* scale
  /// of a fixed canvas, where being a little conservative shows the whole page
  /// with a margin rather than clipping it.
  static const _chromeHeight = 150.0;

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

  /// Does the layout on screen follow one that is a composition?
  ///
  /// Read from the draft rather than the saved document, so turning
  /// composition on for the desktop and stepping straight to the phone says so
  /// before anything is saved.
  bool get _followsAComposition {
    final layouts = widget.layouts;
    if (layouts == null) return false;
    final from = layouts
        .where((l) => l.breakpoint == widget.breakpoint)
        .firstOrNull
        ?.derivedFrom;
    if (from == null) return false;
    return layouts.where((l) => l.breakpoint == from).firstOrNull?.isComposed ??
        false;
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
              // Nor is the tool strip. Left out, Fit would pick a scale a strip
              // too wide — the same mistake the ruler taught, one pane later.
              ToolPalette.width -
              // The ruler down the left-hand edge is not canvas. Left out of
              // this, Fit would pick a scale twenty pixels too wide and quietly
              // stop meaning what it says.
              CanvasRuler.thickness -
              t.space.lg * 2;
          // Wall has no preview width — it *is* the big end — so it takes the
          // pane's own width. Before zoom that made it the one breakpoint the
          // scale never applied to; now it simply starts at 1:1 like the rest.
          final width =
              widget.canvasWidth ?? (available <= 0 ? 1.0 : available);

          final layout = widget.layouts
              ?.where((l) => l.breakpoint == widget.breakpoint)
              .firstOrNull;

          // Fit means *show the whole thing*, and for a fixed canvas the whole
          // thing has a height. Width alone would cut the bottom off a wall
          // layout — which is precisely the arrangement nobody can check
          // without walking across the room to the wall it is for.
          //
          // The pane's height is not known until the row below has laid out, so
          // it is taken from the frame we are in: everything above and below
          // the canvas is fixed chrome, and being a few pixels out here shows
          // up as a scale, not as a broken layout.
          final double fit;
          if (layout?.frame case final composed?
              when composed.fit == DashboardFrameFit.fixed) {
            final tall = frame.maxHeight - _chromeHeight - t.space.lg * 2;
            // **Not clamped to the zoom floor.** A 4K canvas in this pane is
            // 22%, and refusing to go below 50% would show three quarters of a
            // wall while still calling itself Fit. The floor exists so the
            // *stops* stay usable; Fit is a promise about what you can see, and
            // a promise that quietly stops applying at some size is worse than
            // a small number. Only a hair above zero, so a preposterous canvas
            // still has a scale rather than vanishing.
            fit = frameScale(composed, Size(available, tall)).clamp(0.02, 1.0);
          } else {
            // Not clamped to the zoom floor either, for the reason the fixed
            // branch above gives: Fit is a promise about what you can see, and
            // the floor exists so the *stops* stay usable. Adding the tool
            // strip is what made this matter — it took the desktop preview in
            // a 1500-pixel window from 52% to 49%, and the clamp turned "the
            // whole width" into "the whole width, minus twelve pixels you can
            // scroll to but are not told about".
            fit = (available / width).clamp(0.02, 1.0);
          }
          final scale = _zoom ?? fit;
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
                canRedo: widget.canRedo,
                redoLabel: widget.redoLabel,
                onRedo: widget.onRedo,
                history: widget.history,
                historyAt: widget.historyAt,
                onJumpHistory: widget.onJumpHistory,
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
                    // **The rail is the outermost thing on the left.** It is
                    // the one piece of furniture that is never put away — you
                    // are always holding a tool, even if it is Select — so it
                    // sits outside the panel that comes and goes. Every drawing
                    // application since MacPaint has put it against the window
                    // edge for the same reason.
                    ToolPalette(tool: widget.tool, onTool: widget.onTool),
                    if (_leftOpen)
                      _Pane(
                        width: DesignerShell._libraryWidth,
                        border: Border(
                            right: BorderSide(
                                color: t.stroke.hairline,
                                width: t.stroke.width)),
                        child: _LeftRail(
                          items: widget.items,
                          widgetsById: widget.widgetsById,
                          selectedIds: widget.selectedIds,
                          onSelectMany: widget.onSelectMany,
                          onEnterGroupId: widget.onEnterGroupId,
                          onPick: widget.onPick,
                          tool: widget.tool,
                          onClose: () => setState(() => _leftOpen = false),
                        ),
                      )
                    else
                      _PaneHandle(
                        icon: Icons.chevron_right,
                        tooltip: 'Layers, devices and pictures',
                        onTap: () => setState(() => _leftOpen = true),
                      ),
                    // The canvas is the only thing allowed to be large. It
                    // scrolls inside itself; the frame around it never moves.
                    // The canvas, with what is not wired yet above it.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Above the canvas rather than in the panel beside
                          // it: the panel holds what the HOUSE has, and this
                          // holds what this PAGE is still missing. It is also a
                          // job you finish, and it disappears when you have.
                          if (widget.onWire case final onWire?)
                            WiringPanel(
                              gaps: wiringGaps(widget.widgetsById.values),
                              onWire: onWire,
                              onSelect: (id) => widget.onSelectMany?.call({id}),
                            ),
                          Expanded(
                            child: _CanvasKeys(
                              onNudge: widget.onNudge,
                              onDuplicate: widget.onDuplicate,
                              onCopy: widget.onCopy,
                              onPaste: widget.onPaste,
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
                              onGroup: widget.onGroup,
                              onUngroup: widget.onUngroup,
                              onUndo: widget.canUndo ? widget.onUndo : null,
                              onRedo: widget.canRedo ? widget.onRedo : null,
                              onTool: widget.onTool,
                              child: _Ruled(
                                geometry: geometry,
                                scale: scale,
                                lead: t.space.lg,
                                horizontal: _horizontal,
                                vertical: _vertical,
                                items: widget.items,
                                selected: widget.selectedIds,
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
                                              child: widget.emptyStart == null
                                                  ? ScaledCanvas(
                                                      scale: scale,
                                                      child: SizedBox(
                                                          width: width,
                                                          child: widget.canvas),
                                                    )
                                                  : SizedBox(
                                                      // The pane's own width, so the
                                                      // offer is centred in what you
                                                      // are looking at rather than in
                                                      // a board that is not there.
                                                      width: available,
                                                      child: widget.emptyStart,
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
                          ),
                        ],
                      ),
                    ),
                    if (!_rightOpen)
                      _PaneHandle(
                        icon: Icons.chevron_left,
                        tooltip: 'The inspector',
                        onTap: () => setState(() => _rightOpen = true),
                      ),
                    if (_rightOpen)
                      _Pane(
                        width: DesignerShell._inspectorWidth,
                        onClose: () => setState(() => _rightOpen = false),
                        border: Border(
                            left: BorderSide(
                                color: t.stroke.hairline,
                                width: t.stroke.width)),
                        child: widget.selected == null &&
                                widget.selectedCount > 1
                            ? _ManySelected(
                                count: widget.selectedCount,
                                onDistribute: widget.selectedCount < 3
                                    ? null
                                    : widget.onDistribute,
                                onAlign: widget.onAlign,
                                onRemove: widget.onRemoveSelected,
                                onDeselect: widget.onDeselect,
                                groupInHand: widget.groupInHand,
                                onGroup: widget.onGroup,
                                onUngroup: widget.onUngroup,
                                onRenameGroup: widget.onRenameGroup,
                                onEnterGroup: widget.onEnterGroup,
                                groupBox: widget.groupBox,
                                onGroupBox: widget.onGroupBox,
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
                                    onComposeChanged: widget.onComposeChanged,
                                    onFrameChanged: widget.onFrameChanged,
                                    snapToGrid: widget.snapToGrid,
                                    onSnapChanged: widget.onSnapChanged,
                                    sourceComposed: _followsAComposition,
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
                                    rotation: widget.selectedItem?.rotation,
                                    opacity: widget.selectedItem?.opacity,
                                    rect: widget.selectedItem?.rect,
                                    onRect: widget.onRect,
                                    onRotate: widget.onRotate,
                                    onFade: widget.onFade,
                                  ),
                      ),
                  ],
                ),
              ),
              // The bottom strip that used to be here is **deleted**, not
              // moved: the rail's Layers tab says the same names and more, with
              // the grouping shown and a row you can actually hit. Two lists of
              // one page is one list too many, and the strip was the one to
              // give — it cost a band of height off the canvas to say less.
              //
              // `PageLayers` had no other caller, so it went with it. The tests
              // that pinned its behaviour now point at the tree, because the
              // behaviour is the same and only its home changed.
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
                groupInHand: widget.groupInHand,
                inside: widget.inside,
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({
    required this.width,
    required this.border,
    required this.child,
    this.onClose,
  });

  final double width;
  final Border border;
  final Widget child;

  /// Put this pane away. Null when the pane closes itself from inside — the
  /// left one does, because its tab strip is a better place for the control
  /// than a chevron floating above it.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      width: width,
      decoration: BoxDecoration(color: t.surface.base, border: border),
      padding: EdgeInsets.all(t.space.sm),
      child: onClose == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: _CollapseButton(
                    icon: Icons.chevron_right,
                    tooltip: 'Hide',
                    onTap: onClose!,
                  ),
                ),
                Expanded(child: child),
              ],
            ),
    );
  }
}

/// A pane that has been put away: a strip you can push to bring it back.
///
/// Narrow rather than absent, because a panel with no way back is a panel
/// somebody loses. Twenty-two pixels is the whole cost of being able to
/// reopen it, against the two hundred and something it gives the canvas.
class _PaneHandle extends StatelessWidget {
  const _PaneHandle({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      width: 22,
      decoration: BoxDecoration(
        color: t.surface.base,
        border: Border.symmetric(
          vertical: BorderSide(color: t.stroke.hairline, width: t.stroke.width),
        ),
      ),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          child: Icon(icon, size: 15, color: t.surface.onBaseMuted),
        ),
      ),
    );
  }
}

class _CollapseButton extends StatelessWidget {
  const _CollapseButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: t.radius.smR,
        child: Padding(
          padding: EdgeInsets.all(t.space.xs),
          child: Icon(icon, size: 15, color: t.surface.onBaseMuted),
        ),
      ),
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
    required this.canRedo,
    required this.redoLabel,
    required this.onRedo,
    required this.history,
    required this.historyAt,
    required this.onJumpHistory,
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
  final bool canRedo;
  final String? redoLabel;
  final VoidCallback onRedo;
  final List<HistoryEntry> history;
  final int historyAt;
  final ValueChanged<int> onJumpHistory;

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
                ? 'Undo ${undoLabel!.toLowerCase()}  ·  ctrl Z'
                : 'Nothing to undo',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: canRedo ? onRedo : null,
            icon: const Icon(Icons.redo, size: 16),
            tooltip: canRedo
                ? 'Redo ${redoLabel!.toLowerCase()}  ·  ctrl shift Z'
                : 'Nothing to redo',
            visualDensity: VisualDensity.compact,
          ),
          _HistoryControl(
            entries: history,
            at: historyAt,
            onJump: onJumpHistory,
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

/// Grouping, in the pane that already talks about a crowd.
///
/// Two states rather than two panels: a selection that is not yet a group
/// offers to become one, and a selection that *is* one names itself and offers
/// the two things you can do to it. Splitting these into separate surfaces
/// would hide the only control that creates a group behind knowing it exists.
class _GroupSection extends StatefulWidget {
  const _GroupSection({
    required this.path,
    required this.count,
    required this.onGroup,
    required this.onUngroup,
    required this.onRename,
    required this.onEnter,
    required this.box,
    required this.onBox,
  });

  final String? path;
  final int count;
  final VoidCallback? onGroup;
  final VoidCallback? onUngroup;
  final ValueChanged<String>? onRename;
  final VoidCallback? onEnter;

  /// How this group is styled, or null while it is only a name.
  final GroupBox? box;

  /// Restyle it. Null means the surface has nowhere to write — the phone's
  /// in-place editor has no document to save a container into.
  final ValueChanged<GroupBox>? onBox;

  @override
  State<_GroupSection> createState() => _GroupSectionState();
}

class _GroupSectionState extends State<_GroupSection> {
  late final TextEditingController _name =
      TextEditingController(text: _label());

  String _label() => widget.path == null ? '' : nameOf(widget.path!);

  @override
  void didUpdateWidget(_GroupSection old) {
    super.didUpdateWidget(old);
    // Only when the group itself changed. Rewriting the field on every rebuild
    // would fight the person typing in it, and a rename lands as a new path —
    // so the check has to be on the path, not on the text.
    if (old.path != widget.path) _name.text = _label();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final path = widget.path;
    final box = widget.box;

    if (path == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: widget.onGroup,
            icon: const Icon(Icons.folder_outlined, size: 15),
            label: const Text('Group'),
          ),
          SizedBox(height: t.space.xs),
          Text(
            'One click will then hold all ${widget.count} of them. '
            'Double-click to go inside and get at one.',
            style: t.text.captionStyle
                .copyWith(color: t.surface.onBaseMuted, height: 1.4),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('GROUP',
            style: t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted)),
        SizedBox(height: t.space.xs),
        TextField(
          controller: _name,
          style: t.text.bodyStyle.copyWith(color: t.surface.onBase),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.folder_outlined, size: 15),
            prefixIconConstraints:
                BoxConstraints(minWidth: t.space.lg, minHeight: 0),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: widget.onRename,
          // Also on losing focus: a name typed and then clicked away from is a
          // name that was meant.
          onTapOutside: (_) {
            if (_name.text.trim() != _label()) {
              widget.onRename?.call(_name.text);
            }
            FocusManager.instance.primaryFocus?.unfocus();
          },
        ),
        if (parentOf(path) case final parent?) ...[
          SizedBox(height: t.space.xs),
          Text('in $parent',
              style:
                  t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
        ],
        SizedBox(height: t.space.xs),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.onEnter,
                child: const Text('Go inside'),
              ),
            ),
            SizedBox(width: t.space.xs),
            Expanded(
              child: OutlinedButton(
                onPressed: widget.onUngroup,
                child: const Text('Ungroup'),
              ),
            ),
          ],
        ),
        if (widget.onBox case final write?) ...[
          SizedBox(height: t.space.md),
          Text('CONTAINER',
              style:
                  t.text.overlineStyle.copyWith(color: t.surface.onBaseMuted)),
          SizedBox(height: t.space.xs),
          // The switch that turns a name into a body. Off is not a missing
          // setting, it is what a group has always been — so the copy says what
          // turning it on *does* rather than naming the field.
          InspectorToggle(
            label: 'Draw a box around it',
            value: box != null,
            onChanged: (on) => write(
              on
                  ? GroupBox(path: path, padding: t.space.md)
                  : GroupBox(path: path),
            ),
          ),
          if (box case final styled?) ...[
            SizedBox(height: t.space.xs),
            InspectorSlider(
              label: 'Padding',
              value: styled.padding,
              max: 64,
              onChanged: (v) => write(styled.copyWith(padding: v)),
            ),
            InspectorSlider(
              label: 'Corner',
              value: styled.radius ?? 0,
              max: 48,
              onChanged: (v) =>
                  write(styled.copyWith(radius: v <= 0 ? null : v)),
            ),
            SizedBox(height: t.space.xs),
            InspectorToggle(
              label: 'Clip what sticks out',
              value: styled.clip,
              onChanged: (v) => write(styled.copyWith(clip: v)),
            ),
            SizedBox(height: t.space.xs),
            // The parent transform, and the reason it is *here* rather than in
            // a section of its own: in this document a group having an entry at
            // all is what makes it a container, so a group cannot be turned
            // without being one. Turning a cluster of cards that has no
            // container would need a box that draws nothing, and every entry
            // draws — see `page_grid.dart`.
            InspectorSlider(
              label: 'Turn',
              value: styled.rotation ?? 0,
              min: -180,
              max: 180,
              suffix: '°',
              // Back to none rather than to zero: a group at exactly 0° and a
              // group nobody turned are the same picture, and only one of them
              // adds a key to the document.
              onChanged: (v) =>
                  write(styled.copyWith(rotation: rotationFromControl(v))),
            ),
            InspectorSlider(
              label: 'Fade',
              // Shown as a percentage and stored as a fraction, as everywhere
              // else: every renderer takes a fraction.
              value: opacityToControl(styled.opacity),
              max: 100,
              suffix: '%',
              onChanged: (v) =>
                  write(styled.copyWith(opacity: opacityFromControl(v))),
            ),
            SizedBox(height: t.space.xs),
            Text(
              'Members turn about the group, and fade with it.',
              style: t.text.captionStyle
                  .copyWith(color: t.surface.onBaseMuted, height: 1.4),
            ),
            SizedBox(height: t.space.xs),
            Text(
              styled.rect == null
                  ? 'The box fits its members and follows them as they move.'
                  : 'The box is where you put it. Members move inside it.',
              style: t.text.captionStyle
                  .copyWith(color: t.surface.onBaseMuted, height: 1.4),
            ),
          ],
        ],
      ],
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
    required this.groupInHand,
    required this.onGroup,
    required this.onUngroup,
    required this.onRenameGroup,
    required this.onEnterGroup,
    required this.groupBox,
    required this.onGroupBox,
  });

  final int count;
  final ValueChanged<CanvasAlign>? onAlign;
  final ValueChanged<bool>? onDistribute;
  final VoidCallback onRemove;
  final VoidCallback onDeselect;

  /// The group all of them are in, or null when they are not one group.
  final String? groupInHand;
  final VoidCallback? onGroup;
  final VoidCallback? onUngroup;
  final ValueChanged<String>? onRenameGroup;
  final VoidCallback? onEnterGroup;
  final GroupBox? groupBox;
  final ValueChanged<GroupBox>? onGroupBox;

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
          _GroupSection(
            path: groupInHand,
            count: count,
            onGroup: onGroup,
            onUngroup: onUngroup,
            onRename: onRenameGroup,
            onEnter: onEnterGroup,
            box: groupBox,
            onBox: onGroupBox,
          ),
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

/// The left rail: what is on the page, and what you can add to it.
///
/// **Layers is the default tab, and that is the point of the change.** The rail
/// used to be the card library and nothing else — Rooms, Kinds, a search box —
/// so the permanent furniture of a design tool was a catalogue of things you
/// have not put on the page yet. Adding is something you do in bursts;
/// selecting, grouping and finding are what you do continuously.
///
/// Two tabs, not four. The mock has Assets and Styles beside these, and both
/// are real destinations — but a tab that opens an empty panel is a worse
/// answer than a tab that is not there yet, so they arrive when they have
/// something behind them.
class _LeftRail extends StatefulWidget {
  const _LeftRail({
    required this.tool,
    required this.onClose,
    required this.items,
    required this.widgetsById,
    required this.selectedIds,
    required this.onPick,
    this.onSelectMany,
    this.onEnterGroupId,
  });

  /// What is in your hand. The Devices tab needs it: picking a device places
  /// whatever the held tool makes of it.
  final DesignTool tool;

  /// Put the whole panel away.
  final VoidCallback onClose;

  final List<GridItem> items;
  final Map<String, DashboardWidgetModel> widgetsById;
  final Set<String> selectedIds;
  final ValueChanged<DashboardWidgetModel> onPick;
  final ValueChanged<Set<String>>? onSelectMany;
  final ValueChanged<String>? onEnterGroupId;

  @override
  State<_LeftRail> createState() => _LeftRailState();
}

/// The three things the left panel holds.
///
/// **These are the mockup's, and the mockup is right about why.** The panel is
/// for what this *house* has — its layers, its devices, its pictures. What you
/// can *draw* is the rail, and what you can *place from a catalogue* is one
/// tool on that rail. An "Add" tab holding a catalogue of card types put a
/// third answer beside those two and made rooms and kinds look like things you
/// drop, which is exactly the gesture that was wrong.
enum _Panel {
  layers('Layers'),
  devices('Devices'),
  assets('Assets');

  const _Panel(this.label);
  final String label;
}

class _LeftRailState extends State<_LeftRail> {
  _Panel _panel = _Panel.layers;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final tab in _Panel.values)
              _RailTab(
                label: tab.label,
                on: _panel == tab,
                onTap: () => setState(() => _panel = tab),
              ),
            const Spacer(),
            _CollapseButton(
              icon: Icons.chevron_left,
              tooltip: 'Hide the panel',
              onTap: widget.onClose,
            ),
          ],
        ),
        Divider(height: t.stroke.width, color: t.stroke.hairline),
        Expanded(
          child: switch (_panel) {
            _Panel.layers => LayerTreePanel(
                items: widget.items,
                widgetsById: widget.widgetsById,
                selectedIds: widget.selectedIds,
                onSelect: (ids) => widget.onSelectMany?.call(ids),
                onEnterGroup: widget.onEnterGroupId,
              ),
            _Panel.devices =>
              DevicesPanel(tool: widget.tool, onPick: widget.onPick),
            _Panel.assets => AssetsPanel(onPick: widget.onPick),
          },
        ),
      ],
    );
  }
}

class _RailTab extends StatelessWidget {
  const _RailTab({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: t.space.sm),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: on ? t.accent.active : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: t.text.overlineStyle.copyWith(
              color: on ? t.surface.onBase : t.surface.onBaseMuted,
            ),
          ),
        ),
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
    required this.onCopy,
    required this.onPaste,
    required this.onSelectAll,
    required this.onRemove,
    required this.onDeselect,
    required this.onFit,
    required this.onFrameSelection,
    required this.onPanKey,
    required this.onGroup,
    required this.onUngroup,
    required this.onUndo,
    required this.onRedo,
    required this.onTool,
    required this.child,
  });

  final void Function(int dx, int dy)? onNudge;
  final VoidCallback? onDuplicate;
  final VoidCallback? onSelectAll;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final VoidCallback? onRemove;
  final VoidCallback onDeselect;
  final VoidCallback onFit;
  final VoidCallback onFrameSelection;

  /// Space went down, or came back up.
  final ValueChanged<bool> onPanKey;
  final VoidCallback? onGroup;
  final VoidCallback? onUngroup;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  /// A bare letter picked a tool.
  final ValueChanged<DesignTool> onTool;

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
        // Copy and paste, which duplicate is not: ⌘D repeats a card on the
        // page it is already on, and the usual way anybody builds a second
        // page is out of parts of the first.
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () =>
            onCopy?.call(),
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () =>
            onCopy?.call(),
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () =>
            onPaste?.call(),
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () =>
            onPaste?.call(),
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () =>
            onSelectAll?.call(),
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () =>
            onSelectAll?.call(),
        const SingleActivator(LogicalKeyboardKey.delete): () =>
            onRemove?.call(),
        const SingleActivator(LogicalKeyboardKey.backspace): () =>
            onRemove?.call(),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          // Escape means "put it down", and a tool in hand is the thing most
          // in the way — a canvas where clicking keeps making rectangles and
          // Escape only clears the selection is a canvas you feel trapped in.
          onTool(DesignTool.select);
          onDeselect();
        },
        // Bound to the *character*, not to shift-plus-a-digit. On this
        // keyboard those are the same thing; on a layout where the digit row
        // is shifted the other way round they are not, and a shortcut that
        // silently does nothing on someone's keyboard is worse than one they
        // have to find in the menu. Both are also in the zoom menu, which is
        // where anyone finds them the first time.
        const CharacterActivator('!'): onFit,
        const CharacterActivator('@'): onFrameSelection,
        // Both spellings, because this is one of the few shortcuts people
        // arrive already knowing and the modifier differs by platform.
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true): () =>
            onGroup?.call(),
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): () =>
            onGroup?.call(),
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true, shift: true):
            () => onUngroup?.call(),
        const SingleActivator(LogicalKeyboardKey.keyG,
            control: true, shift: true): () => onUngroup?.call(),
        // Undo had no shortcut at all — it was a button in the top bar and
        // nothing else, which for the most-pressed key in any editor is a gap
        // rather than a preference.
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
            onUndo?.call(),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
            onUndo?.call(),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            () => onRedo?.call(),
        const SingleActivator(LogicalKeyboardKey.keyZ,
            control: true, shift: true): () => onRedo?.call(),
        // The other spelling of redo, which half the world's editors use.
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
            onRedo?.call(),
        // The tools, on bare letters — V, T, R, L and the rest, exactly where
        // every design application puts them. Bare letters are safe here for
        // the reason at the top of this class: these bindings are around the
        // canvas, so a focused text field takes its own keys first and typing
        // a card's name still types letters.
        for (final tool in DesignTool.values)
          CharacterActivator(tool.shortcut.toLowerCase()): () => onTool(tool),
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

/// The canvas with a ruler down two of its edges.
///
/// Both are driven by the scroll controllers rather than living inside them:
/// a ruler that scrolled with the page would leave the page it measures. They
/// rebuild on every scroll notification, which is why this listens to the
/// controllers directly instead of the shell rebuilding whole.
class _Ruled extends StatelessWidget {
  const _Ruled({
    required this.geometry,
    required this.scale,
    required this.lead,
    required this.horizontal,
    required this.vertical,
    required this.items,
    required this.selected,
    required this.child,
  });

  final CanvasGeometry geometry;
  final double scale;
  final double lead;
  final ScrollController horizontal;
  final ScrollController vertical;
  final List<GridItem> items;
  final Set<String> selected;
  final Widget child;

  /// Where the selection begins and ends, in cells, on each axis.
  ///
  /// This is what earns the strips their twenty pixels: *how wide is this and
  /// where does it sit* becomes something you look at rather than two numbers
  /// you read off the floor of the window and subtract.
  ((int, int)?, (int, int)?) get _spans {
    final held = [
      for (final i in items)
        if (selected.contains(i.id)) i,
    ];
    if (held.isEmpty) return (null, null);
    var x = held.first.x, right = held.first.right;
    var y = held.first.y, bottom = held.first.bottom;
    for (final i in held) {
      if (i.x < x) x = i.x;
      if (i.y < y) y = i.y;
      if (i.right > right) right = i.right;
      if (i.bottom > bottom) bottom = i.bottom;
    }
    return ((x, right), (y, bottom));
  }

  /// Enough rows to cover the page, with room to drag past the end of it.
  int get _rows {
    var last = 0;
    for (final i in items) {
      if (i.bottom > last) last = i.bottom;
    }
    return last + 6;
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final (across, down) = _spans;
    final border = BorderSide(color: t.stroke.hairline, width: t.stroke.width);

    return Column(
      children: [
        Row(
          children: [
            // The corner where the two meet. Filled rather than left as a hole,
            // which would show the canvas through a square that measures
            // nothing.
            Container(
              width: CanvasRuler.thickness,
              height: CanvasRuler.thickness,
              decoration: BoxDecoration(
                color: t.surface.raised,
                border: Border(bottom: border, right: border),
              ),
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: horizontal,
                builder: (context, _) => CanvasRuler(
                  horizontal: true,
                  step: geometry.stepX,
                  scale: scale,
                  offset:
                      horizontal.hasClients ? horizontal.position.pixels : 0,
                  lead: lead,
                  cells: geometry.columns,
                  span: across,
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: Row(
            // Stretched, or the ruler collapses: a Row hands its children loose
            // cross-axis constraints, and a strip whose height comes from its
            // painter has no height at all.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedBuilder(
                animation: vertical,
                builder: (context, _) => CanvasRuler(
                  horizontal: false,
                  step: geometry.stepY,
                  scale: scale,
                  offset: vertical.hasClients ? vertical.position.pixels : 0,
                  lead: lead,
                  cells: _rows,
                  span: down,
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ],
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
    required this.groupInHand,
    required this.inside,
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

  final String? groupInHand;

  /// Where you are standing. The one piece of state with no mark on the canvas
  /// of its own, and the one that silently changes what every click does.
  final String? inside;

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
      // Named rather than counted: "3 selected" is equally true of a group and
      // of three loose cards, and only one of those moves as a unit.
      if (groupInHand case final path?) 'group ${nameOf(path)}',
      // Where you are standing — the one piece of state with no mark of its own
      // on the canvas, and the one that changes what every click does.
      if (inside case final path?) 'inside $path',
      // Cells for a grid card, **pixels for a composed one**. Reporting "4×1
      // at 4,1" for an element whose truth is a rectangle is reporting the
      // approximation and calling it the measurement — and it is exactly what
      // made a drawn rule look like it had been forced into a two-by-four
      // block. The unit says which kind of element you are holding.
      if (item?.rect case final r?)
        '${r.w.round()}×${r.h.round()} px at ${r.x.round()},${r.y.round()}'
      else if (item != null)
        '${item!.w}×${item!.h} at ${item!.x},${item!.y}',
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

/// Everywhere the draft has been, as a list you can step back into.
///
/// Undo answers *take that back*; this answers *take back the last four*, which
/// is a different question and the one you have when you look up and find the
/// page wrong. Pressing undo four times gets there too, but only if you can
/// count the changes from memory — and the fourth press is the one that goes
/// too far.
///
/// **A popup rather than a rail.** The two panes are already full and the whole
/// visual interface is due a pass; a third permanent panel would be spending
/// canvas width on something read a few times an hour. It hangs off the undo
/// buttons, which is where you look when you want it.
class _HistoryControl extends StatelessWidget {
  const _HistoryControl({
    required this.entries,
    required this.at,
    required this.onJump,
  });

  final List<HistoryEntry> entries;
  final int at;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    // One entry means the page has not been touched: there is nowhere else to
    // stand and a list of one is a list about nothing.
    final enabled = entries.length > 1;

    return PopupMenuButton<int>(
      enabled: enabled,
      tooltip: enabled ? 'History' : 'Nothing has changed yet',
      // Opens on the row you are standing on rather than at the top, so a
      // twenty-deep history does not need scrolling to find *now*.
      initialValue: at,
      onSelected: onJump,
      itemBuilder: (context) => [
        for (var i = 0; i < entries.length; i++)
          PopupMenuItem(
            value: i,
            height: 32,
            child: _HistoryRow(entry: entries[i], current: i == at),
          ),
      ],
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: t.space.xs),
        child: Icon(
          Icons.history,
          size: 16,
          color: enabled ? t.surface.onBase : t.surface.onBaseMuted,
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.current});

  final HistoryEntry entry;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    // Three states, and they have to be told apart at a glance: where you are,
    // what you have done, and what you have undone but could put back.
    final colour = current
        ? t.surface.onBase
        : entry.future
            ? t.surface.onBaseMuted
            : t.surface.onBase;

    return Row(
      children: [
        SizedBox(
          width: t.space.md,
          child: current
              ? Icon(Icons.chevron_right, size: 14, color: t.accent.active)
              : null,
        ),
        Flexible(
          child: Text(
            entry.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.text.captionStyle.copyWith(
              color: colour,
              fontWeight: current ? FontWeight.w600 : null,
              // Struck through, because "undone" is a fact about the change
              // rather than about how loud it is — dimming alone reads as
              // *less important*, which these are not.
              decoration: entry.future ? TextDecoration.lineThrough : null,
              decorationColor: t.surface.onBaseMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// One place the draft has stood, for the history panel.
///
/// A *position*, not an edit — which is why there is always one more of these
/// than there are changes: you can stand before the first one.
class HistoryEntry {
  const HistoryEntry({required this.label, required this.future});

  /// The change that produced this state, or how the page began.
  final String label;

  /// Ahead of where the draft is now: somewhere undo has been walked back
  /// past, and redo can return to. Shown, rather than dropped, because a
  /// history that hides what you just undid cannot be used to change your mind
  /// twice.
  final bool future;
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
