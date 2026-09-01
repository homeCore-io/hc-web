import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/dashboard/canvas_view.dart';
import '../../core/dashboard/card_style.dart';
import '../../core/dashboard/frame.dart';
import '../../core/dashboard/grid_engine.dart';
import '../../core/dashboard/group_frame.dart';
import '../../core/dashboard/groups.dart';
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
    this.onWidgetConfig,
    this.onAddAt,
    this.onMarquee,
    this.onDraw,
    this.selectedIds = const {},
    this.onDropCard,
    this.onMenu,
    this.onSelect,
    this.onEnterGroup,
    this.groupOutline,
    this.groupStyles = const [],
    this.groupPaths = const {},
    this.frame,
    this.snapToGrid = true,
    this.onCompose,
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

  /// A card rewriting its own config — see [WidgetRenderArgs.onConfigChanged].
  final void Function(String id, Map<String, dynamic> config)? onWidgetConfig;

  /// A tap on empty canvas, in canvas pixels.
  ///
  /// The canvas used to be inert: cards appended at the engine's first fit and
  /// you dragged them where you meant. Pointing at the place you want something
  /// is the difference between arranging a page and correcting one.
  ///
  /// Pixels rather than cells, for the same reason [onDraw] takes them: a tap
  /// with a text tool in hand should put the words where the pointer was, and
  /// the caller can always ask the geometry which cell that is.
  final void Function(Offset at)? onAddAt;

  /// A rubber band was pulled from one cell to another. [additive] is shift:
  /// add the catch to what is already in hand.
  final void Function(int x1, int y1, int x2, int y2, bool additive)? onMarquee;

  /// A drag was made **with a drawing tool in hand**, in canvas pixels.
  ///
  /// The same gesture as [onMarquee] and deliberately so: one band, and what it
  /// means is what you are holding. That is how every design application
  /// works, and it is the interaction the designer was missing — an element
  /// arriving at the size and place you drew it, rather than at the engine's
  /// first fit with two corrections to follow.
  ///
  /// **Pixels, not cells.** A selection band asks which cells it swept, and
  /// cells are the answer. Drawing asks what rectangle this is, and a cell is
  /// about 130 by 120 on a desktop layout — so answering in cells turns a rule
  /// into a two-by-four block and a caption into a word floating in a box four
  /// times its height. The document has expressed rectangles since the
  /// composition arc; drawing uses them.
  ///
  /// Non-null is also the signal that a tool is in hand: the band changes
  /// colour, the cursor becomes a crosshair, and nothing gets selected.
  final void Function(Offset from, Offset to)? onDraw;

  /// The card the rail is showing. Marked on the canvas, because a panel that
  /// names a card while nothing on the board says which one is a panel about
  /// nothing you can see.
  /// Everything in hand. A set, because align, distribute and the keyboard all
  /// act on more than one card — see `page_screen`'s `_selection`.
  final Set<String> selectedIds;

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
  /// [additive] is a shift-click: add to the selection, or take back out
  /// something already in it.
  final void Function(String id, bool additive)? onSelect;

  /// A double-click on a card: step into the group it belongs to.
  ///
  /// The gesture every drawing tool uses for it, and the only way to reach one
  /// member of a group on the canvas — a single click deliberately holds the
  /// whole cluster.
  final void Function(String id)? onEnterGroup;

  /// The group in hand, as a rectangle in cells and the name to write on it.
  ///
  /// Drawn as one dashed frame around the lot. Without it a group is
  /// indistinguishable from three cards that happen to be selected together,
  /// which is the difference the feature exists to make.
  final (GridItem, String)? groupOutline;

  /// The groups that have been given a body, and who is in each one.
  ///
  /// Both halves are needed and neither can be resolved without the other:
  /// membership lives in the widgets' config, which only the draft knows, and
  /// the rectangles are in the board's units, which only this widget's
  /// LayoutBuilder knows. So the styles and the paths come down and the
  /// resolution happens here, once, against the same `boxOf` the cards are
  /// drawn from — a container that computed its position from anything else
  /// could disagree with what is inside it.
  ///
  /// Unlike [groupOutline] these are part of the *page*, not part of the
  /// selection: they are drawn in view mode too, behind everything, because a
  /// container that only existed while you were editing would not be a
  /// container.
  final List<GroupBox> groupStyles;

  /// Which group each element is in — see `groups.dart`.
  final Map<String, String?> groupPaths;

  /// The canvas this layout is composed on, or null for a plain grid.
  ///
  /// Present, the board is the frame's own size and every element is drawn from
  /// its rectangle rather than from its cells — see `frame.dart`. Absent, none
  /// of this applies and the grid behaves exactly as it always has, which is
  /// the case most pages are in.
  final DashboardFrame? frame;

  /// A composed element was moved or resized to [rect].
  ///
  /// Separate from [onMove] and [onResize] because it is a different edit: those
  /// two report cells and the parent runs the packing engine on them, which is
  /// exactly what must not happen to something somebody placed.
  final void Function(String id, DashboardRect rect)? onCompose;

  /// Whether a composed drag is pulled to the cell edges.
  ///
  /// A choice per gesture rather than a property of the document. This is the
  /// one place "the grid is a magnet, not a law" has to actually be true.
  final bool snapToGrid;

  @override
  State<PageGrid> createState() => _PageGridState();
}

/// Moving a card, on raw pointer events rather than a pan recogniser.
///
/// The canvas sits inside two scroll views, and a pan recogniser competes with
/// them for the gesture. **In a real browser it wins** — this was checked
/// against the live house, before and after, dragging horizontally, vertically
/// and diagonally, and the pan version moved the card every time. Under
/// `flutter_test` it does not: the harness synthesises one large move where a
/// browser sends a stream of small ones, and the arena resolves the other way,
/// so every drag became a scroll and no test could move a card at all.
///
/// So this is not a fix for a bug anybody could see. It is a fix for a gesture
/// whose outcome depended on how the pointer events arrived, which meant the
/// drag could not be tested — and composition needed testing more than the
/// grid did, because a composed drag writes a rectangle rather than snapping
/// to a cell that would have hidden small errors.
///
/// Raw pointers do not compete, so the outcome is the same either way. Tapping,
/// the context menu and the long press stay on the [GestureDetector]
/// underneath: a tap recogniser rejects itself once the pointer travels past
/// the slop, so a drag cannot also read as a click.
class _DragBody extends StatefulWidget {
  const _DragBody({
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.child,
  });

  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final Widget child;

