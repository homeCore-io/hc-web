import 'package:flutter/material.dart';

import '../../core/dashboard/card_style.dart';
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
    this.ghostItems = const [],
    this.onMove,
    this.onResize,
    this.onRemove,
    this.onConfigure,
    this.onAddAt,
    this.selectedId,
    this.onDropCard,
    this.onMenu,
    this.onSelect,
  });

  final List<GridItem> items;
  final Map<String, DashboardWidgetModel> widgetsById;
  final int columns;
  final double rowHeight;
  final double gap;
  final bool editing;

  /// Where these cards would sit if this layout still followed another one.
  ///
  /// Drawn over the real ones as a dashed outline, so the question the whole
  /// per-device feature exists to answer — *what am I diverging from, and did I
  /// mean to?* — is answerable by looking, rather than by holding two
  /// arrangements in your head or opening a second window. Empty when there is
  /// nothing to diverge from, which is most of the time.
  final List<GridItem> ghostItems;

  final void Function(String id, int x, int y)? onMove;
  final void Function(String id, int w, int h)? onResize;
  final void Function(String id)? onRemove;
  final void Function(String id)? onConfigure;

  /// A tap on empty canvas, in grid cells.
  ///
  /// The canvas used to be inert: cards appended at the engine's first fit and
  /// you dragged them where you meant. Pointing at the place you want something
  /// is the difference between arranging a page and correcting one.
  final void Function(int x, int y)? onAddAt;

  /// The card the rail is showing. Marked on the canvas, because a panel that
  /// names a card while nothing on the board says which one is a panel about
  /// nothing you can see.
  final String? selectedId;

  /// A card dragged in from the library, dropped at a cell.
  final void Function(Object payload, int x, int y)? onDropCard;

  /// A right-click on a card, at the pointer.
  ///
  /// The convention that carries the most weight in a pointer-driven tool, and
  /// the one this editor never had: every card action was a small round button
  /// you had to find and hit, or nothing.
  final void Function(String id, Offset globalPosition)? onMenu;

  /// A plain click on a card. Null on the surfaces with nowhere to put a
  /// selection — the phone's in-place editor has no inspector beside it, and a
  /// card that highlights and then does nothing is a worse answer than none.
  final void Function(String id)? onSelect;

  @override
  State<PageGrid> createState() => _PageGridState();
}

