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
  // Local, pixel-space drag state. The dragged card follows the finger freely
  // (duration zero) while everything else reflows to the grid; on release it
  // snaps to the cell the engine settled it into.
  String? _dragId;
  Point _dragStart = const Point(0, 0);
  Offset _accum = Offset.zero;

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

        double leftOf(GridItem i) => i.x * stepX;
        double topOf(GridItem i) => i.y * stepY;
        double widthOf(GridItem i) => i.w * cellW + (i.w - 1) * widget.gap;
        double heightOf(GridItem i) =>
            i.h * widget.rowHeight + (i.h - 1) * widget.gap;

        final maxRow =
            widget.items.fold<int>(0, (m, i) => i.bottom > m ? i.bottom : m);
        final height = maxRow <= 0
            ? widget.rowHeight
            : maxRow * widget.rowHeight + (maxRow - 1) * widget.gap;

        return SizedBox(
          width: double.infinity,
          // Room to drop a card below the last row while editing.
          height: height + (widget.editing ? stepY * 2 : 0),
          child: Stack(
            children: [
              for (final item in widget.items)
                AnimatedPositioned(
                  duration: _dragId == item.id
                      ? Duration.zero
                      : t.motion.d(t.motion.fast),
                  curve: t.motion.curve,
                  left: _dragId == item.id
                      ? _dragStart.x * stepX + _accum.dx
                      : leftOf(item),
                  top: _dragId == item.id
                      ? _dragStart.y * stepY + _accum.dy
                      : topOf(item),
                  width: widthOf(item),
                  height: heightOf(item),
                  child: _Cell(
                    item: item,
                    model: widget.widgetsById[item.id],
                    editing: widget.editing,
                    dragging: _dragId == item.id,
                    onRemove: () => widget.onRemove?.call(item.id),
                    onConfigure: () => widget.onConfigure?.call(item.id),
                    onDragStart: () => setState(() {
                      _dragId = item.id;
                      _dragStart = Point(item.x, item.y);
                      _accum = Offset.zero;
                    }),
                    onDragUpdate: (delta) {
                      _accum += delta;
                      final tx = _dragStart.x + (_accum.dx / stepX).round();
                      final ty = _dragStart.y + (_accum.dy / stepY).round();
                      widget.onMove?.call(item.id, tx, ty < 0 ? 0 : ty);
                      setState(() {}); // re-read _accum for the followed card
                    },
                    onDragEnd: () => setState(() => _dragId = null),
                    onResize: (delta, current) {
                      final tw = current.w + (delta.dx / stepX).round();
                      final th = current.h + (delta.dy / stepY).round();
                      widget.onResize?.call(item.id, tw, th);
                    },
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
    required this.dragging,
    required this.onRemove,
    required this.onConfigure,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onResize,
  });

  final GridItem item;
  final DashboardWidgetModel? model;
  final bool editing;
  final bool dragging;
  final VoidCallback onRemove;
  final VoidCallback onConfigure;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final void Function(Offset delta, GridItem current) onResize;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final descriptor =
        model == null ? null : WidgetRegistry.lookup(model!.type);

    final body = model == null
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
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: t.surface.onBase,
                ),
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
            onPanUpdate: (d) => onResize(d.delta, item),
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