  @override
  State<_DragBody> createState() => _DragBodyState();
}

class _DragBodyState extends State<_DragBody> {
  Offset? _from;
  bool _moving = false;

  void _end() {
    if (_moving) widget.onDragEnd();
    _from = null;
    _moving = false;
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (event) {
          // Primary only. The middle button pans the canvas and the secondary
          // one opens the card menu; neither should move anything.
          if (event.buttons != kPrimaryButton) return;
          _from = event.localPosition;
          _moving = false;
        },
        onPointerMove: (event) {
          final from = _from;
          if (from == null) return;
          if (!_moving) {
            // Past the slop before anything happens, or every click nudges the
            // card by a pixel and the page is never quite where you left it.
            if ((event.localPosition - from).distance < kTouchSlop) {
              return;
            }
            _moving = true;
            widget.onDragStart();
          }
          // The *local* delta: the board is drawn scaled, and the global one
          // would move the card by screen pixels on a canvas measured in its
          // own.
          widget.onDragUpdate(event.localDelta);
        },
        onPointerUp: (_) => _end(),
        onPointerCancel: (_) => _end(),
        child: widget.child,
      );
}

class _PageGridState extends State<PageGrid> {
  /// The cell a dragged-in card is hovering over, in grid units.
  (int, int)? _dropCell;

  /// The second half of a double-click, timed here rather than handed to
  /// [GestureDetector.onDoubleTap].
  ///
  /// Flutter's double-tap recogniser makes a *single* tap wait out the
  /// double-tap window before it fires, so wiring `onDoubleTap` put a third of
  /// a second between clicking a card and seeing it selected. Selection has to
  /// be instant — it is the most common thing anyone does here — so the first
  /// click selects immediately and a second one inside the window additionally
  /// steps into the group. Nothing is delayed and nothing is swallowed.
  String? _lastTapId;
  DateTime? _lastTapAt;

  static const _doubleTapWindow = Duration(milliseconds: 400);

