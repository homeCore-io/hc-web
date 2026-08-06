import 'package:flutter/material.dart';

import '../../core/dashboard/grid_engine.dart';
import '../../core/dashboard/widget_registry.dart';
import '../../core/models/dashboard.dart';
import '../../design/components/hc_surface.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';

/// The grid that draws a page — live in view mode, directly manipulable in edit.
///
/// Layout is [GridEngine]'s job, not this widget's: dragging reports a target
/// cell and the parent runs `move`, which pushes neighbours out of the way and
/// packs the result. That is the "things move out of the way, no fiddling"
/// behaviour — the grid model already had it; this only had to stop fighting it.
class PageGrid extends StatefulWidget {
  const PageGrid({
    super.key,
    required this.items,
    required this.widgetsById,
    required this.columns,
    required this.rowHeight,
    required this.gap,
    required this.editing,
    this.onMove,
    this.onResize,
    this.onRemove,
    this.onConfigure,
  });

  final List<GridItem> items;
  final Map<String, DashboardWidgetModel> widgetsById;
  final int columns;
  final double rowHeight;
  final double gap;
  final bool editing;

  final void Function(String id, int x, int y)? onMove;
  final void Function(String id, int w, int h)? onResize;
  final void Function(String id)? onRemove;
  final void Function(String id)? onConfigure;

  @override
  State<PageGrid> createState() => _PageGridState();
}

class _PageGridState extends State<PageGrid> {
  // A gesture (move or resize) works from an immutable snapshot of the layout
  // taken at its start, so the arrangement depends only on where the pointer is
  // *now* — not on the path it took to get there. The engine reflows that
  // snapshot into a stable preview each frame; the committed draft is touched
  // once, on release. That is what stops neighbours from oscillating under the
  // cursor and gives an honest WYSIWYG result.
  List<GridItem>? _baseline;
  List<GridItem>? _preview;

  // Move gesture.
  String? _dragId;
  Point _dragStart = const Point(0, 0);
  Offset _accum = Offset.zero;

  // Resize gesture — start holds the card's original (w, h).
  String? _resizeId;
  Point _resizeStart = const Point(0, 0);
  Offset _resizeAccum = Offset.zero;