class _PageGridState extends State<PageGrid> {
  /// The cell a dragged-in card is hovering over, in grid units.
  (int, int)? _dropCell;

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
            // An empty page still needs a board. Four rows is enough to read as
            // a grid and to aim at, without pretending the page is longer than
            // it is.
            ? widget.rowHeight * (widget.editing ? 4 : 1) +
                (widget.editing ? widget.gap * 3 : 0)
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
              // The column grid, behind everything, while editing. A card's
              // width is only meaningful as a count of columns, and counting
              // them off an unmarked canvas is guesswork — this is the ruler,
              // drawn where the cards actually land rather than as a strip
              // above them.
              if (widget.editing)
                Positioned.fill(
                  // The whole board is a drop target while editing. Tracking
                  // the cell under the pointer is what makes dropping feel like
                  // placing rather than like submitting: you see where it will
                  // land before you let go.
                  child: DragTarget<Object>(
                    onMove: (details) {
                      final box = context.findRenderObject() as RenderBox?;
                      if (box == null) return;
                      final local = box.globalToLocal(details.offset);
                      final x =
                          (local.dx / stepX).floor().clamp(0, columns - 1);
                      final y = (local.dy / stepY).floor();
                      final cell = (x, y < 0 ? 0 : y);
                      if (_dropCell != cell) setState(() => _dropCell = cell);
                    },
                    onLeave: (_) => setState(() => _dropCell = null),
                    onAcceptWithDetails: (details) {
                      final cell = _dropCell;
                      setState(() => _dropCell = null);
                      if (cell != null) {
                        widget.onDropCard?.call(details.data, cell.$1, cell.$2);
                      }
                    },
                    builder: (context, _, __) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: widget.onAddAt == null
                          ? null
                          : (details) {
                              final p = details.localPosition;
                              final x =
                                  (p.dx / stepX).floor().clamp(0, columns - 1);
                              final y = (p.dy / stepY).floor();
                              widget.onAddAt!(x, y < 0 ? 0 : y);
                            },
                      child: CustomPaint(
                        painter: _ColumnGuides(
                          columns: columns,
                          cellW: cellW,
                          gap: widget.gap,
                          color: t.stroke.hairline,
                        ),
                      ),
                    ),
                  ),
                ),

              // Where the dragged card would land. Drawn over the guides and
              // under the cards, so it reads as part of the board.
              if (_dropCell case final cell?)
                Positioned(
                  left: cell.$1 * stepX,
                  top: cell.$2 * stepY,
                  width: cellW * 4 + widget.gap * 3,
                  height: widget.rowHeight * 2 + widget.gap,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: t.accent.active.withValues(alpha: 0.08),
                        borderRadius: t.radius.mdR,
                        border: Border.all(color: t.accent.active, width: 2),
                      ),
                    ),
                  ),
                ),

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
                      selected: widget.selectedId == item.id,
                      // Only while resizing. During a move the position is
                      // already legible from where the card is; during a
                      // resize the number of cells is exactly what you are
                      // aiming at and the only thing you cannot read off the
                      // screen.
                      sizeLabel:
                          _resizeId == item.id ? '${item.w}×${item.h}' : null,
                      onRemove: () => widget.onRemove?.call(item.id),
                      onConfigure: () => widget.onConfigure?.call(item.id),
                      onMenu: (pos) => widget.onMenu?.call(item.id, pos),
                      onSelect: widget.onSelect == null
                          ? null
                          : () => widget.onSelect!(item.id),
                      onDragStart: () => startDrag(item),
                      onDragUpdate: updateDrag,
                      onDragEnd: endDrag,
                      onResizeStart: () => startResize(item),
                      onResizeUpdate: updateResize,
                      onResizeEnd: endResize,
                    ),
                  ),
                ),

              // The ghost, ON TOP of the cards.
              //
              // It was drawn behind them first, which is what the plan
              // described and what "underlay" implies — and rendering it showed
              // that behind means *invisible* in exactly the case that matters.
              // A layout diverges by putting cards somewhere else, so the new
              // arrangement almost always covers the old one: a full-width card
              // hid every outline of the three-column arrangement it replaced,
              // and the feature drew nothing at all.
              //
              // On top it is onion-skinning, which is how every design tool
              // shows a previous position. It stays non-interactive, has no
              // fill, and is dashed, so it reads as an annotation over the
              // arrangement rather than as another card.
              if (widget.editing && widget.ghostItems.isNotEmpty) ...[
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _GhostOutlines(
                        items: widget.ghostItems,
                        stepX: stepX,
                        stepY: stepY,
                        cellW: cellW,
                        rowHeight: widget.rowHeight,
                        gap: widget.gap,
                        radius: t.radius.md,
                        // Neutral, not accent. `accent.active` means *this
                        // device is on* (brief principle 2) — borrowing it for
                        // a drawing about layout would make the ghost read as
                        // state and put a second meaning on a semantic token.
                        color: t.surface.onBaseMuted,
                      ),
                    ),
                  ),
                ),
                // A label only where no real card sits under it. Over one it
                // lands beside that card's own title and the two read as a
                // single confused heading — which is precisely what it looked
                // like before this condition came back.
                for (final g in widget.ghostItems)
                  if (!items.any((i) =>
                      i.x < g.right &&
                      i.right > g.x &&
                      i.y < g.bottom &&
                      i.bottom > g.y))
                    Positioned(
                      left: leftOf(g) + t.space.sm,
                      top: topOf(g) + t.space.xs,
                      width: (widthOf(g) - t.space.sm * 2).clamp(0, 400),
                      child: IgnorePointer(
                        child: Text(
                          widget.widgetsById[g.id]?.title ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.text.captionStyle
                              .copyWith(color: t.surface.onBaseMuted),
                        ),
                      ),
                    ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The column bands, painted behind the cards while editing.
///
/// Bands rather than lines: a line between columns tells you where a boundary
/// is, a band tells you how wide one column is, and width in columns is the
/// thing being decided. Kept at hairline strength — this is a guide for the
/// minute you spend arranging, not a permanent feature of the page.
class _ColumnGuides extends CustomPainter {
  const _ColumnGuides({
    required this.columns,
    required this.cellW,
    required this.gap,
    required this.color,
  });

  final int columns;
  final double cellW;
  final double gap;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Very faint. Filled bands cover a lot of area — most of it the empty drop
    // zone below the last row — and at anything like hairline strength the
    // guide stops being a guide and becomes the loudest thing on the page.
    // It only has to be enough to count against.
    final paint = Paint()..color = color.withValues(alpha: color.a * 0.18);
    for (var i = 0; i < columns; i++) {
      final left = i * (cellW + gap);
      canvas.drawRect(Rect.fromLTWH(left, 0, cellW, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_ColumnGuides old) =>
      old.columns != columns ||
      old.cellW != cellW ||
      old.gap != gap ||
      old.color != color;
}

/// The ghost arrangement, as dashed outlines.
///
/// Dashed rather than a faint solid: a solid box reads as another card, and the
/// one thing this must never be mistaken for is something you can grab. Dashes
/// say "not real" in a way no opacity value does — which matters more now that
/// it is drawn over the cards rather than under them.
///
/// One painter for every outline rather than a widget each — they are a
/// drawing, none of them is interactive, and a dozen `Positioned` boxes with
/// custom borders would cost layout on every drag frame for no benefit.
class _GhostOutlines extends CustomPainter {
  const _GhostOutlines({
    required this.items,
    required this.stepX,
    required this.stepY,
    required this.cellW,
    required this.rowHeight,
    required this.gap,
    required this.radius,
    required this.color,
  });

  final List<GridItem> items;
  final double stepX;
  final double stepY;
  final double cellW;
  final double rowHeight;
  final double gap;
  final double radius;
  final Color color;

  static const _dash = 6.0;
  static const _skip = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: color.a * 0.7);

    for (final i in items) {
      final rect = Rect.fromLTWH(
        i.x * stepX,
        i.y * stepY,
        i.w * cellW + (i.w - 1) * gap,
        i.h * rowHeight + (i.h - 1) * gap,
      );
      final path = Path()
        ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
      canvas.drawPath(_dashed(path), paint);
    }
  }

  /// Walks the path and keeps every other stretch. `PathMetric.extractPath` is
  /// the only way to dash a rounded rect in Flutter — there is no dash style on
  /// Paint — and doing it per frame is fine because the ghost does not move.
  Path _dashed(Path source) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dash;
        out.addPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          Offset.zero,
        );
        distance = next + _skip;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(_GhostOutlines old) =>
      old.items != items ||
      old.stepX != stepX ||
      old.stepY != stepY ||
      old.cellW != cellW ||
      old.rowHeight != rowHeight ||
      old.gap != gap ||
      old.radius != radius ||
      old.color != color;
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
    required this.selected,
    required this.sizeLabel,
    required this.onRemove,
    required this.onConfigure,
    required this.onMenu,
    required this.onSelect,
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
  final bool selected;

  /// `4×2` while this card is being resized, else null.
  final String? sizeLabel;
  final VoidCallback onRemove;
  final VoidCallback onConfigure;
  final void Function(Offset globalPosition) onMenu;

  /// Null outside the surfaces that have somewhere to show a selection.
  final VoidCallback? onSelect;
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
                      editing: editing,
                    ),
                  );

    // How much frame the element asked for. A watermarked stand-in during a
    // drag always takes the full card, whatever it is the rest of the time —
    // a bare element would otherwise vanish at the moment you are moving it.
    final chrome = simplified
        ? WidgetChrome.card
        : (descriptor?.chrome ?? WidgetChrome.card);

    // Only meaningful where there is a surface to style. A bare element has no
    // background to remove.
    final style = CardStyle.fromConfig(model?.config ?? const {});

    final Widget card = switch (chrome) {
      // Draws itself onto the page, and nothing is drawn around it.
      WidgetChrome.bare => SizedBox.expand(child: ClipRect(child: body)),
      // The surface, but the body reaches its edges.
      WidgetChrome.bleed => HcSurface(
          selected: dragging || selected,
          padding: EdgeInsets.zero,
          filled: style.filled,
          bordered: style.bordered,
          child: ClipRect(child: body),
        ),
      WidgetChrome.card => HcSurface(
          // Lifted OR chosen. Both mean "this is the one you are working on".
          selected: dragging || selected,
          padding: EdgeInsets.all(t.space.md),
          filled: style.filled,
          bordered: style.bordered,
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
        ),
    };

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
            // Click to select. It reads as too obvious to write down, and it
            // was missing: the only way to put a card in the inspector was to
            // find the small round options button in its corner. Everything
            // else about the canvas said "direct manipulation" and the first
            // gesture anyone tries did nothing at all.
            onTap: onSelect,
            onPanStart: (_) => onDragStart(),
            onPanUpdate: (d) => onDragUpdate(d.delta),
            onPanEnd: (_) => onDragEnd(),
            onSecondaryTapDown: (d) => onMenu(d.globalPosition),
            // A long press is the same gesture on a touchscreen, and the
            // in-place editor runs there too.
            onLongPressStart: (d) => onMenu(d.globalPosition),
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
              _RoundButton(
                  icon: HcIcons.sliders,
                  onTap: onConfigure,
                  label: 'Card options'),
              const SizedBox(width: 4),
              _RoundButton(
                  icon: HcIcons.x, onTap: onRemove, label: 'Remove card'),
            ],
          ),
        ),
        if (sizeLabel case final label?)
          Positioned(
            key: const Key('resize-readout'),
            left: 6,
            bottom: 6,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: t.surface.overlay,
                  borderRadius: BorderRadius.circular(t.radius.xs),
                  border:
                      Border.all(color: t.accent.active, width: t.stroke.width),
                ),
                child: Text(
                  label,
                  style: t.text.captionStyle.copyWith(
                      color: t.surface.onBase,
                      fontFeatures: t.numericFontFeatures),
                ),
              ),
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
              child: Semantics(
                // A bare corner to drag was invisible to assistive tech and
                // unnamed to everyone else.
                label: 'Resize card',
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
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton(
      {required this.icon, required this.onTap, required this.label});

  final IconData icon;
  final VoidCallback onTap;

  /// A bare glyph on a card told a screen reader nothing and a pointer user
  /// only what a caret-in-a-circle suggests. Both of these are destructive or
  /// mode-changing, so both say which.
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Tooltip(
      message: label,
      child: Material(
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
      ),
    );
  }
}