  void _tapped(String id, bool additive) {
    widget.onSelect!(id, additive);
    final now = DateTime.now();
    final again = _lastTapId == id &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!) < _doubleTapWindow;
    if (again) {
      _lastTapId = null;
      _lastTapAt = null;
      widget.onEnterGroup?.call(id);
      return;
    }
    _lastTapId = id;
    _lastTapAt = now;
  }

  /// The rectangle a composed gesture started from, so a drag depends only on
  /// how far the pointer has moved and not on the path it took.
  DashboardRect? _gestureRect;

  /// Which edge or corner is being pulled. Always the bottom-right for a cell
  /// card, which has only one grip.
  ResizeHandle _handle = ResizeHandle.bottomRight;

  /// The card the editor has been *entered* into, or null.
  ///
  /// At most one, like a text cursor: two live cards would mean two things
  /// claiming the same drop and the same Escape.
  String? _entered;

  /// Held by the entered card's frame, so Escape has somewhere to land.
  final _enteredFocus = FocusNode(debugLabel: 'entered card');

  @override
  void dispose() {
    _enteredFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PageGrid old) {
    super.didUpdateWidget(old);
    // Leaving edit mode, or the card being deleted underneath us, leaves
    // nothing to be inside of.
    if (_entered != null &&
        (!widget.editing || !widget.items.any((i) => i.id == _entered))) {
      _entered = null;
    }
  }

  void _enter(String id) {
    setState(() => _entered = id);
    // Entering is also choosing: the inspector should be showing the card you
    // are now working inside.
    widget.onSelect?.call(id, false);
    _enteredFocus.requestFocus();
  }

  void _leave() {
    if (_entered == null) return;
    setState(() => _entered = null);
    _enteredFocus.unfocus();
  }

  // A gesture (move or resize) works from an immutable snapshot of the layout
  // taken at its start, so the arrangement depends only on where the pointer is
  // *now* — not on the path it took to get there. The engine reflows that
  // snapshot into a stable preview each frame; the committed draft is touched
  // once, on release. That is what stops neighbours from oscillating under the
  // cursor and gives an honest WYSIWYG result.
  List<GridItem>? _baseline;

  /// The rubber band, in cells, while one is being dragged out.
  ///
  /// **Tap adds, drag selects.** Both gestures start on the empty canvas and
  /// the split is the honest one: a tap is pointing at a cell, which is what
  /// placing a card means, and a drag is describing a region, which is what
  /// selecting means. Neither has to be modal and neither steals the other.
  (int, int)? _bandFrom;
  (int, int)? _bandTo;

  /// The same drag, in canvas pixels, while a **drawing** tool is in hand.
  ///
  /// Two representations because the two gestures want different truths. A
  /// selection band asks "which cells did this sweep over", and cells are the
  /// answer. Drawing asks "what rectangle is this", and cells are the wrong
  /// answer by a factor of a hundred: a cell is about 130 by 120 on a desktop
  /// layout, so a rule drawn in cells is a two-by-four block. The band you see
  /// while drawing is the element you are about to get, to the pixel.
  Offset? _drawFrom;
  Offset? _drawTo;

  /// How far the pointer must travel before a press counts as a drawn drag.
  ///
  /// Without it every click with a tool in hand would make a four-pixel
  /// element from the hand-shake — and a click is supposed to make one at a
  /// sensible size instead.
  static const double _drawSlop = 6;

  List<GridItem>? _preview;

  // Move gesture.
  String? _dragId;
  Point _dragStart = const Point(0, 0);
  Offset _accum = Offset.zero;

  // Resize gesture — start holds the card's original (w, h).
  String? _resizeId;
  Point _resizeStart = const Point(0, 0);
  Offset _resizeAccum = Offset.zero;

  /// [items] in the order they should be painted: the grid, then whatever
  /// floats above it, lowest first.
  static List<GridItem> _stacked(List<GridItem> items) {
    final grounded = [
      for (final i in items)
        if (!i.floating) i
    ];
    final floating = [
      for (final i in items)
        if (i.floating) i
    ]..sort((a, b) => a.z.compareTo(b.z));
    return [...grounded, ...floating];
  }

  /// The cell under a point, clamped to the board.
  /// [child] cut to [box], which is in board units while the child's own
  /// coordinates start at its top-left — hence the translation.
  ///
  /// Returns the child untouched when there is nothing to clip to, so a page
  /// with no clipping group pays for none of this: no extra layer, no extra
  /// render object, and the widget tree its tests walk is the one it was.
  /// The card's own transform: turned about its centre, and faded.
  ///
  /// Paint only. The box `AnimatedPositioned` gives the card is untouched, so a
  /// turned card still occupies exactly the cells it did — which is the promise
  /// `docs/dashboard-layout.md` makes and the reason neither value enters the
  /// layout engine. A rotated card may therefore overflow its cells and paint
  /// over a neighbour, which is what turning something on a canvas *means*.
  ///
  /// Neither wrapper is added when there is nothing to apply. An `Opacity` of
  /// 1.0 still costs a saved layer on every card, on a canvas that can hold
  /// dozens.
  static Widget _transformed(GridItem item, Widget child) {
    var out = child;
    final opacity = item.opacity;
    if (opacity != null && opacity < 1) {
      out = Opacity(opacity: opacity.clamp(0.0, 1.0), child: out);
    }
    final rotation = item.rotation;
    if (rotation != null && rotation != 0) {
      out = Transform.rotate(angle: rotation * math.pi / 180, child: out);
    }
    return out;
  }

  static Widget _clipped(
    String id,
    DashboardRect? box,
    double left,
    double top,
    Widget child,
  ) {
    if (box == null) return child;
    return ClipRect(
      key: ValueKey('group-clip:$id'),
      clipper: _ClipTo(Rect.fromLTWH(
        box.x - left,
        box.y - top,
        box.w,
        box.h,
      )),
      child: child,
    );
  }

  static (int, int) _cellOf(Offset p, double stepX, double stepY, int columns) {
    final x = (p.dx / stepX).floor().clamp(0, columns - 1);
    final y = (p.dy / stepY).floor();
    return (x, y < 0 ? 0 : y);
  }

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

        // The geometry of one cell, in the units the board is drawn in. When
        // the layout is composed those units *are* the frame's, because the
        // board is laid out at the frame's width — so a rectangle needs no
        // conversion on the way to the screen, and a cell means the same thing
        // to the guides, the rulers and the snap.
        final geometry = CanvasGeometry(
          width: c.maxWidth,
          columns: columns,
          rowHeight: widget.rowHeight,
          gap: widget.gap,
        );

        // The one place the two representations are reconciled. Everything that
        // draws goes through here, so "the rectangle is the truth and the cells
        // are the fallback" is decided once.
        DashboardRect boxOf(GridItem i) => rectFor(geometry, i, i.rect);

        // The groups with a body, resolved against the very rectangles the
        // cards are about to be drawn from. Empty for every page that has not
        // styled a group, which is all of them until somebody does.
        final containers = widget.groupStyles.isEmpty
            ? const <GroupContainer>[]
            : resolveGroups(widget.groupStyles, widget.groupPaths, (id) {
                for (final i in items) {
                  if (i.id == id) return boxOf(i);
                }
                return null;
              });

        // Only the members of a group that actually clips. A nested clip wins
        // over its ancestor's, because `resolveGroups` orders outermost first
        // and the inner box is the tighter promise.
        final clipTo = <String, DashboardRect>{};
        for (final container in containers) {
          if (!container.box.clip) continue;
          for (final id in membersOf(widget.groupPaths, container.path)) {
            clipTo[id] = container.rect;
          }
        }

        double leftOf(GridItem i) => boxOf(i).x;
        double topOf(GridItem i) => boxOf(i).y;
        double widthOf(GridItem i) => boxOf(i).w;
        double heightOf(GridItem i) => boxOf(i).h;

        final maxRow =
            items.fold<int>(0, (m, i) => i.bottom > m ? i.bottom : m);
        // How far down anything actually reaches, which for a composed page is
        // not a multiple of a row.
        final reach = items.fold<double>(
            0, (m, i) => boxOf(i).bottom > m ? boxOf(i).bottom : m);

        final double height;
        if (widget.frame case final frame?) {
          height = switch (frame.fit) {
            // A fixed canvas *is* its own height — that is what a wall display
            // shows. But while you are editing, a card that has fallen outside
            // it has to stay reachable: shrinking the canvas under a page must
            // not swallow the cards it no longer covers, or the control that
            // resizes it is a control that silently deletes work. So the board
            // grows to reach them and the canvas edge is drawn where it really
            // is.
            DashboardFrameFit.fixed =>
              widget.editing ? math.max(frame.height, reach) : frame.height,
            // A scrolling frame's height is a starting point, so the board is
            // whichever is greater — the page grows past it.
            DashboardFrameFit.scroll => math.max(frame.height, reach),
          };
        } else if (maxRow <= 0) {
          // An empty page still needs a board. Four rows is enough to read as
          // a grid and to aim at, without pretending the page is longer than
          // it is.
          height = widget.rowHeight * (widget.editing ? 4 : 1) +
              (widget.editing ? widget.gap * 3 : 0);
        } else {
          height = maxRow * widget.rowHeight + (maxRow - 1) * widget.gap;
        }

        /// The preview with [id]'s rectangle replaced — a composed element is
        /// placed, not packed, so the engine is deliberately not consulted.
        List<GridItem> composedPreview(String id, DashboardRect rect) => [
              for (final i in _baseline!)
                if (i.id == id)
                  geometry
                      .snapToCells(i.id, rect, floating: i.floating, z: i.z)
                      .copyWith(rect: rect)
                else
                  i,
            ];

        void startDrag(GridItem item) => setState(() {
              _baseline = List<GridItem>.of(widget.items);
              _preview = _baseline;
              _dragId = item.id;
              _dragStart = Point(item.x, item.y);
              _gestureRect = item.rect;
              _accum = Offset.zero;
            });

        void updateDrag(Offset delta) {
          _accum += delta;
          if (_gestureRect case final from?) {
            final rect = from.copyWith(
              x: geometry.snapX(from.x + _accum.dx, on: widget.snapToGrid),
              y: geometry.snapY(from.y + _accum.dy, on: widget.snapToGrid),
            );
            setState(() => _preview = composedPreview(_dragId!, rect));
            return;
          }
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
            if (settled.rect case final rect?) {
              widget.onCompose?.call(id, rect);
            } else {
              widget.onMove?.call(id, settled.x, settled.y);
            }
          }
          setState(() {
            _dragId = null;
            _baseline = null;
            _preview = null;
            _gestureRect = null;
            _accum = Offset.zero;
          });
        }

        void startResize(GridItem item, ResizeHandle handle) => setState(() {
              _baseline = List<GridItem>.of(widget.items);
              _preview = _baseline;
              _resizeId = item.id;
              _resizeStart = Point(item.w, item.h);
              _gestureRect = item.rect;
              _handle = handle;
              _resizeAccum = Offset.zero;
            });

        void updateResize(Offset delta) {
          // Accumulate, like drag — a per-event delta rounds to zero almost
          // every frame and the resize feels dead.
          _resizeAccum += delta;
          if (_gestureRect case final from?) {
            final rect = geometry.resizedBy(from, _handle, _resizeAccum,
                snap: widget.snapToGrid);
            setState(() => _preview = composedPreview(_resizeId!, rect));
            return;
          }
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
            if (settled.rect case final rect?) {
              widget.onCompose?.call(id, rect);
            } else {
              widget.onResize?.call(id, settled.w, settled.h);
            }
          }
          setState(() {
            _resizeId = null;
            _baseline = null;
            _preview = null;
            _gestureRect = null;
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

        // Room to drop a card below the last row while editing — but never on
        // a fixed canvas, which is exactly its own height. Extra board there
        // would mean the thing you are composing is not the thing being
        // measured: Fit would scale to include the slack, and the bottom edge
        // of the design would not be the bottom edge of the page.
        final fixedCanvas = widget.frame?.fit == DashboardFrameFit.fixed;
        final board = SizedBox(
          width: double.infinity,
          height: height + (widget.editing && !fixedCanvas ? stepY * 2 : 0),
          child: Stack(
            // The board is where the page's things ARE, not a frame they may
            // not leave. A `Stack` clips to its own bounds by default, and that
            // default quietly contradicted what this file already says about
            // composed elements: a card may sit at a negative x on purpose,
            // because bleeding something past the edge of a page is a thing
            // people do. It could not — the board cut it off.
            //
            // A group container made that visible. Its padding puts its edge
            // outside its members, so a group flush with the top-left corner
            // drew only the two sides that had room, which reads as a broken
            // border rather than as a clip.
            //
            // Overflow is still bounded: the scroll viewport this sits in does
            // the real clipping, so bleeding reaches the page's own margin and
            // stops there — it cannot paint over the rulers or the rails.
            clipBehavior: Clip.none,
            children: [
              // The column grid, behind everything, while editing. A card's
              // width is only meaningful as a count of columns, and counting
              // them off an unmarked canvas is guesswork — this is the ruler,
              // drawn where the cards actually land rather than as a strip
              // above them.
              if (widget.editing)
                Positioned.fill(
                  // **Raw pointers, not a pan gesture.** The canvas lives
                  // inside two scroll views, and a pan recogniser loses the
                  // arena to them — every band drag became a scroll. A design
                  // tool's artboard background belongs to the marquee; you
                  // scroll it with the wheel or with the bars this shell draws
                  // permanently. So the band takes the pointer directly rather
                  // than negotiating for it.
                  child: MouseRegion(
                    // A crosshair is the whole feedback that a tool is in
                    // hand: the pointer says what the next drag will do before
                    // it does it, which is the difference between a tool you
                    // are holding and a mode you are in.
                    cursor: widget.onDraw != null
                        ? SystemMouseCursors.precise
                        : MouseCursor.defer,
                    child: Listener(
                      onPointerDown:
                          widget.onMarquee == null && widget.onDraw == null
                              ? null
                              : (e) => setState(() {
                                    _bandFrom = _cellOf(
                                        e.localPosition, stepX, stepY, columns);
                                    _bandTo = _bandFrom;
                                    _drawFrom = e.localPosition;
                                    _drawTo = e.localPosition;
                                  }),
                      onPointerMove:
                          widget.onMarquee == null && widget.onDraw == null
                              ? null
                              : (e) {
                                  if (_bandFrom == null) return;
                                  setState(() {
                                    _bandTo = _cellOf(
                                        e.localPosition, stepX, stepY, columns);
                                    _drawTo = e.localPosition;
                                  });
                                },
                      onPointerUp: widget.onMarquee == null &&
                              widget.onDraw == null
                          ? null
                          : (_) {
                              final from = _bandFrom;
                              final to = _bandTo;
                              final drawn = (_drawFrom, _drawTo);
                              setState(() {
                                _bandFrom = null;
                                _bandTo = null;
                                _drawFrom = null;
                                _drawTo = null;
                              });
                              // One band, and what it means is what you are
                              // holding. Drawing is checked first and in
                              // *pixels*, so a rule pulled across half a cell
                              // is still a rule — the cell test below would
                              // have thrown it away as a wobbled tap.
                              if (widget.onDraw case final draw?) {
                                if (drawn.$1 case final a?) {
                                  if (drawn.$2 case final b?) {
                                    if ((a - b).distance >= _drawSlop) {
                                      draw(a, b);
                                      return;
                                    }
                                  }
                                }
                                // Too short to be a drag: the tap handler
                                // below draws one at its own size.
                                return;
                              }
                              // Never left its cell: a tap that wobbled, and
                              // placing a card is what a tap here is for.
                              if (from == null || to == null || from == to) {
                                return;
                              }
                              widget.onMarquee!(
                                from.$1,
                                from.$2,
                                to.$1,
                                to.$2,
                                HardwareKeyboard.instance.isShiftPressed,
                              );
                            },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: widget.onAddAt == null
                            ? null
                            : (details) =>
                                widget.onAddAt!(details.localPosition),
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
                ),

              // The band, while one is being pulled — a catch, or a thing about
              // to exist.
              //
              // The two read differently on purpose. A selection band is a net
              // you throw over what is already there, so it is faint. A draw
              // band *is* the element you are making, at the size it will be,
              // so it is filled and solid-edged: what you let go of is what you
              // see, which is the promise the gesture makes.
              //
              // And the draw band is in *pixels* while the selection band is in
              // cells, for the same reason the callback is: a preview that
              // snapped to cells would promise a two-by-four block and then
              // hand over the thin rule you actually drew.
              if (widget.onDraw != null && _drawFrom != null && _drawTo != null)
                Positioned.fromRect(
                  rect: Rect.fromPoints(_drawFrom!, _drawTo!),
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: t.accent.active.withValues(alpha: 0.14),
                        border: Border.all(
                            color: t.accent.active, width: t.stroke.width * 2),
                      ),
                    ),
                  ),
                )
              else if (_bandFrom case final from?)
                if (_bandTo case final to?)
                  Positioned(
                    left: (from.$1 < to.$1 ? from.$1 : to.$1) * stepX,
                    top: (from.$2 < to.$2 ? from.$2 : to.$2) * stepY,
                    width: ((from.$1 - to.$1).abs() + 1) * stepX - widget.gap,
                    height: ((from.$2 - to.$2).abs() + 1) * stepY - widget.gap,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          color: t.accent.active.withValues(alpha: 0.06),
                          border: Border.all(
                              color: t.accent.active, width: t.stroke.width),
                        ),
                      ),
                    ),
                  ),

              // Where the canvas actually ends, when something is outside it.
              // Without this the page simply looks longer than it is, and the
              // cards past the edge look placed rather than stranded.
              if (widget.frame case final frame?)
                if (widget.editing && reach > frame.height + 0.5)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: frame.height,
                    bottom: 0,
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _OffCanvas(
                          colour: t.surface.onBaseMuted,
                          veil: t.surface.sunken.withValues(alpha: 0.55),
                          style: t.text.captionStyle
                              .copyWith(color: t.surface.onBaseMuted),
                        ),
                      ),
                    ),
                  ),

              // One frame around the group in hand. Without it a group looks
              // exactly like three cards that happen to be selected at the same
              // time, which is the whole difference the feature makes — and it
              // is drawn a gap *outside* the cards so it reads as a container
              // rather than as a fourth selection outline.
              if (widget.groupOutline case (final box, final label))
                Positioned(
                  left: box.x * stepX - widget.gap / 2,
                  top: box.y * stepY - widget.gap / 2,
                  width: box.w * stepX,
                  height: box.h * stepY,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _GroupFrame(
                        label: label,
                        color: t.accent.primary,
                        radius: Radius.circular(t.radius.md),
                        style: t.text.captionStyle.copyWith(
                            color: t.accent.primary,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),

              // The lines saying what the held card agrees with. Above the
              // cards, because a guide under the thing it describes is a guide
              // you cannot see at the moment you need it.
              if (_dragId case final id?)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _SmartGuides(
                        guides: GridEngine(columns: columns)
                            .guidesFor(_preview ?? widget.items, id),
                        stepX: stepX,
                        stepY: stepY,
                        gap: widget.gap,
                        color: t.accent.primary,
                        labelStyle: t.text.captionStyle.copyWith(
                          color: t.surface.base,
                          fontWeight: FontWeight.w600,
                          fontFeatures: t.numericFontFeatures,
                        ),
                        labelBackground: t.accent.primary,
                        labelRadius: t.radius.xsR,
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

              // The groups that have been given a body, under everything they
              // contain. Part of the page rather than part of the selection —
              // drawn in view mode too, because a container that appeared only
              // while you were editing would not be a container.
              //
              // `IgnorePointer` throughout: a container is a backdrop, not a
              // target. Clicking one has to reach the card underneath, or the
              // moment you give a group a background you can no longer press
              // anything in it.
              for (final container in containers)
                Positioned(
                  // Keyed by path so a test — and the inspector — can name the
                  // one container it means. Every card carries a DecoratedBox
                  // of its own, so "the box behind this group" is not something
                  // a type finder can pick out.
                  key: ValueKey('group-box:${container.path}'),
                  left: container.rect.x,
                  top: container.rect.y,
                  width: container.rect.w,
                  height: container.rect.h,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        // **The edge defines it; the fill only lifts it.**
                        //
                        // Tinted by the CONTRASTING colour rather than a
                        // surface token, because every surface token in a skin
                        // is a near neighbour of the others by design —
                        // Midnight's `sunken` is #0d1116 against a #0b0e13
                        // ground, three values apart, and shipped invisible.
                        //
                        // But a fill bright enough to carry the container on
                        // its own overshoots `raised` and ends up BRIGHTER
                        // than the cards standing on it, which reads as one
                        // big card behind three small ones. On the house at 7%
                        // it did exactly that. The two jobs cannot both go to
                        // the fill, so they are split: 3% keeps the wash below
                        // `raised` on all four skins, and the border does the
                        // work of saying where the container ends.
                        color: t.surface.onBase.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(
                            container.box.radius ?? t.radius.lg),
                        border: Border.all(
                          // 0.35, set by the weakest skin rather than the
                          // prettiest. Soft Home is light, so a dark `onBase`
                          // line gains ratio slowly: this is 2.9:1 on Midnight
                          // and only 2.1:1 there, and anything that reached
                          // 3:1 on Soft Home would be a glaring 5:1 rule on
                          // the dark three.
                          color: t.surface.onBase.withValues(alpha: 0.35),
                          width: t.stroke.width,
                        ),
                      ),
                    ),
                  ),
                ),

              // Paint order is stacking order. Grid items first — they cannot
              // be underneath each other, so their order among themselves does
              // not matter — then the floating ones by height. Sorted here
              // rather than upstream so every caller gets it right by default.
              for (final item in _stacked(items))
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
                  child: _clipped(
                    item.id,
                    clipTo[item.id],
                    _dragId == item.id ? draggedLeft(item) : leftOf(item),
                    _dragId == item.id ? draggedTop(item) : topOf(item),
                    _transformed(
                      item,
                      RepaintBoundary(
                        child: _Cell(
                        onConfigChanged: widget.onWidgetConfig == null
                            ? null
                            : (next) => widget.onWidgetConfig!(item.id, next),
                        item: item,
                        model: widget.widgetsById[item.id],
                        editing: widget.editing,
                        simplified: gesturing,
                        dragging: _dragId == item.id || _resizeId == item.id,
                        selected: widget.selectedIds.contains(item.id),
                        entered: _entered == item.id,
                        enteredFocus: _enteredFocus,
                        onEnter: () => _enter(item.id),
                        onLeave: _leave,
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
                            // Shift is read at the moment of the tap rather than
                            // tracked as state: a modifier held while the pointer
                            // was elsewhere is not a modifier held for this click.
                            : () => _tapped(
                                  item.id,
                                  HardwareKeyboard.instance.isShiftPressed,
                                ),
                        onDragStart: () => startDrag(item),
                        onDragUpdate: updateDrag,
                        onDragEnd: endDrag,
                        onResizeStart: (handle) => startResize(item, handle),
                          composed: item.isComposed,
                          onResizeUpdate: updateResize,
                          onResizeEnd: endResize,
                        ),
                      ),
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

        if (!widget.editing) return board;

        // The whole board is a drop target — *around* the cards, not behind
        // them.
        //
        // Behind was the obvious place and it was wrong: a card in the editor
        // is covered by an opaque veil, so a library drag held over one was
        // seen by nothing at all, and letting go there did nothing. Dropping
        // onto the half of a full page that already has cards on it is not an
        // edge case.
        //
        // As an ancestor it is *last* in the hit path, which is exactly the
        // priority we want: a card that claims the drop itself — an entered
        // floor plan turning it into a marker — is deeper, so it wins, and this
        // catches everything it does not.
        return DragTarget<Object>(
          onMove: (details) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            final local = box.globalToLocal(details.offset);
            final x = (local.dx / stepX).floor().clamp(0, columns - 1);
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
          builder: (context, _, __) => board,
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

/// The lines a held card agrees with.
///
/// Drawn the full width or height of the board rather than only between the two
/// cards, because the question a guide answers is "is this in line with
/// anything?" and a stub between two cards makes you find the other end
/// yourself. One line per position, however many cards share it — three cards
/// on the same left edge is one guide, not three drawn on top of each other.
/// Everything past the bottom edge of a fixed canvas.
///
/// Veiled rather than clipped. Clipping is what a wall display does — it shows
/// the canvas and nothing else — but in the designer it would mean a card
/// vanishing the moment you shortened the canvas, with no way to find it and
/// nothing to say it had happened. This shows where the page ends and leaves
/// what is beyond it visible, dimmed, and still draggable back.
class _OffCanvas extends CustomPainter {
  _OffCanvas({required this.colour, required this.veil, required this.style});

  final Color colour;
  final Color veil;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = veil);
    canvas.drawLine(
      Offset.zero,
      Offset(size.width, 0),
      Paint()
        ..color = colour
        ..strokeWidth = 1,
    );
    final text = TextPainter(
      text: TextSpan(text: 'Off the canvas', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, const Offset(6, 4));
  }

  @override
  bool shouldRepaint(_OffCanvas old) => old.veil != veil;
}

/// A dashed frame around the group in hand, with its name on the corner.
///
/// Dashed rather than solid because it is not an edge of anything drawn — no
/// group has a background or a border of its own, and a solid line would
/// promise a container that is not there. The name sits *above* the frame, out
/// of the way of whatever is in the top-left card.
/// A fixed rectangle in the child's own coordinates.
class _ClipTo extends CustomClipper<Rect> {
  const _ClipTo(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(_ClipTo old) => old.rect != rect;
}

class _GroupFrame extends CustomPainter {
  _GroupFrame({
    required this.label,
    required this.color,
    required this.radius,
    required this.style,
  });

  final String label;
  final Color color;
  final Radius radius;
  final TextStyle style;

  static const _dash = 6.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;

    final rect = RRect.fromRectAndRadius(Offset.zero & size, radius);
    // Dashes measured along the path rather than drawn per edge, so the
    // corners stay even instead of restarting the pattern four times.
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      var start = 0.0;
      while (start < metric.length) {
        final end = start + _dash;
        canvas.drawPath(
          metric.extractPath(start, end > metric.length ? metric.length : end),
          paint,
        );
        start = end + _gap;
      }
    }

    final text = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: size.width);
    text.paint(canvas, Offset(0, -text.height - 2));
  }

  @override
  bool shouldRepaint(_GroupFrame old) =>
      old.label != label || old.color != color;
}