  static GridItem? _itemById(List<GridItem> items, String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    return LayoutBuilder(
      builder: (context, c) {
        final columns = widget.columns <= 0 ? 1 : widget.columns;
        final cellW = ((c.maxWidth - widget.gap * (columns - 1)) / columns)
            .clamp(1.0, double.infinity);
        final stepX = cellW + widget.gap;
        final stepY = widget.rowHeight + widget.gap;

        // While a gesture is live we lay out its preview, so the real draft is
        // untouched until release.
        final items = _preview ?? widget.items;

        double leftOf(GridItem i) => i.x * stepX;
        double topOf(GridItem i) => i.y * stepY;
        double widthOf(GridItem i) => i.w * cellW + (i.w - 1) * widget.gap;
        double heightOf(GridItem i) =>
            i.h * widget.rowHeight + (i.h - 1) * widget.gap;

        final maxRow =
            items.fold<int>(0, (m, i) => i.bottom > m ? i.bottom : m);
        final height = maxRow <= 0
            ? widget.rowHeight
            : maxRow * widget.rowHeight + (maxRow - 1) * widget.gap;

        void startDrag(GridItem item) => setState(() {
              _baseline = List<GridItem>.of(widget.items);
              _preview = _baseline;
              _dragId = item.id;
              _dragStart = Point(item.x, item.y);
              _accum = Offset.zero;
            });

        void updateDrag(Offset delta) {
          _accum += delta;
          final tx = _dragStart.x + (_accum.dx / stepX).round();
          final ty = _dragStart.y + (_accum.dy / stepY).round();
          final engine = GridEngine(columns: columns);
          setState(() => _preview =
              engine.move(_baseline!, _dragId!, tx, ty < 0 ? 0 : ty));
        }

        void endDrag() {
          final id = _dragId;
          final settled = id == null ? null : _itemById(_preview!, id);
          // Commit once: the parent runs the identical move on the real draft,
          // so the card lands exactly where the preview showed it.
          if (id != null && settled != null) {
            widget.onMove?.call(id, settled.x, settled.y);
          }
          setState(() {
            _dragId = null;
            _baseline = null;
            _preview = null;
            _accum = Offset.zero;
          });
        }

        void startResize(GridItem item) => setState(() {
              _baseline = List<GridItem>.of(widget.items);
              _preview = _baseline;
              _resizeId = item.id;
              _resizeStart = Point(item.w, item.h);
              _resizeAccum = Offset.zero;
            });

        void updateResize(Offset delta) {
          // Accumulate, like drag — a per-event delta rounds to zero almost
          // every frame and the resize feels dead.
          _resizeAccum += delta;
          final tw = _resizeStart.x + (_resizeAccum.dx / stepX).round();
          final th = _resizeStart.y + (_resizeAccum.dy / stepY).round();
          final engine = GridEngine(columns: columns);
          setState(
              () => _preview = engine.resize(_baseline!, _resizeId!, tw, th));
        }

        void endResize() {
          final id = _resizeId;
          final settled = id == null ? null : _itemById(_preview!, id);
          if (id != null && settled != null) {
            widget.onResize?.call(id, settled.w, settled.h);
          }
          setState(() {
            _resizeId = null;
            _baseline = null;
            _preview = null;
            _resizeAccum = Offset.zero;
          });
        }

        // The lifted card follows the finger, but clamped to the legal range so
        // it never visually leaves the board and snaps back on release.
        double draggedLeft(GridItem i) {
          final maxLeft = (columns - i.w).clamp(0, columns) * stepX;
          return (_dragStart.x * stepX + _accum.dx).clamp(0.0, maxLeft);
        }

        double draggedTop(GridItem i) =>
            (_dragStart.y * stepY + _accum.dy).clamp(0.0, double.infinity);

        // While a gesture is live, render every card as a lightweight chip
        // instead of its full live body. Reflowing 6 device grids/lists (each
        // with glowing tiles and CustomPaint) on every pointer frame is what
        // made dragging choppy; a chip costs almost nothing, so the reflow
        // animates smoothly. Cards snap back to their live selves on release.
        final gesturing = _dragId != null || _resizeId != null;

        return SizedBox(
          width: double.infinity,
          // Room to drop a card below the last row while editing.
          height: height + (widget.editing ? stepY * 2 : 0),
          child: Stack(
            children: [
              for (final item in items)
                AnimatedPositioned(
                  key: ValueKey(item.id),
                  duration: _dragId == item.id
                      ? Duration.zero
                      : t.motion.d(t.motion.fast),
                  curve: t.motion.curve,
                  left: _dragId == item.id ? draggedLeft(item) : leftOf(item),
                  top: _dragId == item.id ? draggedTop(item) : topOf(item),
                  width: widthOf(item),
                  height: heightOf(item),
                  child: RepaintBoundary(
                    child: _Cell(
                      item: item,
                      model: widget.widgetsById[item.id],
                      editing: widget.editing,
                      simplified: gesturing,
                      dragging: _dragId == item.id || _resizeId == item.id,
                      onRemove: () => widget.onRemove?.call(item.id),
                      onConfigure: () => widget.onConfigure?.call(item.id),
                      onDragStart: () => startDrag(item),
                      onDragUpdate: updateDrag,
                      onDragEnd: endDrag,
                      onResizeStart: () => startResize(item),
                      onResizeUpdate: updateResize,
                      onResizeEnd: endResize,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A tiny integer point, so the drag origin does not need a whole GridItem.
class Point {
  const Point(this.x, this.y);
  final int x;
  final int y;
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.item,
    required this.model,
    required this.editing,
    required this.simplified,
    required this.dragging,
    required this.onRemove,
    required this.onConfigure,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  final GridItem item;
  final DashboardWidgetModel? model;
  final bool editing;
  final bool simplified;
  final bool dragging;
  final VoidCallback onRemove;
  final VoidCallback onConfigure;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onResizeStart;
  final ValueChanged<Offset> onResizeUpdate;
  final VoidCallback onResizeEnd;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final descriptor =
        model == null ? null : WidgetRegistry.lookup(model!.type);

    final body = simplified
        // A cheap stand-in during drag/resize: an icon watermark, no providers,
        // no CustomPaint — so the reflow stays smooth.
        ? Center(
            child: Icon(
              descriptor?.icon ?? HcIcons.dashboards,
              size: 26,
              color: t.surface.onBaseMuted.withValues(alpha: 0.4),
            ),
          )
        : model == null
            ? const SizedBox.shrink()
            : descriptor == null
                ? UnknownWidget(type: model!.type)
                : descriptor.builder(
                    context,
                    WidgetRenderArgs(
                      id: model!.id,
                      title: model!.title,
                      subtitle: model!.subtitle,
                      config: model!.config,
                      w: item.w,
                      h: item.h,
                      sizeHint: descriptor.sizeHint,
                    ),
                  );

    final card = HcSurface(
      selected: dragging,
      padding: EdgeInsets.all(t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((model?.title ?? '').isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: t.space.sm),
              child: Text(
                model!.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.bodyStyle.copyWith(
                    fontWeight: FontWeight.w600, color: t.surface.onBase),
              ),
            ),
          Expanded(child: ClipRect(child: body)),
        ],
      ),
    );

    if (!editing) return card;

    // Edit mode: a veil swallows the live widget's own taps, and the frame adds
    // the three things you do to a card — move it, size it, remove it.
    return Stack(
      children: [
        Positioned.fill(child: IgnorePointer(child: card)),
        // Drag anywhere on the body to move.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => onDragStart(),
            onPanUpdate: (d) => onDragUpdate(d.delta),
            onPanEnd: (_) => onDragEnd(),
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: t.radius.mdR,
                  border: Border.all(
                    color: t.accent.active.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Configure + remove.
        Positioned(
          top: 4,
          right: 4,
          child: Row(
            children: [
              _RoundButton(icon: HcIcons.sliders, onTap: onConfigure),
              const SizedBox(width: 4),
              _RoundButton(icon: HcIcons.x, onTap: onRemove),
            ],
          ),
        ),
        // Resize from the bottom-right.
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => onResizeStart(),
            onPanUpdate: (d) => onResizeUpdate(d.delta),
            onPanEnd: (_) => onResizeEnd(),
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeDownRight,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                child: Icon(HcIcons.grip,
                    size: 13, color: t.accent.active.withValues(alpha: 0.8)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Material(
      color: t.surface.base,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 13, color: t.surface.onBase),
        ),
      ),
    );
  }
}
