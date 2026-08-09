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
class DesignerShell extends StatelessWidget {
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

  /// Fixed, because the frame is fixed. Panes that resized themselves would
  /// make the canvas scale jump while you worked in it.
  static const _libraryWidth = 260.0;
  static const _inspectorWidth = 340.0;

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
          final available =
              frame.maxWidth - _libraryWidth - _inspectorWidth - t.space.lg * 2;
          final scale = canvasWidth == null || canvasWidth! <= 0
              ? 1.0
              : (available / canvasWidth!).clamp(0.25, 1.0);

          return Column(
            children: [
              _TopBar(
                title: dashboard.name,
                layouts: layouts,
                breakpoint: breakpoint,
                source: source,
                saving: saving,
                dirty: dirty,
                onSelectBreakpoint: onSelectBreakpoint,
                onRevert: onRevert,
                onSave: onSave,
                onLeave: () => context.go('/pages/${dashboard.id}'),
              ),
              if (consequence case final line?)
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
                      width: _libraryWidth,
                      border: Border(
                          right: BorderSide(
                              color: t.stroke.hairline, width: t.stroke.width)),
                      child: CardLibrary(onPick: onPick),
                    ),
                    // The canvas is the only thing allowed to be large. It
                    // scrolls inside itself; the frame around it never moves.
                    Expanded(
                      child: Container(
                        color: t.surface.sunken,
                        // Scaled to fit, never enlarged. The canvas draws the
                        // layout at the width that breakpoint really has — 1600
                        // for desktop — and the middle pane is nowhere near that
                        // once two panels take their 600. Unscaled it simply
                        // clipped: the right-hand third of every full-width card
                        // sat outside the viewport, which is worse than the
                        // editor this replaces.
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(t.space.lg),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Transform.scale(
                              scale: scale,
                              alignment: Alignment.topLeft,
                              child:
                                  SizedBox(width: canvasWidth, child: canvas),
                            ),
                          ),
                        ),
                      ),
                    ),
                    _Pane(
                      width: _inspectorWidth,
                      border: Border(
                          left: BorderSide(
                              color: t.stroke.hairline, width: t.stroke.width)),
                      child: selected == null
                          ? PageInspector(
                              dashboard: dashboard,
                              breakpoint: breakpoint,
                              layout: layouts
                                  ?.where((l) => l.breakpoint == breakpoint)
                                  .firstOrNull,
                              cardCount: cardCount,
                              onFlowChanged: onFlowChanged,
                            )
                          : CardInspector(
                              model: selected!,
                              onChanged: onChanged,
                              onRemove: onRemoveSelected,
                              onClose: onDeselect,
                            ),
                    ),
                  ],
                ),
              ),
              _StatusBar(
                scale: scale,
                selectedCount: selectedCount,
                item: selectedItem,
                columns: columns,
                flow: layouts
                        ?.where((l) => l.breakpoint == breakpoint)
                        .firstOrNull
                        ?.flow ??
                    GridFlow.packed,
                dirty: dirty,
                saving: saving,
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
    required this.scale,
  });

  final double scale;
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
      if (scale < 0.999) '${(scale * 100).round()}%',
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