class _SmartGuides extends CustomPainter {
  const _SmartGuides({
    required this.guides,
    required this.stepX,
    required this.stepY,
    required this.gap,
    required this.color,
    required this.labelStyle,
    required this.labelBackground,
    required this.labelRadius,
  });

  final List<GridGuide> guides;
  final double stepX;
  final double stepY;
  final double gap;
  final Color color;

  /// For the measurement written on the line. Alignment tells you the edges
  /// agree; the number tells you whether the space above matches the space
  /// below, which is what you are actually judging when you drag something
  /// into a row of others — and the one thing you cannot do by eye across a
  /// scrolled canvas.
  final TextStyle labelStyle;
  final Color labelBackground;
  final BorderRadius labelRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (guides.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    final drawn = <double>{};
    // One measurement per pair of cards, not one per line. Two cards of the
    // same width at the same column agree on three guides and every one of
    // them reports the same distance — three identical labels stacked on top
    // of each other would read as noise, or worse, as three measurements.
    final measured = <String>{};

    for (final guide in guides) {
      // Cell edges sit half a gap in from the step, so a guide on a card's
      // right edge lands on the ink rather than in the gutter beside it.
      final at = guide.isVertical
          ? guide.at * stepX - gap / 2
          : guide.at * stepY - gap / 2;
      final key = guide.isVertical ? at : -at - 1;
      if (drawn.add(key)) {
        canvas.drawLine(
          guide.isVertical ? Offset(at, 0) : Offset(0, at),
          guide.isVertical ? Offset(at, size.height) : Offset(size.width, at),
          paint,
        );
      }

      final cells = guide.gap;
      if (cells == null) continue;
      if (!measured.add('${guide.partner.id}:${guide.isVertical}')) continue;

      // Midway along the space itself, so the number sits *in* the gap it is
      // describing rather than beside one of the two cards.
      final step = guide.isVertical ? stepY : stepX;
      final middle = (guide.gapFrom + cells / 2) * step - gap / 2;
      _label(
        canvas,
        cells.toStringAsFixed(0),
        guide.isVertical ? Offset(at, middle) : Offset(middle, at),
      );
    }
  }

  void _label(Canvas canvas, String text, Offset centre) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = Rect.fromCenter(
      center: centre,
      width: painter.width + 8,
      height: painter.height + 2,
    );
    canvas.drawRRect(
      labelRadius.toRRect(box),
      Paint()..color = labelBackground,
    );
    painter.paint(
      canvas,
      Offset(box.center.dx - painter.width / 2,
          box.center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_SmartGuides old) {
    if (old.guides.length != guides.length ||
        old.stepX != stepX ||
        old.color != color) {
      return true;
    }
    for (var i = 0; i < guides.length; i++) {
      // The measurement is not part of a guide's identity, so it has to be
      // compared here explicitly — a card dragged further from the one it is
      // still aligned with changes the number and nothing else.
      if (old.guides[i] != guides[i] ||
          old.guides[i].gap != guides[i].gap ||
          old.guides[i].gapFrom != guides[i].gapFrom) {
        return true;
      }
    }
    return false;
  }
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
    required this.entered,
    required this.enteredFocus,
    required this.onEnter,
    required this.onLeave,
    required this.sizeLabel,
    required this.onRemove,
    required this.onConfigure,
    required this.onConfigChanged,
    required this.onMenu,
    required this.onSelect,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onResizeStart,
    required this.composed,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  final GridItem item;
  final DashboardWidgetModel? model;
  final bool editing;
  final bool simplified;
  final bool dragging;
  final bool selected;

  /// The editor is inside this card: no veil, no drag, the pointer is the
  /// card's own. See [WidgetDescriptor.inPlaceLabel].
  final bool entered;

  /// Where Escape lands while inside.
  final FocusNode enteredFocus;
  final VoidCallback onEnter;
  final VoidCallback onLeave;

  /// `4×2` while this card is being resized, else null.
  final String? sizeLabel;
  final VoidCallback onRemove;
  final VoidCallback onConfigure;

  /// How this card writes its own config back. Null when nothing is listening,
  /// which is also how a card knows it may not edit itself.
  final ValueChanged<Map<String, dynamic>>? onConfigChanged;
  final void Function(Offset globalPosition) onMenu;

  /// Null outside the surfaces that have somewhere to show a selection.
  final VoidCallback? onSelect;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final ValueChanged<ResizeHandle> onResizeStart;

  /// Composed cards get all eight handles; a cell card keeps its one grip,
  /// because a cell card is anchored top-left and only its extent is in
  /// question.
  final bool composed;
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
                      entered: entered,
                      onConfigChanged: onConfigChanged,
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
    final tint = resolveCardTint(t, style.tint);
    final corner = resolveCardCorner(t, style.corner);
    final radius = corner == null ? null : BorderRadius.circular(corner);
    final image = cardDecorationImage(style);

    final Widget card = switch (chrome) {
      // Draws itself onto the page, and nothing is drawn around it.
      WidgetChrome.bare => SizedBox.expand(child: ClipRect(child: body)),
      // The surface, but the body reaches its edges.
      WidgetChrome.bleed => HcSurface(
          selected: dragging || selected,
          padding: EdgeInsets.zero,
          filled: style.filled,
          bordered: style.bordered,
          tint: tint,
          blur: style.blur,
          borderRadius: radius,
          image: image,
          child: ClipRect(child: body),
        ),
      WidgetChrome.card => HcSurface(
          // Lifted OR chosen. Both mean "this is the one you are working on".
          selected: dragging || selected,
          padding: EdgeInsets.all(t.space.md),
          filled: style.filled,
          bordered: style.bordered,
          tint: tint,
          blur: style.blur,
          borderRadius: radius,
          image: image,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (style.titled && (model?.title ?? '').isNotEmpty)
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

    // Inside the card: the veil comes off.
    //
    // This is the whole point of entering. Everything below — the IgnorePointer
    // and the opaque pan detector over it — exists so a card in the editor is
    // an object you arrange rather than one you operate, and it is total: a
    // floor plan's own Place button rendered *underneath* it, visible and
    // unclickable, and a marker drag never reached the marker. So while we are
    // inside, the card gets the pointer, the grid will not move it, and the
    // only chrome left is the way out.
    if (entered) {
      return Focus(
        focusNode: enteredFocus,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            onLeave();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            Positioned.fill(child: card),
            // Which card you are inside, said on the card. Non-interactive, so
            // it never takes a pointer the card wanted.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: t.radius.mdR,
                    border: Border.all(color: t.accent.active, width: 2),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: _DoneChip(onTap: onLeave),
            ),
          ],
        ),
      );
    }

    // Edit mode: a veil swallows the live widget's own taps, and the frame adds
    // the three things you do to a card — move it, size it, remove it.
    return Stack(
      children: [
        Positioned.fill(child: IgnorePointer(child: card)),
        // Drag anywhere on the body to move.
        Positioned.fill(
          child: _DragBody(
            onDragStart: onDragStart,
            onDragUpdate: onDragUpdate,
            onDragEnd: onDragEnd,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Click to select. It reads as too obvious to write down, and it
              // was missing: the only way to put a card in the inspector was to
              // find the small round options button in its corner. Everything
              // else about the canvas said "direct manipulation" and the first
              // gesture anyone tries did nothing at all.
              onTap: onSelect,
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
        ),
        // Configure + remove.
        Positioned(
          top: 4,
          right: 4,
          child: Row(
            children: [
              // Only for a card that has something to do in place, and only
              // where its edits have somewhere to go.
              if (descriptor?.inPlaceLabel case final label?)
                if (onConfigChanged != null) ...[
                  _RoundButton(
                      icon: HcIcons.pencil, onTap: onEnter, label: label),
                  const SizedBox(width: 4),
                ],
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
        // Resize. One grip on a cell card, eight on a composed one — see
        // [ResizeHandle].
        if (!composed)
          Positioned(
            right: 0,
            bottom: 0,
            child: _Grip(
              handle: ResizeHandle.bottomRight,
              onStart: onResizeStart,
              onUpdate: onResizeUpdate,
              onEnd: onResizeEnd,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                child: Icon(HcIcons.grip,
                    size: 13, color: t.accent.active.withValues(alpha: 0.8)),
              ),
            ),
          )
        // Only on the card in hand. Eight grips on every card at once is a
        // board of dots rather than a page you can read.
        else if (selected)
          for (final handle in ResizeHandle.values)
            Positioned(
              // Inside the card's own bounds, never outside them: a Stack does
              // not hit-test a child beyond its edges, so a handle hanging off
              // the corner would be drawn and not grabbable.
              //
              // An edge handle spans its whole side *less the corners*, so the
              // two never fight over the same pixel — the corner is the one
              // that resizes both axes, and losing it to the edge lying on top
              // of it would cost the gesture people reach for most.
              // Pinned to the edges it moves, and stretched across the axis it
              // does not.
              left: handle.movesRight ? null : 0,
              right: handle.movesLeft ? null : 0,
              top: handle.movesBottom ? null : 0,
              bottom: handle.movesTop ? null : 0,
              width: handle.movesLeft || handle.movesRight ? _gripSize : null,
              height: handle.movesTop || handle.movesBottom ? _gripSize : null,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal:
                      handle.movesLeft || handle.movesRight ? 0 : _gripSize,
                  vertical:
                      handle.movesTop || handle.movesBottom ? 0 : _gripSize,
                ),
                child: _Grip(
                  handle: handle,
                  onStart: onResizeStart,
                  onUpdate: onResizeUpdate,
                  onEnd: onResizeEnd,
                  child: Center(
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: t.surface.base,
                        border: Border.all(color: t.accent.active),
                        borderRadius: t.radius.xsR,
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

/// How big a resize handle is to hit.
///
/// Sixteen rather than the seven that is drawn: the dot is the affordance, the
/// box around it is what you actually have to land on, and a handle you have to
/// aim at is a handle you avoid.
const double _gripSize = 16;

/// One resize handle. Raw pointers, for the reason [_DragBody] gives: inside
/// two scroll views a pan recogniser's outcome depends on how the events
/// arrive.
class _Grip extends StatefulWidget {
  const _Grip({
    required this.handle,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.child,
  });

  final ResizeHandle handle;
  final ValueChanged<ResizeHandle> onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;
  final Widget child;

  @override
  State<_Grip> createState() => _GripState();
}

class _GripState extends State<_Grip> {
  bool _pulling = false;

  static const _cursors = {
    ResizeHandle.topLeft: SystemMouseCursors.resizeUpLeft,
    ResizeHandle.top: SystemMouseCursors.resizeUp,
    ResizeHandle.topRight: SystemMouseCursors.resizeUpRight,
    ResizeHandle.right: SystemMouseCursors.resizeRight,
    ResizeHandle.bottomRight: SystemMouseCursors.resizeDownRight,
    ResizeHandle.bottom: SystemMouseCursors.resizeDown,
    ResizeHandle.bottomLeft: SystemMouseCursors.resizeDownLeft,
    ResizeHandle.left: SystemMouseCursors.resizeLeft,
  };

  void _end() {
    if (_pulling) widget.onEnd();
    _pulling = false;
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: _cursors[widget.handle]!,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (event.buttons != kPrimaryButton) return;
            _pulling = true;
            widget.onStart(widget.handle);
          },
          onPointerMove: (event) {
            if (_pulling) widget.onUpdate(event.localDelta);
          },
          onPointerUp: (_) => _end(),
          onPointerCancel: (_) => _end(),
          child: Semantics(
            // A bare corner to drag was invisible to assistive tech and
            // unnamed to everyone else.
            label: 'Resize card',
            child: widget.child,
          ),
        ),
      );
}

/// The way out of a card you are inside.
///
/// A word rather than another round glyph: every other button on a card's frame
/// is an action *on* the card, and this one is the only thing that changes what
/// your pointer means. It says so, and it says the shortcut.
class _DoneChip extends StatelessWidget {
  const _DoneChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Tooltip(
      message: 'Done — or press Escape',
      child: Material(
        color: t.accent.active,
        shape: RoundedRectangleBorder(borderRadius: t.radius.pillR),
        child: InkWell(
          borderRadius: t.radius.pillR,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: t.space.sm, vertical: t.space.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(HcIcons.check, size: 13, color: t.accent.onPrimary),
                SizedBox(width: t.space.xs),
                Text('Done',
                    style: t.text.captionStyle
                        .copyWith(color: t.accent.onPrimary)),
              ],
            ),
          ),
        ),
      ),
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
