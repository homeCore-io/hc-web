import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show BrowserContextMenu, Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dashboard/breakpoints.dart';
import '../../core/dashboard/canvas_view.dart';
import '../../core/dashboard/constraints.dart';
import '../../core/dashboard/clipboard.dart';
import '../../core/dashboard/design_tools.dart';
import '../../core/dashboard/device_slot.dart';
import '../../core/dashboard/frame.dart';
import '../../core/dashboard/frame_space.dart';
import '../../core/dashboard/free_layer.dart';
import '../../core/dashboard/grid_engine.dart';
import '../../core/dashboard/group_frame.dart';
import '../../core/dashboard/groups.dart';
import '../../core/dashboard/layout_write.dart';
import '../../core/dashboard/page_starts.dart';
import '../../core/dashboard/repeat.dart';
import '../../core/text/humanize.dart';
import '../../core/dashboard/widget_registry.dart';
import '../../core/models/dashboard.dart';
import '../../core/models/device_state.dart';
import '../../core/providers/dashboards_provider.dart';
import '../../core/devices/breakdown.dart' show prettyGroup;
import '../../core/providers/page_room_provider.dart';
import '../../core/providers/devices_provider.dart';
import '../../design/components/hc_controls.dart';
import '../../design/components/hc_dialog.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';
import '../../shell/shell_scope.dart';
import 'breakpoint_bar.dart';
import 'card_inspector.dart';
import 'card_library.dart';
import 'designer_shell.dart';
import 'page_actions.dart';
import 'page_grid.dart';
import 'scaled_canvas.dart';
import 'widget_config_form.dart';
import 'widget_palette.dart';

/// A dashboard, as an app page you can rearrange in place.
///
/// This is the replacement for the old CMS: same underlying document, same grid
/// engine, same widget registry — but you edit the page *on the page*, dragging
/// live cards, instead of navigating away to a 2,000-line form. View and edit
/// are one surface with a mode, which is the whole difference.
class PageScreen extends ConsumerStatefulWidget {
  const PageScreen(
      {super.key, required this.dashboardId, this.designer = false, this.room});

  final String dashboardId;

  /// The room this page is being shown for, from the route's `?room=`.
  ///
  /// One room page serves every room — `room_field` sends the room rather than
  /// opening one of fifteen copies — so everything on the page that says
  /// `@room` resolves against this. Null on a page opened without one, where
  /// `@room` stays unresolved rather than guessing a room.
  final String? room;

  /// The full-page design surface rather than the house.
  ///
  /// Phase 2 of `designer-plan.md`. The same screen, because the editing state
  /// machine — drafts, per-breakpoint arrangements, pending placements, ghosts,
  /// what a save does to the layouts you are not looking at — is intricate and
  /// a second copy of it would drift. What differs is the presentation: the
  /// designer fills the viewport, keeps both panes open, and is always editing.
  final bool designer;

  @override
  ConsumerState<PageScreen> createState() => _PageScreenState();
}

/// The draft, frozen. Everything an undo has to put back.
class _Snapshot {
  const _Snapshot({
    required this.label,
    required this.coalesce,
    required this.items,
    required this.layouts,
    required this.widgets,
    required this.touched,
    required this.contentDirty,
    required this.selected,
    required this.background,
  });

  /// What the *next* action was, so the button can name what it will undo.
  final String label;
  final String coalesce;
  final List<GridItem> items;
  final List<DashboardLayout> layouts;
  final Map<String, DashboardWidgetModel> widgets;
  final Set<DashboardBreakpoint> touched;
  final bool contentDirty;

  /// What was in hand. Undo puts you back where you were, and
  /// where you were includes what you were looking at.
  final Set<String> selected;
  final DashboardBackground? background;
}

class _PageScreenState extends ConsumerState<PageScreen> {
  @override
  void initState() {
    super.initState();
    // Right-click in a design tool means the tool's menu, and the browser's
    // would cover it. Only in the designer, and restored on the way out: on an
    // ordinary page the browser menu is useful — copying a device name out of
    // one is a reasonable thing to want.
    if (kIsWeb && widget.designer) BrowserContextMenu.disableContextMenu();
  }

  /// A different page arrived in the same screen.
  ///
  /// **This is a data-loss guard, not housekeeping.** Going from one design
  /// route straight to another — `/pages/a/design` to `/pages/b/design` —
  /// reuses this State, because go_router sees the same widget in the same
  /// place. Every draft field survived that: the canvas showed page A's cards
  /// under page B's name, and pressing Save wrote A's widgets and layouts onto
  /// B. Nothing warned, and the only tell was the title.
  ///
  /// It is the same failure `layout_write.dart` exists to prevent, one level
  /// up: an editor that writes back something it never read. There it was the
  /// other breakpoints; here it is the other *page*.
  @override
  void didUpdateWidget(PageScreen old) {
    super.didUpdateWidget(old);
    if (old.dashboardId == widget.dashboardId) return;
    // Everything below belongs to the page that just left. The designer
    // re-enters editing on the next build, so dropping the draft is enough —
    // it does not have to be rebuilt here.
    _exitEditing();
    setState(() {
      _draftBackground = null;
      _undo.clear();
      _redo.clear();
      _inside = null;
      _dismissedStart = false;
    });
    // `_editing` is derived from the draft, so clearing the draft above has
    // already ended the edit — there is no flag to reset and no way for the two
    // to disagree.
  }

  @override
  void dispose() {
    if (kIsWeb && widget.designer) BrowserContextMenu.enableContextMenu();
    super.dispose();
  }

  /// Every layout, in whatever state the edit has left them — null means view
  /// mode. A working copy so Cancel leaves the saved page exactly as it was.
  ///
  /// The draft holds *all* the layouts rather than just the one on screen,
  /// because the breakpoint bar lets you move between them in a single session.
  /// It is kept as the true projection at all times: each gesture runs
  /// `writeArrangement` immediately, so switching breakpoints is a read and
  /// Save is a push, and neither has to reconstruct what the other did.
  List<DashboardLayout>? _draftLayouts;

  /// The selected breakpoint's arrangement, as the grid works in.
  List<GridItem>? _draftItems;
  Map<String, DashboardWidgetModel>? _draftWidgets;

  /// The card the inspector is showing, when there is room for one.
  /// What is selected, in the order it was picked.
  ///
  /// A set rather than a single id, because align, distribute, group and every
  /// keyboard action that moves something act on *what you have in hand* — and
  /// with one id in hand, "distribute" has no meaning at all, which is why the
  /// canvas shipped without it. See [GridEngine.distribute].
  final _selection = <String>{};

  /// The one selected card, or null when there is not exactly one.
  ///
  /// The inspector edits a card, not a crowd: two cards selected have two
  /// titles and two configs and no honest single form. So the panel reads this
  /// and shows the multi-selection summary when it is null but the selection is
  /// not empty.
  String? get _selectedCard => _selection.length == 1 ? _selection.first : null;

  /// The starting points have been dismissed for this session.
  ///
  /// View state, and only for the *blank* start: the other two hide the chooser
  /// by putting something on the page or a canvas under it, which is a fact
  /// about the document and survives a reload. "Just the grid" changes nothing
  /// at all, so the only thing it can mean is *stop offering*.
  bool _dismissedStart = false;

  /// What is in hand at the toolbar.
  ///
  /// View state like the zoom, and deliberately **not** sticky across a
  /// session: a designer that opened with the shape tool still held from
  /// yesterday would make a rectangle out of the first click of the day.
  DesignTool _tool = DesignTool.select;

  /// Whether a composed drag is pulled to the cell edges.
  ///
  /// View state, like the zoom: how you are working on a page is not a fact
  /// about the page. On by default, because the grid is what every existing
  /// arrangement lines up with and a composition that starts by drifting off it
  /// is a worse starting point than one that starts on it.
  bool _snapToGrid = true;

  /// The group you have stepped into, or null at the top of the page.
  ///
  /// A group is held as one thing, so getting at a single member means going
  /// inside first. This is where you are standing; it is view state like the
  /// zoom, never saved, and it survives no longer than the session.
  String? _inside;

  /// What group each element belongs to, by id.
  Map<String, String?> get _paths => {
        for (final e
            in (_draftWidgets ?? const <String, DashboardWidgetModel>{})
                .entries)
          e.key: groupOf(e.value.config),
      };

  /// The same map, from whichever copy of the widgets is being drawn.
  ///
  /// [_paths] reads the draft, which is null outside an edit — fine for the
  /// grouping *gestures*, which only exist while editing. Containers are not a
  /// gesture: they are part of the page, so in view mode the membership has to
  /// come from the saved widgets or every container would resolve to nothing
  /// the moment you left the editor.
  Map<String, String?> _pathsIn(Map<String, DashboardWidgetModel> widgets) =>
      _draftWidgets != null
          ? _paths
          : {for (final e in widgets.entries) e.key: groupOf(e.value.config)};

  /// What clicking [id] on the canvas actually puts in hand.
  ///
  /// The element itself when it is loose or when you are already standing in
  /// its group; otherwise every member of the group at the next level down.
  Set<String> _clickHolds(String id, Map<String, String?> paths) {
    final target = clickTarget(paths[id], _inside);
    return target == null ? {id} : membersOf(paths, target);
  }

  /// Replace the selection, or add to it — shift-click, in one place.
  ///
  /// [direct] takes the element and only the element, whatever group it is in.
  /// The elements strip addresses things individually — that is what a layers
  /// panel is for — while the canvas holds clusters.
  void _select(String? id, {bool additive = false, bool direct = false}) {
    setState(() {
      if (id == null) {
        _selection.clear();
        return;
      }
      final paths = _paths;
      // Reaching for something outside the group you are standing in steps you
      // out of it. Ignoring the click instead would be a canvas that stops
      // responding for reasons nothing on screen explains.
      if (_inside case final here?) {
        final path = paths[id];
        if (path == null || !isUnder(path, here)) _inside = null;
      }
      final holds = direct ? {id} : _clickHolds(id, paths);
      if (!additive) {
        _selection
          ..clear()
          ..addAll(holds);
        return;
      }
      // Shift-clicking something already held takes it back out, which is how
      // you fix a selection you overshot without starting again. A group goes
      // in and out whole.
      if (holds.every(_selection.contains)) {
        _selection.removeAll(holds);
      } else {
        _selection.addAll(holds);
      }
    });
  }

  /// Step into the group under [id], so its members can be picked apart.
  ///
  /// Double-click, the gesture every drawing tool uses for it. Does nothing for
  /// a loose element or one you are already as deep as.
  void _enterGroup(String id) {
    final paths = _paths;
    final target = clickTarget(paths[id], _inside);
    if (target == null) return;
    setState(() {
      _inside = target;
      final holds = _clickHolds(id, paths);
      _selection
        ..clear()
        ..addAll(holds);
    });
  }

  /// Step back out one level, holding the group you were inside.
  ///
  /// Holding it rather than letting go: stepping out of a group to move the
  /// whole thing is the reason you step out, and an empty selection would make
  /// you click it again.
  bool _leaveGroup() {
    final here = _inside;
    if (here == null) return false;
    setState(() {
      _inside = stepOut(here);
      _selection
        ..clear()
        ..addAll(membersOf(_paths, here));
    });
    return true;
  }

  /// The single group every selected element is in, or null when there is not
  /// one — which is what decides whether there is anything to name or dissolve.
  String? get _groupInHand => _selection.isEmpty
      ? null
      : commonGroup(_selection.map((id) => _paths[id]));

  /// The box to draw around the group in hand, and what to call it.
  ///
  /// Null unless the whole of one group is held: a partial selection inside a
  /// group is not a group, and framing it would draw a container around
  /// something that is not one.
  (GridItem, String)? get _groupOutline {
    final target = _groupInHand;
    if (target == null) return null;
    final members = membersOf(_paths, target);
    if (members.length != _selection.length) return null;
    final items = [
      for (final i in _draftItems ?? const <GridItem>[])
        if (members.contains(i.id)) i,
    ];
    if (items.isEmpty) return null;
    var x = items.first.x, y = items.first.y;
    var right = items.first.right, bottom = items.first.bottom;
    for (final i in items) {
      if (i.x < x) x = i.x;
      if (i.y < y) y = i.y;
      if (i.right > right) right = i.right;
      if (i.bottom > bottom) bottom = i.bottom;
    }
    return (
      GridItem(id: target, x: x, y: y, w: right - x, h: bottom - y),
      // The name alone, not the path: the frame is drawn where the group is, so
      // where it sits is already on screen.
      nameOf(target),
    );
  }

  /// Give the group in hand a body, or change the one it has.
  ///
  /// Written onto the layout being edited and no other. A container is a box on
  /// a *page*, and the page differs by breakpoint — styling a group on the wall
  /// must not put a background behind it on the phone, where the same cards are
  /// a single scrolling column and the box would enclose the whole screen.
  ///
  /// A box that says nothing the default would not is *removed* rather than
  /// stored, which is what makes the switch in the panel reversible: turning
  /// the container off leaves the group exactly as it was before anyone gave it
  /// one, rather than leaving a row behind that means nothing.
  void _setGroupBox(GroupBox next) {
    final layouts = _draftLayouts;
    if (layouts == null || _editingBreakpoint == null) return;
    _pushUndo(next.isPlain ? 'Remove the container' : 'Change the container',
        coalesce: 'group-box-${next.path}');
    setState(() {
      _draftLayouts = [
        for (final l in layouts)
          if (l.breakpoint != _editingBreakpoint)
            l
          else
            l.copyWith(groups: [
              for (final g in l.groups)
                if (g.path != next.path) g,
              if (!next.isPlain) next,
            ]),
      ];
      _contentDirty = true;
    });
  }

  /// Make the group in hand a frame, or stop it being one.
  ///
  /// The one edit in the designer that changes what the document's numbers
  /// *mean* rather than what they are, and the whole requirement is that
  /// **nothing moves**. Turning it on must leave every card exactly where it
  /// was on screen; turning it off must put it back.
  ///
  /// Which is why almost nothing happens here. The draft holds page
  /// coordinates — every gesture on the canvas produces them and always has —
  /// and page coordinates are precisely what this edit does not change. So the
  /// cards are not touched at all, and `_commit` writes them into whatever
  /// space the frames then describe. The only rectangles that need restating
  /// are the *boxes'* own, because a container nested inside the new frame is
  /// measured from it too, and `rebase` does that arithmetic as a round trip
  /// rather than as a shift — see `frame_space.dart` for why that distinction
  /// is worth the words.
  ///
  /// **A frame has to state a rectangle**, so turning it on materialises one
  /// from where the members currently are. That is the only geometry invented
  /// here, and it is invented to sit exactly around what is already there.
  void _setGroupFrame(String path, bool on) {
    final layouts = _draftLayouts;
    final items = _draftItems;
    final selected = _editingBreakpoint;
    if (layouts == null || items == null || selected == null) return;
    final layout = layouts.where((l) => l.breakpoint == selected).firstOrNull;
    if (layout == null) return;

    final before = framesByPath(layout.groups);
    final existing = layout.groups.where((g) => g.path == path).firstOrNull;

    var rect = existing?.rect;
    if (on && rect == null) {
      final members = membersOf(_paths, path);
      final bounds = boundsOfRects([
        for (final i in items)
          if (members.contains(i.id))
            if (i.rect case final r?) r,
      ]);
      // Nothing composed to be around. A packed group has no rectangles of its
      // own — its members are positioned by cells — so there is no honest box
      // to invent and nothing to measure from. The panel does not offer this
      // on such a layout; this is the guard for the case it is called anyway.
      if (bounds == null) return;
      // Materialised in the box's *parent's* space, which is where a box's
      // rectangle lives. On an unnested group that is the page, and this is
      // the identity.
      rect = toLocal(bounds, spaceOfBox(path), before);
    }

    final next =
        (existing ?? GroupBox(path: path)).copyWith(frame: on, rect: rect);
    final rebased = rebase(
      boxes: [
        for (final g in layout.groups)
          if (g.path != path) g,
        if (!next.isPlain) next,
      ],
      before: before,
      // The cards are already where they belong: see above.
      paths: const {},
      rects: const {},
    );

    _pushUndo(on ? 'Hold things inside the group' : 'Let the group go');
    setState(() {
      _draftLayouts = [
        for (final l in layouts)
          if (l.breakpoint != selected)
            l
          else
            l.copyWith(groups: rebased.boxes),
      ];
      _contentDirty = true;
    });
  }

  /// A frame put somewhere new — dragged by its name, or pulled by an edge.
  ///
  /// Two things move, and only one of them is written down. The **box** gets a
  /// new rectangle, restated in whatever space it sits in. The **members** are
  /// not touched in the document at all — their rectangles are stated inside
  /// this frame, and the frame is what moved — but the draft holds them
  /// resolved to the page, so those resolved numbers are carried along here or
  /// the next edit would localise stale positions and snap everything back to
  /// where the frame used to be.
  ///
  /// The layout is updated *before* the commit, deliberately: `_commit`
  /// localises against the frames it finds, and the frame it must find is the
  /// one at its new position.
  void _setFrameRect(String path, DashboardRect pageRect) {
    final layouts = _draftLayouts;
    final items = _draftItems;
    final selected = _editingBreakpoint;
    if (layouts == null || items == null || selected == null) return;
    final layout = layouts.where((l) => l.breakpoint == selected).firstOrNull;
    if (layout == null) return;

    final frames = framesByPath(layout.groups);
    final box = layout.groups.where((g) => g.path == path).firstOrNull;
    final was = box == null ? null : pageRectOf(box, frames);
    if (box == null || was == null) return;

    // Bail on the whole rectangle, not on the corner: pulling the right edge
    // moves nothing and resizes everything, and a guard that only watched the
    // corner would drop it on the floor.
    if (pageRect == was) return;

    // **Every member is re-resolved rather than nudged**, and stating it that
    // way is what makes the two halves of a frame gesture one piece of
    // arithmetic instead of two that have to agree.
    //
    // Down into the old frame's space, apply whatever the member's pin says
    // about the *size* change, back up through the new one. The **corner**
    // falls out of the last step — a member is stated from the frame's
    // top-left, so it goes wherever that corner goes, the whole way on a move,
    // the whole way when the left or top edge is pulled, and not at all when
    // it is the right or bottom. The **size** is `constraints.dart`, and for
    // everything nobody has pinned that is the identity, so a page written
    // before pins existed resizes exactly as it did yesterday.
    final boxes = [
      for (final g in layout.groups)
        if (g.path == path)
          // A box's own rectangle lives in its *parent's* space, which for a
          // frame at the top of the page is the page.
          g.copyWith(rect: toLocal(pageRect, spaceOfBox(path), frames))
        else
          g,
    ];
    final after = framesByPath(boxes);
    final widgets = _draftWidgets ?? const <String, DashboardWidgetModel>{};
    final paths = _paths;
    final carried = membersOf(paths, path);

    /// [rect] where it ends up, in page units.
    DashboardRect settled(String id, DashboardRect rect) {
      final where = paths[id];
      var local = toLocal(rect, where, frames);
      // Pins are the *nearest* frame's business. A card two frames down is
      // measured from the inner one, and the inner one has not changed size —
      // it has only moved, which the resolve below already carries. Applying
      // this frame's size change to it would stretch it twice.
      if (nearestFrame(where, frames) == path) {
        local = applyPins(
          local,
          Pins.fromConfig(widgets[id]?.config ?? const {}),
          was: was.w,
          wasHeight: was.h,
          now: pageRect.w,
          nowHeight: pageRect.h,
        );
      }
      return toPage(local, where, after);
    }

    _pushUndo(
      pageRect.w == was.w && pageRect.h == was.h
          ? 'Move ${nameOf(path)}'
          : 'Resize ${nameOf(path)}',
      coalesce: 'frame:$path',
    );
    setState(() {
      _draftLayouts = [
        for (final l in layouts)
          if (l.breakpoint != selected) l else l.copyWith(groups: boxes),
      ];
      _commit([
        for (final i in items)
          if (i.rect case final rect? when carried.contains(i.id))
            i.copyWith(rect: settled(i.id, rect))
          else
            i,
      ]);
    });
  }

  /// Write a new path onto a set of elements, as one undoable edit.
  void _writePaths(String label, Map<String, String?> next) {
    final widgets = _draftWidgets;
    if (widgets == null || next.isEmpty) return;
    _pushUndo(label);
    setState(() {
      final updated = {...widgets};
      for (final entry in next.entries) {
        final model = updated[entry.key];
        if (model == null) continue;
        updated[entry.key] =
            model.copyWith(config: withGroup(model.config, entry.value));
      }
      _draftWidgets = updated;
      _contentDirty = true;
    });
  }

  /// Hold these as one thing from now on.
  void _groupSelection() {
    if (_selection.isEmpty) return;
    final paths = _paths;
    final name = freshName(namesIn(paths.values, _inside));
    final path = join(_inside, name);
    _writePaths('Group ${_selection.length} elements', {
      for (final id in _selection) id: regrouped(paths[id], path, _inside),
    });
  }

  /// Dissolve the group in hand.
  ///
  /// Every member of it, not only what is selected: the group is going away, so
  /// leaving part of the page still pointing at it would leave a group that
  /// exists and cannot be selected.
  void _ungroupSelection() {
    final target = _groupInHand;
    if (target == null) return;
    final paths = _paths;
    _writePaths('Ungroup ${nameOf(target)}', {
      for (final id in membersOf(paths, target))
        id: ungrouped(paths[id], target),
    });
    // Standing inside what was just dissolved is standing nowhere.
    if (_inside case final here?) {
      if (isUnder(here, target)) setState(() => _inside = stepOut(target));
    }
  }

  /// Rename the group in hand, carrying everything under it.
  void _renameGroup(String desired) {
    final target = _groupInHand;
    if (target == null) return;
    final paths = _paths;
    final siblings = namesIn(paths.values, parentOf(target))
      ..remove(nameOf(target));
    final to = join(parentOf(target), uniqueName(desired, siblings));
    if (to == target) return;
    _writePaths('Rename ${nameOf(target)}', {
      for (final id in membersOf(paths, target))
        id: renamedPath(paths[id], target, to),
    });
    if (_inside case final here?) {
      if (isUnder(here, target)) {
        setState(() => _inside = renamedPath(here, target, to));
      }
    }
  }

  bool _saving = false;

  bool get _editing => _draftItems != null;

  static const _defaultColumns = 12;
  static const _defaultRowHeight = 120.0;
  static const _defaultGap = 12.0;

  /// The breakpoint being arranged. Set when editing starts so a window resize
  /// mid-edit cannot silently retarget the save, and thereafter only by the
  /// breakpoint bar.
  DashboardBreakpoint? _editingBreakpoint;

  /// Which breakpoints the person actually rearranged.
  ///
  /// Selecting a layout is not editing it. A derived layout must survive being
  /// looked at — it only stops following when someone moves something in it,
  /// and that distinction is the difference between a switcher you can explore
  /// and one that quietly detaches everything you click on.
  final Set<DashboardBreakpoint> _touched = {};

  /// A card's own content changed — its config, or its name.
  ///
  /// Separate from [_touched] because the two mean different things and were
  /// briefly the same flag. [_touched] means "this layout was arranged by
  /// hand", which is what detaches a derived layout from the one it follows;
  /// renaming a card is not arranging anything, and marking the breakpoint
  /// touched for it would silently cut a layout loose from its source.
  ///
  /// It had a second cost, and that one was already shipped: the unsaved
  /// indicator read [_touched], so changing a card's room in the inspector left
  /// the bar saying **Saved** while the change sat unsaved in the draft.
  bool _contentDirty = false;

  /// The page's background, while it is being edited. Null means "as saved".
  DashboardBackground? _draftBackground;

  /// Undo, as a stack of draft snapshots.
  ///
  /// `designer-plan.md` §5.1 argued a timed snackbar was enough, because
  /// removal was the only act that destroyed work. Two things changed. There
  /// are now more of them — a rename, a style and a selection edit all
  /// overwrite something — and a *timed* undo makes it a race you can lose by
  /// reading the sentence. John: *"the undo bar at the bottom is just bad, some
  /// other undo button on the top panel should exist and be active when undo is
  /// available."*
  ///
  /// A snapshot is cheap because the draft is already a value: three immutable
  /// collections and a set. Bounded, because this is an undo affordance and not
  /// a document history.
  final List<_Snapshot> _undo = [];

  /// The states undo has walked back past, newest last.
  ///
  /// There was no redo at all before this: undo was a one-way stack, so an
  /// undo pressed once too often cost you the change with no way back. A
  /// history panel over that would have been a list you can only walk in one
  /// direction, which is not a history — it is a receipt.
  final List<_Snapshot> _redo = [];
  static const _undoDepth = 20;

  /// Whether the oldest state we hold has been dropped off the end of the cap.
  bool _trimmed = false;

  /// Cards added during this edit, and not yet settled on every hand-arranged
  /// layout.
  ///
  /// A new card reaches the breakpoint you added it on and every layout
  /// following that one, because those have no arrangement of their own to
  /// disturb. It does **not** barge into a layout someone arranged by hand —
  /// that would reflow their work to make room for something they have not
  /// looked at yet. Instead it is announced there, with both ways out.
  ///
  /// Session-scoped on purpose: the question "where does this new card go on
  /// the phone?" belongs to the session that added it. Once answered — placed
  /// or left off — it is answered, and a card deliberately left off stays off,
  /// because [reconcileWidgetSet] no longer re-adds what it did not add.
  final Set<String> _pendingPlacement = {};

  /// `breakpoint:widgetId` pairs already decided — placed here, or deliberately
  /// left off here.
  final Set<String> _settled = {};

  /// The layout for [wanted], falling back through [availableBreakpoint] and
  /// finally to an empty desktop layout for a dashboard that has none.
  DashboardLayout _layoutFor(
      DashboardDefinition d, DashboardBreakpoint wanted) {
    final available = availableBreakpoint(d, wanted);
    if (available == null) {
      return DashboardLayout(
        breakpoint: wanted,
        columns: wanted == DashboardBreakpoint.mobile ? 4 : _defaultColumns,
        rowHeight: _defaultRowHeight,
        gap: _defaultGap,
        placements: const [],
      );
    }
    return d.layoutFor(available);
  }

  List<GridItem> _itemsFrom(DashboardDefinition d, DashboardLayout layout) {
    final frames = framesByPath(layout.groups);
    return [
      for (final p in layout.placements)
        if (d.widgetById(p.widgetId) case final w?)
          GridItem(
            id: p.widgetId,
            x: p.x,
            y: p.y,
            w: p.w,
            h: p.h,
            minW: WidgetRegistry.lookup(w.type)?.sizeHint.minW ?? 1,
            minH: WidgetRegistry.lookup(w.type)?.sizeHint.minH ?? 1,
            // Lifted-ness travels with the element, in its config — see
            // `free_layer.dart`. Read here, where the widget is in scope, so
            // the engine never has to know what a config is.
            floating: isFloating(w.config),
            z: zOf(w.config),
            // The composition, the angle and the fade travel on the
            // *placement*, and every one of them has to be read back or the
            // next save writes over it with what the cells alone imply.
            // Stated in the element's frame's space, drawn in the page's —
            // see `frame_space.dart`. One conversion here means no gesture
            // downstream has to know what a frame is.
            rect: placedRect(p.rect, groupOf(w.config), frames),
            rotation: p.rotation,
            opacity: p.opacity,
          ),
    ];
  }

  void _startEditing(DashboardDefinition d, DashboardBreakpoint breakpoint) {
    final layout = _layoutFor(d, breakpoint);
    var items = _itemsFrom(d, layout);

    // A widget placed on *no* layout at all would be dropped on the first save,
    // so it is given a home here. A widget missing from only *this* layout is a
    // different thing entirely — someone left it off this breakpoint — and
    // force-placing it would undo that decision simply because you opened the
    // layout to look at it. Only the orphans get rescued.
    final engine = GridEngine(
        columns: layout.columns <= 0 ? 12 : layout.columns, flow: layout.flow);
    final placedSomewhere = {
      for (final l in d.layouts)
        for (final p in l.placements) p.widgetId,
    };
    for (final w in d.widgets) {
      if (placedSomewhere.contains(w.id)) continue;
      final hint =
          WidgetRegistry.lookup(w.type)?.sizeHint ?? const WidgetSizeHint();
      items = engine.add(
        items,
        GridItem(
          id: w.id,
          x: 0,
          y: 0,
          w: hint.recommendedW,
          h: hint.recommendedH,
          minW: hint.minW,
          minH: hint.minH,
        ),
      );
    }

    // Every breakpoint the document has, plus the one being edited if it was
    // missing. The draft is the whole set from here on.
    final layouts = [...d.layouts];
    if (!layouts.any((l) => l.breakpoint == breakpoint)) {
      layouts.add(_layoutFor(d, breakpoint));
    }

    setState(() {
      _draftLayouts = layouts;
      _draftItems = items;
      _draftWidgets = {for (final w in d.widgets) w.id: w};
      _editingBreakpoint = breakpoint;
      _touched.clear();
      _contentDirty = false;
      _draftBackground = null;
      _undo.clear();
      _redo.clear();
      _trimmed = false;
      _dismissedStart = false;
      _inside = null;
      _pendingPlacement.clear();
      _settled.clear();
    });
  }

  /// Records an edit to the selected breakpoint and reprojects the draft.
  ///
  /// Every gesture goes through here, so `_draftLayouts` is always what a save
  /// would write — including the recomputed followers. That is what lets the
  /// bar switch breakpoints by simply reading, and what stops Save from having
  /// to replay anything.
  void _commit(List<GridItem> items) {
    final selected = _editingBreakpoint!;
    _touched.add(selected);
    _draftItems = items;
    // `placeEverywhere` is deliberately empty: nothing lands in a hand-arranged
    // layout without being asked for. A new card reaches the breakpoint it was
    // added on and everything following it; elsewhere it is announced, and the
    // notice row is what places it.
    _draftLayouts = writeArrangement(
      layouts: _draftLayouts!,
      // The draft holds page coordinates, because that is what every gesture
      // on the canvas produces; the document holds each element's rectangle in
      // its frame's space. This is the one place the two meet.
      items: itemsToLocal(
        items,
        _paths,
        framesByPath(_draftLayouts!
                .where((l) => l.breakpoint == selected)
                .firstOrNull
                ?.groups ??
            const []),
      ),
      edited: selected,
    );
  }

  /// The frame [id] sits in, by name, or null when it sits on the page.
  ///
  /// The *nearest* framed ancestor rather than the group it belongs to: a card
  /// in `Panel/Row` where only `Panel` is a frame is grouped in `Row` and
  /// measured from `Panel`, and it is `Panel` whose size its pins are about.
  String? _frameAround(String? id) {
    if (id == null) return null;
    final groups = _draftLayouts
        ?.where((l) => l.breakpoint == _editingBreakpoint)
        .firstOrNull
        ?.groups;
    if (groups == null) return null;
    final path = nearestFrame(_paths[id], framesByPath(groups));
    return path == null ? null : nameOf(path);
  }

  /// Whether the layout being edited composes rather than packs.
  bool get _composedHere =>
      _draftLayouts
          ?.where((l) => l.breakpoint == _editingBreakpoint)
          .firstOrNull
          ?.isComposed ??
      false;

  /// The pixel shape of the layout being edited, in the units it is drawn in.
  CanvasGeometry _geometry(int columns) {
    final layout = _draftLayouts
        ?.where((l) => l.breakpoint == _editingBreakpoint)
        .firstOrNull;
    return CanvasGeometry(
      width: layout?.frame?.width ??
          previewWidthFor(_editingBreakpoint ?? DashboardBreakpoint.desktop) ??
          1600,
      columns: columns,
      rowHeight: layout?.rowHeight ?? _defaultRowHeight,
      gap: layout?.gap ?? _defaultGap,
    );
  }

  /// Turn composition on for a layout, or hand it back to the grid.
  ///
  /// **Nothing moves either way**, and that is the whole requirement. Turning it
  /// on gives every element the rectangle its cells already describe, so the
  /// page you were looking at is the page you get. Turning it off drops the
  /// rectangles and leaves the cells, which have been kept in step all along —
  /// so it costs you the fractions and nothing else.
  ///
  /// A page that rearranged itself the moment you enabled a mode would have
  /// lost the arrangement the mode exists to let you refine.
  void _setComposed(bool on, DashboardBreakpoint breakpoint, int columns) {
    if (_draftItems == null || _draftLayouts == null) return;
    _pushUndo(on ? 'Compose freely' : 'Back to the grid');
    final geometry = _geometry(columns);
    setState(() {
      _draftLayouts = [
        for (final l in _draftLayouts!)
          if (l.breakpoint == breakpoint)
            l.copyWith(
              frame: on ? frameForGrid(geometry, _draftItems!) : null,
              // Composed elements are placed, not packed, so a composed layout
              // is a free one by construction — leaving it packed would mean
              // the next save closed every gap somebody composed.
              flow: on ? GridFlow.free : l.flow,
            )
          else
            l,
      ];
      _commit([
        for (final i in _draftItems!)
          i.copyWith(rect: on ? geometry.rectOfItem(i) : null),
      ]);
    });
  }

  /// Begin a page from one of the starting points — see `page_starts.dart`.
  ///
  /// One undo entry for the whole thing, because it is one decision. Undoing a
  /// start card by card would be undoing something nobody did.
  void _startPage(PageStartKind kind, DashboardBreakpoint breakpoint,
      int columns, String? room, String? label) {
    if (_draftItems == null || _draftLayouts == null) return;
    // Blank changes nothing, so it is not an edit — it is the chooser being
    // dismissed. Pushing an undo entry for it would put a step in the history
    // that undoes to the state it started from.
    if (kind == PageStartKind.blank) {
      setState(() => _dismissedStart = true);
      return;
    }
    final cards = startCards(kind, room: room, label: label);
    final frame = startFrame(kind);
    _pushUndo('Start the page');

    // Stacked down the page in the order the start names them, rather than
    // packed by the engine: a starting point is an arrangement, and letting the
    // packer decide would make the same choice produce different pages
    // depending on what happened to fit.
    final widgets = {...?_draftWidgets};
    final items = [..._draftItems!];
    var y = items.fold<int>(0, (m, i) => i.bottom > m ? i.bottom : m);
    var n = DateTime.now().microsecondsSinceEpoch;
    for (final card in cards) {
      final id = 'widget_${n++}';
      widgets[id] = DashboardWidgetModel(
        id: id,
        type: card.type,
        title: card.title,
        refreshPolicy: DashboardRefreshPolicy.live,
        config: card.config,
      );
      items.add(GridItem(
        id: id,
        x: 0,
        y: y,
        w: card.w.clamp(1, columns),
        h: card.h,
      ));
      y += card.h;
    }

    setState(() {
      _draftWidgets = widgets;
      _contentDirty = true;
      if (frame != null) {
        _draftLayouts = [
          for (final l in _draftLayouts!)
            if (l.breakpoint == breakpoint)
              l.copyWith(frame: frame, flow: GridFlow.free)
            else
              l,
        ];
      }
      final geometry = frame == null
          ? null
          : CanvasGeometry(
              width: frame.width,
              columns: columns,
              rowHeight: _draftLayouts!
                      .where((l) => l.breakpoint == breakpoint)
                      .map((l) => l.rowHeight)
                      .firstOrNull ??
                  _defaultRowHeight,
              gap: _draftLayouts!
                      .where((l) => l.breakpoint == breakpoint)
                      .map((l) => l.gap)
                      .firstOrNull ??
                  _defaultGap,
            );
      _commit([
        for (final i in items)
          if (geometry == null) i else i.copyWith(rect: geometry.rectOfItem(i)),
      ]);
    });
  }

  /// Resize the canvas, or change what its height promises.
  ///
  /// **Nothing on the page moves.** Making a canvas bigger does not move what
  /// is drawn on it — that is what a canvas is. The alternative, scaling every
  /// rectangle to match, would turn typing in a number field into an edit that
  /// touched every element on the page, and there is no way to do that *and*
  /// leave a design somebody nudged into place alone.
  ///
  /// The cells are recomputed, because they must be: a cell is a fraction of
  /// the canvas width, so the same rectangle is a different column once the
  /// canvas is wider. Leaving them stale would let the snapped fallback drift
  /// away from the composition it is supposed to approximate — and core
  /// validates the stale one.
  void _setFrame(DashboardFrame frame, DashboardBreakpoint breakpoint) {
    if (_draftItems == null || _draftLayouts == null) return;
    _pushUndo('Resize the canvas', coalesce: 'frame:${breakpoint.name}');
    final geometry = CanvasGeometry(
      width: frame.width,
      columns: _draftLayouts!
              .where((l) => l.breakpoint == breakpoint)
              .map((l) => l.columns)
              .firstOrNull ??
          _defaultColumns,
      rowHeight: _draftLayouts!
              .where((l) => l.breakpoint == breakpoint)
              .map((l) => l.rowHeight)
              .firstOrNull ??
          _defaultRowHeight,
      gap: _draftLayouts!
              .where((l) => l.breakpoint == breakpoint)
              .map((l) => l.gap)
              .firstOrNull ??
          _defaultGap,
    );
    setState(() {
      _draftLayouts = [
        for (final l in _draftLayouts!)
          if (l.breakpoint == breakpoint) l.copyWith(frame: frame) else l,
      ];
      _commit([
        for (final i in _draftItems!)
          if (i.rect case final rect?)
            geometry
                .snapToCells(i.id, rect, floating: i.floating, z: i.z)
                .copyWith(rect: rect)
          else
            i,
      ]);
    });
  }

  /// A composed element was put somewhere.
  ///
  /// Deliberately not through [_apply]: that runs the packing engine, which is
  /// exactly what must not happen to something a person placed on a canvas.
  /// The cells are recomputed alongside so the snapped approximation core
  /// validates stays true to the rectangle.
  void _composeCard(String id, DashboardRect rect, int columns) {
    if (_draftItems == null) return;
    final geometry = _geometry(columns);

    // **Where you drop it is what it joins.**
    //
    // Every other way into a group is a command — select these, group them,
    // name it — which is right for a cluster you are gathering and wrong for a
    // template you are filling. There, putting a control in a panel is a thing
    // you do by dragging it onto the panel, and being made to select-and-group
    // afterwards is the tool asking you to say twice what you already said
    // once. This is the gesture "widgets are placed inside the template"
    // actually names.
    //
    // Only frames catch. An ordinary group is a tag several elements agree on
    // and has no inside to fall into — a card dragged across one is a card
    // that happens to be over it.
    final frames = framesByPath(_draftLayouts
            ?.where((l) => l.breakpoint == _editingBreakpoint)
            .firstOrNull
            ?.groups ??
        const []);
    final leaving = nearestFrame(_paths[id], frames);
    final joining = frameHolding(rect, frames);
    final moved = joining != leaving;

    final model = _draftWidgets?[id];
    final what = model == null ? 'it' : _cardLabel(model);
    _pushUndo(
      !moved
          ? 'Move'
          : joining != null
              ? 'Put $what in ${nameOf(joining)}'
              : 'Take $what out of ${nameOf(leaving!)}',
      // Empty means *never fold this into the edit before it*. A re-parenting
      // is a different edit from the drags around it: undoing "put this in the
      // panel" has to give back the card **and** where it was.
      coalesce: moved ? '' : 'compose:$id',
    );
    setState(() {
      _goFree();
      if (moved) {
        // Written before the commit, because `_commit` localises against
        // `_paths` and the path this card is about to be measured from is the
        // new one. Its *page* rectangle does not change at all — it is where
        // you let go of it — so nothing on screen moves and only the number in
        // the document does.
        if (model != null) {
          _draftWidgets = {
            ..._draftWidgets!,
            id: model.copyWith(
              config: withGroup(
                model.config,
                reparented(_paths[id], leaving, joining),
              ),
            ),
          };
        }
      }
      _commit([
        for (final i in _draftItems!)
          if (i.id == id)
            geometry
                .snapToCells(id, rect, floating: i.floating, z: i.z)
                .copyWith(rect: rect)
          else
            i,
      ]);
    });
  }

  /// The flow of the layout being edited. Everything that moves a card must
  /// run under it, or a free layout gets repacked by whichever call site
  /// forgot.
  GridFlow get _editedFlow =>
      _draftLayouts
          ?.where((l) => l.breakpoint == _editingBreakpoint)
          .firstOrNull
          ?.flow ??
      GridFlow.packed;

  GridEngine _engine(int columns) =>
      GridEngine(columns: columns, flow: _editedFlow);

  /// Remember the draft as it is *now*, labelled with what is about to happen.
  ///
  /// [coalesce] collapses a run of the same edit into one entry — typing a name
  /// is one undo, not one per keystroke. The *first* snapshot of the run is the
  /// one kept, because that is the state before you started typing.
  void _pushUndo(String label, {String coalesce = ''}) {
    if (_draftItems == null) return;
    // A new edit abandons the future. Keeping it would mean redo replaying a
    // change onto a page that no longer has the thing it changed.
    _redo.clear();
    if (coalesce.isNotEmpty &&
        _undo.isNotEmpty &&
        _undo.last.coalesce == coalesce) {
      return;
    }
    _undo.add(_snapshotNow(label, coalesce));
    if (_undo.length > _undoDepth) {
      _undo.removeAt(0);
      // The oldest state we hold is no longer the one the page opened in, and
      // the history panel has to stop claiming it is.
      _trimmed = true;
    }
  }

  /// The draft exactly as it stands, labelled.
  _Snapshot _snapshotNow(String label, String coalesce) => _Snapshot(
        label: label,
        coalesce: coalesce,
        items: List<GridItem>.of(_draftItems ?? const []),
        layouts: List<DashboardLayout>.of(_draftLayouts ?? const []),
        widgets:
            Map<String, DashboardWidgetModel>.of(_draftWidgets ?? const {}),
        touched: Set<DashboardBreakpoint>.of(_touched),
        contentDirty: _contentDirty,
        selected: Set<String>.of(_selection),
        background: _draftBackground,
      );

  /// Put the draft back to [snap], without a [setState] of its own.
  ///
  /// Callers wrap a whole move in one, because jumping several steps along the
  /// history restores several snapshots and only the last one is worth drawing.
  void _restore(_Snapshot snap) {
    _draftItems = snap.items;
    _draftLayouts = snap.layouts;
    _draftWidgets = snap.widgets;
    _touched
      ..clear()
      ..addAll(snap.touched);
    _contentDirty = snap.contentDirty;
    _draftBackground = snap.background;
    // Restored too, but only if it survived — a snapshot taken before a card
    // was added has no such card to select.
    _selection
      ..clear()
      ..addAll(snap.selected.where(snap.widgets.containsKey));
    // Standing inside a group that the snapshot has no members for is standing
    // nowhere, and every click would then behave as though it were somewhere.
    if (_inside case final here?) {
      if (!snap.widgets.values.any((w) {
        final path = groupOf(w.config);
        return path != null && isUnder(path, here);
      })) {
        _inside = null;
      }
    }
  }

  /// One step back. The state being left becomes the one redo returns to.
  void _stepBack() {
    if (_undo.isEmpty) return;
    final snap = _undo.removeLast();
    // Labelled with the edit it undoes, so redo can name the same thing undo
    // just named — they are two directions along one move, not two moves.
    _redo.add(_snapshotNow(snap.label, snap.coalesce));
    _restore(snap);
  }

  void _stepForward() {
    if (_redo.isEmpty) return;
    final snap = _redo.removeLast();
    _undo.add(_snapshotNow(snap.label, snap.coalesce));
    _restore(snap);
  }

  void _undoLast() => setState(_stepBack);
  void _redoNext() => setState(_stepForward);

  /// Everything this session has been through, oldest first.
  ///
  /// The panel shows *positions*, not edits: row 0 is where the page started
  /// and every row after it is named for the change that produced it. That is
  /// why the count is one more than the number of edits — you can stand before
  /// the first one.
  List<HistoryEntry> get _historyEntries {
    if (_draftItems == null) return const [];
    return [
      HistoryEntry(
        // Honest about the cap: once the oldest snapshot has been dropped this
        // is no longer the state the page opened in, and saying "Opened" would
        // promise a place you can no longer get back to.
        label: _trimmed ? 'Earlier changes' : 'Opened',
        future: false,
      ),
      for (var i = 0; i < _undo.length; i++)
        HistoryEntry(label: _undo[i].label, future: false),
      for (var i = _redo.length - 1; i >= 0; i--)
        HistoryEntry(label: _redo[i].label, future: true),
    ];
  }

  /// Which row of [_historyEntries] the draft is standing on.
  int get _historyAt => _undo.length;

  /// Walk to [index] by stepping, so one move and twenty are the same code.
  void _jumpHistory(int index) {
    final target = index.clamp(0, _undo.length + _redo.length);
    if (target == _historyAt) return;
    setState(() {
      while (_historyAt > target) {
        _stepBack();
      }
      while (_historyAt < target) {
        _stepForward();
      }
    });
  }

  void _apply(List<GridItem> Function(GridEngine e, List<GridItem> items) op,
      int columns,
      {bool byHand = false, String label = 'Move'}) {
    _pushUndo(label);
    setState(() {
      if (byHand) _goFree();
      _commit(op(_engine(columns), _draftItems!));
    });
  }

  /// Arranging by hand makes this layout keep its gaps.
  ///
  /// The same shape as the rule that makes a derived layout authored: nothing
  /// flips it but a person moving something. Opening the page, switching
  /// breakpoints and resizing the window all leave it alone, and a layout
  /// nobody has arranged keeps packing, which is what every existing document
  /// expects.
  ///
  /// It is not a toggle because a toggle would have to be found. Leaving a gap
  /// and having it stay is the whole feature; discovering it by doing it is
  /// better than discovering a checkbox.
  void _goFree() {
    final selected = _editingBreakpoint;
    if (selected == null || _draftLayouts == null) return;
    _draftLayouts = [
      for (final l in _draftLayouts!)
        if (l.breakpoint == selected && l.flow != GridFlow.free)
          l.copyWith(flow: GridFlow.free)
        else
          l,
    ];
  }

  /// A draft layout's placements as grid items, with each card's size hints
  /// reattached from the registry — the engine needs them to refuse a resize
  /// below a card's minimum.
  List<GridItem> _draftItemsFor(DashboardBreakpoint b) {
    final layout = _draftLayouts!.firstWhere((l) => l.breakpoint == b);
    final frames = framesByPath(layout.groups);
    return [
      for (final p in layout.placements)
        if (_draftWidgets![p.widgetId] case final w?)
          GridItem(
            id: p.widgetId,
            x: p.x,
            y: p.y,
            w: p.w,
            h: p.h,
            minW: WidgetRegistry.lookup(w.type)?.sizeHint.minW ?? 1,
            minH: WidgetRegistry.lookup(w.type)?.sizeHint.minH ?? 1,
            // Lifted-ness travels with the element, in its config — see
            // `free_layer.dart`. Read here, where the widget is in scope, so
            // the engine never has to know what a config is.
            floating: isFloating(w.config),
            z: zOf(w.config),
            // The composition, the angle and the fade travel on the
            // *placement*, and every one of them has to be read back or the
            // next save writes over it with what the cells alone imply.
            rect: placedRect(p.rect, groupOf(w.config), frames),
            rotation: p.rotation,
            opacity: p.opacity,
          ),
    ];
  }

  /// Where the selected layout's cards would sit if it still followed [source].
  ///
  /// Only meaningful for a layout that has diverged: one still following is
  /// identical to its own ghost, and drawing an outline exactly under every
  /// card is noise dressed as information. So the ghost appears precisely when
  /// there is a divergence to see, which is also precisely when the question
  /// "did I mean to diverge?" is worth asking.
  List<GridItem> _ghostFor(DashboardBreakpoint selected,
      DashboardBreakpoint source, List<DashboardLayout> layouts) {
    if (selected == source) return const [];
    final layout = layouts.where((l) => l.breakpoint == selected).firstOrNull;
    if (layout == null || layout.derivedFrom != null) return const [];

    final sourceLayout =
        layouts.where((l) => l.breakpoint == source).firstOrNull;
    if (sourceLayout == null) return const [];

    final derived = deriveLayout(
      layout,
      [
        for (final p in sourceLayout.placements)
          GridItem(id: p.widgetId, x: p.x, y: p.y, w: p.w, h: p.h),
      ],
    );
    return [
      for (final p in derived.placements)
        GridItem(id: p.widgetId, x: p.x, y: p.y, w: p.w, h: p.h),
    ];
  }

  /// Moves to another breakpoint mid-edit. A read, not a write: selecting a
  /// layout must never be what takes it over.
  void _selectBreakpoint(DashboardBreakpoint next) {
    if (next == _editingBreakpoint) return;
    setState(() {
      _editingBreakpoint = next;
      _draftItems = _draftItemsFor(next);
    });
  }

  /// Hands the selected layout back to [source] and shows the result at once,
  /// so "follow desktop again" is a thing you see rather than a thing you are
  /// told happened.
  void _revertSelected(DashboardBreakpoint source) {
    final selected = _editingBreakpoint!;
    final sourceLayout =
        _draftLayouts!.where((l) => l.breakpoint == source).firstOrNull;
    if (sourceLayout == null) return;

    final sourceItems = [
      for (final p in sourceLayout.placements)
        GridItem(id: p.widgetId, x: p.x, y: p.y, w: p.w, h: p.h),
    ];

    setState(() {
      _draftLayouts = [
        for (final l in _draftLayouts!)
          if (l.breakpoint == selected)
            // The containers come back too. Reverting means "follow that
            // layout again", and a revert that restored the arrangement but
            // left this breakpoint's own containers behind would leave the
            // page half-reverted.
            revertToDerived(l, source, sourceItems,
                sourceGroups: sourceLayout.groups)
          else
            l,
      ];
      _touched.remove(selected);
      // Reload from the draft so the reverted arrangement is on screen at once.
      _draftItems = _draftItemsFor(selected);
    });
  }

  /// Adds a card, at ([atX], [atY]) when the canvas was pointed at.
  ///
  /// Without a target this is the old behaviour — the engine's first fit — and
  /// that is still right for the button, which is not pointing anywhere.
  Future<void> _addWidget(int columns, {int? atX, int? atY}) async {
    final created = await showWidgetPalette(context);
    if (created == null || !mounted) return;
    final engine = _engine(columns);
    final hint =
        WidgetRegistry.lookup(created.type)?.sizeHint ?? const WidgetSizeHint();
    // Clamped so a card dropped near the right edge lands whole rather than
    // hanging off the board and being reflowed somewhere surprising.
    final x = atX == null
        ? 0
        : atX.clamp(0, (columns - hint.recommendedW).clamp(0, columns));
    final item = GridItem(
      id: created.id,
      x: x,
      y: atY ?? 0,
      w: hint.recommendedW,
      h: hint.recommendedH,
      minW: hint.minW,
      minH: hint.minH,
    );
    setState(() {
      _draftWidgets = {...?_draftWidgets, created.id: created};
      _pendingPlacement.add(created.id);
      _commit(atX == null
          ? engine.add(_draftItems!, item)
          : engine.addAt(_draftItems!, item, atX, atY ?? 0));
    });
  }

  /// Cards this session added that the selected layout has no place for.
  ///
  /// Only hand-arranged layouts can be in this state: a following one is
  /// recomputed whole and always has everything.
  List<DashboardWidgetModel> _unplacedHere(DashboardBreakpoint selected) {
    if (_draftLayouts == null || _pendingPlacement.isEmpty) return const [];
    final layout =
        _draftLayouts!.where((l) => l.breakpoint == selected).firstOrNull;
    if (layout == null || layout.derivedFrom != null) return const [];
    final placed = {for (final p in layout.placements) p.widgetId};
    return [
      for (final id in _pendingPlacement)
        if (!placed.contains(id) &&
            !_settled.contains(_settledKey(selected, id)))
          if (_draftWidgets?[id] case final w?) w,
    ];
  }

  /// A decision is per layout, not per card: leaving a card off the phone says
  /// nothing about whether it belongs on the wall, and a single global "dealt
  /// with" flag would silently answer for every other hand-arranged layout.
  static String _settledKey(DashboardBreakpoint b, String id) =>
      '${b.name}:$id';

  /// Puts a pending card on the selected layout, at the first place it fits.
  void _placeHere(String id, DashboardBreakpoint selected, int columns) {
    final hint =
        WidgetRegistry.lookup(_draftWidgets?[id]?.type ?? '')?.sizeHint ??
            const WidgetSizeHint();
    final engine = _engine(columns);
    setState(() {
      _settled.add(_settledKey(selected, id));
      _commit(engine.add(
        _draftItems!,
        GridItem(
          id: id,
          x: 0,
          y: 0,
          w: hint.recommendedW.clamp(1, columns),
          h: hint.recommendedH,
          minW: hint.minW.clamp(1, columns),
          minH: hint.minH,
        ),
      ));
    });
  }

  /// Leaves a pending card off the selected layout for good.
  ///
  /// Nothing to undo in the document — it is already absent — so this only
  /// stops the asking. The absence persists because the reconcile no longer
  /// re-adds what it did not add.
  void _keepOffHere(String id, DashboardBreakpoint selected) {
    setState(() => _settled.add(_settledKey(selected, id)));
  }

  /// Removes a card, and offers it back.
  ///
  /// The only action in the designer whose inverse is not a gesture. A
  /// mis-drag is undone by dragging back and a wrong room by picking another,
  /// but a removed card takes its configuration with it — which room, which
  /// devices, which limit — and putting it back means rebuilding all of that
  /// from memory. That is what earns an undo here, and what makes a general
  /// history stack unnecessary everywhere else.
  void _removeWidget(String id, int columns) {
    final engine = _engine(columns);
    final model = _draftWidgets?[id];
    // Captured before the removal, including where it sat: restoring a card to
    // the top-left would be a different page from the one you had.
    final item =
        _draftItems?.where((i) => i.id == id).cast<GridItem?>().firstOrNull;

    if (model != null && item != null) {
      _pushUndo('Remove ${_cardLabel(model)}');
    }
    setState(() {
      _draftWidgets = {...?_draftWidgets}..remove(id);
      _selection.remove(id);
      _commit(engine.remove(_draftItems!, id));
    });
  }

  /// The card menu, at the pointer.
  ///
  /// Every entry here is reachable another way — that is deliberate. A context
  /// menu is a shortcut for someone who already knows what they want, not the
  /// only door to anything, because a menu you have to discover by right-
  /// clicking is a menu most people never open.
  ///
  /// The size presets are the one thing here that is genuinely faster than the
  /// alternative: dragging a card to exactly half the grid means counting
  /// columns, and "Half width" is what you actually meant.
  /// `⌘C` on a Mac, `Ctrl+C` everywhere else — the label only, for a menu.
  ///
  /// Read from the platform rather than from the pointer, because the keyboard
  /// is what it describes: a Mac keyboard has a Command key whatever is
  /// plugged into the mouse port.
  static String _shortcut(String key) =>
      defaultTargetPlatform == TargetPlatform.macOS ? '⌘$key' : 'Ctrl+$key';

  Future<void> _cardMenu(String id, Offset at, int columns) async {
    final model = _draftWidgets?[id];
    final item =
        _draftItems?.where((i) => i.id == id).cast<GridItem?>().firstOrNull;
    if (model == null || item == null) return;

    _select(id);

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(value: 'configure', child: Text('Configure')),
        const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        // Beside Duplicate, because it is duplicate with a purpose: one copy
        // per device, each wired to its own. See `repeat.dart` for the number
        // this exists for.
        const PopupMenuItem(
            value: 'repeat', child: Text('Repeat for devices…')),
        const PopupMenuDivider(),
        // Copy, cut and paste were keyboard-only when they landed, which for
        // most people is the same as not existing. The shortcut is shown
        // beside each one so the menu teaches the keyboard rather than
        // replacing it — the way you find out ⌘C works here is by looking for
        // Copy and reading what is next to it.
        _MenuRow.item('copy', 'Copy', _shortcut('C')),
        _MenuRow.item('cut', 'Cut', _shortcut('X')),
        _MenuRow.item('paste', 'Paste', _shortcut('V')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'half', child: Text('Half width')),
        const PopupMenuItem(value: 'full', child: Text('Full width')),
        const PopupMenuDivider(),
        // Named for what happens to the card, not for the mechanism. "Free
        // layer" is our word; "float above the grid" is what you can see.
        if (item.floating) ...[
          const PopupMenuItem(
              value: 'ground', child: Text('Put back in the grid')),
          const PopupMenuItem(value: 'front', child: Text('Bring to front')),
          const PopupMenuItem(value: 'forward', child: Text('Bring forward')),
          const PopupMenuItem(value: 'backward', child: Text('Send backward')),
          const PopupMenuItem(value: 'back', child: Text('Send to back')),
        ] else
          const PopupMenuItem(
              value: 'lift', child: Text('Float above the grid')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'remove', child: Text('Remove')),
      ],
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case 'configure':
        _select(id);
      case 'duplicate':
        _duplicateCard(model, item, columns);
      case 'copy':
        await _copySelection();
      case 'cut':
        // Copy first and only remove if it landed. A cut whose copy silently
        // failed is a delete, and the card is gone with nothing to paste.
        if (await _copySelection()) {
          if (mounted) _removeWidget(id, columns);
        }
      case 'paste':
        await _paste(
          columns,
          _draftLayouts
                  ?.where((l) => l.breakpoint == _editingBreakpoint)
                  .firstOrNull
                  ?.isComposed ??
              false,
        );
      case 'half':
        _apply((e, its) => e.resize(its, id, columns ~/ 2, item.h), columns,
            byHand: true);
      case 'full':
        _apply((e, its) => e.resize(its, id, columns, item.h), columns,
            byHand: true);
      case 'lift':
        _stack(id, StackMove.lift, columns);
      case 'ground':
        _stack(id, StackMove.ground, columns);
      case 'front':
        _stack(id, StackMove.front, columns);
      case 'back':
        _stack(id, StackMove.back, columns);
      case 'forward':
        _stack(id, StackMove.forward, columns);
      case 'backward':
        _stack(id, StackMove.backward, columns);
      case 'repeat':
        await _repeatForDevices(id, columns);
      case 'remove':
        _removeWidget(id, columns);
    }
  }

  /// One design, once per device — see `repeat.dart`.
  ///
  /// **What is repeated is what is in hand**, which is the whole reason this
  /// is on the card menu rather than in a panel: a row is usually a cluster,
  /// and a cluster is what a click on one of its members already selects.
  /// Right-clicking a light row and asking for six of them is the gesture; the
  /// alternative is a form asking which elements you meant, about a thing you
  /// are pointing at.
  ///
  /// Only on a composed layout. Stamping copies at a step of so many pixels
  /// means nothing on a page positioned by cells, where the engine decides
  /// where things land.
  Future<void> _repeatForDevices(String id, int columns) async {
    final widgets = _draftWidgets;
    final items = _draftItems;
    if (widgets == null || items == null || !_composedHere) return;

    // The selection when this card is in it, so a row selected as a group
    // repeats as a row; otherwise just this card.
    final chosen = _selection.contains(id) && _selection.length > 1
        ? _selection
        : _clickHolds(id, _paths);
    final design = [
      for (final wid in chosen)
        if (widgets[wid] case final w?) w,
    ];
    final placed = [
      for (final item in items)
        if (chosen.contains(item.id)) item,
    ];
    if (design.isEmpty || placed.any((i) => i.rect == null)) return;

    final devices = ref.read(devicesProvider).value ?? const <DeviceState>[];
    final picked =
        await pickDevices(context, devices, single: false, selected: const {});
    if (picked == null || picked.isEmpty || !mounted) return;

    // In the order they were picked, mapped through the house so a device that
    // has gone away between the picker opening and closing is simply absent
    // rather than a row wired to nothing.
    final byId = {for (final d in devices) d.id: d};
    final set = [
      for (final deviceId in picked)
        if (byId[deviceId] case final d?) d,
    ];
    if (set.isEmpty) return;

    var n = DateTime.now().microsecondsSinceEpoch;
    final out = repeatFor(
      design: design,
      items: placed,
      devices: set,
      step: stepFor(placed),
      stamp: (_) => 'widget_${n++}',
      takenPaths: _paths.values.whereType<String>().toSet(),
    );

    _pushUndo(set.length == 1
        ? 'Wire to ${set.first.displayName}'
        : 'Repeat for ${set.length} devices');
    setState(() {
      _draftWidgets = {...widgets, ...out.rewired, ...out.widgets};
      _pendingPlacement.addAll(out.widgets.keys);
      _commit([...items, ...out.items]);
    });
  }

  /// Lifts a card above the grid, puts it back, or moves it within the stack.
  ///
  /// One operation for all six controls, because they are all the same edit:
  /// change the element's config, then re-derive the item the engine sees from
  /// it. Doing those separately is how the two halves drift — the document says
  /// floating and the layout still packs it, or the reverse.
  ///
  /// The engine runs afterwards so the grid closes up behind a card that has
  /// just left it, which is the thing you want to see happen.
  void _restack(String id, String label, int columns,
      Map<String, dynamic> Function(Map<String, dynamic> config) change) {
    final model = _draftWidgets?[id];
    if (model == null) return;
    _pushUndo(label);

    final config = change(model.config);
    setState(() {
      _draftWidgets = {...?_draftWidgets, id: model.copyWith(config: config)};
      _contentDirty = true;
      // Lifting is arranging by hand: a card taken out of the flow has left a
      // hole somebody chose, and a layout that repacked it on the next save
      // would undo the whole gesture.
      _goFree();
      _commit(_engine(columns).normalize([
        for (final i in _draftItems!)
          if (i.id == id)
            i.copyWith(floating: isFloating(config), z: zOf(config))
          else
            i,
      ]));
    });
  }

  /// One stacking request, from wherever it was made.
  ///
  /// The card menu and the inspector both go through here, so "forward" cannot
  /// come to mean two different things depending on which control you reached
  /// for. The heights in use are known here and nowhere else.

  /// Turn the selected card, or fade it.
  ///
  /// One entry in the history per gesture rather than per frame: dragging a
  /// slider emits a value on every pixel, and a stack that recorded each one
  /// would take a hundred presses to undo one drag. `coalesce` collapses the
  /// run, exactly as renaming a card does.
  ///
  /// The two are separate methods because `null` is a real value for both —
  /// back to none, not to zero — and one method taking two nullables could not
  /// say which of them it had been asked to change.
  /// Move or resize an element by typing, rather than by dragging.
  ///
  /// Coalesced per element the way a rotation is, so typing a width and then a
  /// height is one undo rather than two — and typing 1, 2, 0 into a width is
  /// one, not three.
  void _reposition(String id, DashboardRect rect) => _transform(
        id,
        'Move the card',
        'rect-',
        (i) => i.copyWith(rect: rect),
      );

  void _rotate(String id, double? degrees) => _transform(
        id,
        'Turn the card',
        'rotation-$id',
        (i) => i.copyWith(rotation: degrees),
      );

  void _fade(String id, double? opacity) => _transform(
        id,
        'Fade the card',
        'opacity-$id',
        (i) => i.copyWith(opacity: opacity),
      );

  void _transform(
    String id,
    String label,
    String coalesce,
    GridItem Function(GridItem) change,
  ) {
    if (_draftItems == null) return;
    _pushUndo(label, coalesce: coalesce);
    setState(() {
      _commit([
        for (final i in _draftItems!)
          if (i.id == id) change(i) else i,
      ]);
    });
  }

  void _stack(String id, StackMove move, int columns) {
    final model = _draftWidgets?[id];
    if (model == null) return;
    final label = switch (move) {
      StackMove.lift => 'Float ${_cardLabel(model)}',
      StackMove.ground => 'Ground ${_cardLabel(model)}',
      _ => move.label,
    };
    _restack(
        id,
        label,
        columns,
        (c) => switch (move) {
              StackMove.lift => lift(c, z: frontZ(_floatingZs)),
              StackMove.ground => ground(c),
              StackMove.front => withZ(c, frontZ(_floatingZs)),
              StackMove.back => withZ(c, backZ(_floatingZs)),
              StackMove.forward => withZ(c, stepZ(zOf(c), _floatingZs, 1)),
              StackMove.backward => withZ(c, stepZ(zOf(c), _floatingZs, -1)),
            });
  }

  /// The heights currently in use, for the stacking controls.
  Iterable<int> get _floatingZs => [
        for (final i in _draftItems ?? const <GridItem>[])
          if (i.floating) i.z
      ];

  /// A copy of a card, placed directly under the original.
  ///
  /// Under rather than beside: a card is often as wide as the space it had, so
  /// there is rarely room next to it, and a duplicate that lands at first fit
  /// appears somewhere you are not looking.
  /// Put what is in hand on the system clipboard.
  ///
  /// The whole selection as one payload, not a card at a time: two cards copied
  /// side by side have to arrive side by side, and that only works if their
  /// arrangement travels with them — see `clipboard.dart`.
  Future<bool> _copySelection() async {
    final text = encodeCards(
      ids: _selection,
      widgets: _draftWidgets ?? const {},
      items: _draftItems ?? const [],
      paths: _paths,
      composed: _draftLayouts
              ?.where((l) => l.breakpoint == _editingBreakpoint)
              .firstOrNull
              ?.isComposed ??
          false,
    );
    if (text == null) return false;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return true;
    final n = _selection.length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(n == 1 ? 'Card copied' : '$n cards copied'),
    ));
    return true;
  }

  /// Land whatever is on the clipboard on this page.
  ///
  /// Live even with nothing selected — pasting is how a card gets *onto* a
  /// page, so requiring a selection first would be requiring the thing you are
  /// trying to create.
  ///
  /// Silent when the clipboard holds something that is not ours. A person
  /// pressing ⌘V having copied a URL has not made a mistake worth a message,
  /// and a page that announced every foreign clipboard would be shouting at
  /// ordinary use.
  Future<void> _paste(int columns, bool composedTarget) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final cards = decodeCards(data?.text);
    if (cards == null || !mounted) return;
    if (_draftItems == null || _draftWidgets == null) return;

    // Below everything already on the page. Pasting on top of the existing
    // arrangement would hide what you have and what you just added at the same
    // time; the engine then packs it up into whatever room there is.
    var below = 0;
    for (final i in _draftItems!) {
      if (i.bottom > below) below = i.bottom;
    }
    final stamped = DateTime.now().microsecondsSinceEpoch;
    final pasted = pasteInto(
      cards: cards,
      columns: columns,
      atX: 0,
      atY: below,
      stamp: (i) => 'widget_${stamped}_$i',
      composedTarget: composedTarget,
      taken: _paths.values.whereType<String>().toSet(),
    );

    _pushUndo('Paste');
    setState(() {
      _draftWidgets = {...?_draftWidgets, ...pasted.widgets};
      var next = _draftItems!;
      for (final item in pasted.items) {
        next = _engine(columns).addAt(next, item, item.x, item.y);
      }
      _commit(next);
      _contentDirty = true;
      _selection
        ..clear()
        ..addAll(pasted.widgets.keys);
    });
    if (!mounted) return;
    final n = pasted.items.length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(n == 1 ? 'Card pasted' : '$n cards pasted'),
    ));
  }

  void _duplicateCard(DashboardWidgetModel model, GridItem item, int columns) {
    final copy = model.copyWith(
      id: 'widget_${DateTime.now().microsecondsSinceEpoch}',
    );
    setState(() {
      _draftWidgets = {...?_draftWidgets, copy.id: copy};
      _commit(_engine(columns).addAt(
        _draftItems!,
        GridItem(
          id: copy.id,
          x: item.x,
          y: item.bottom,
          w: item.w,
          h: item.h,
          minW: item.minW,
          minH: item.minH,
        ),
        item.x,
        item.bottom,
      ));
      _selection
        ..clear()
        ..add(copy.id);
    });
  }

  // `_restoreWidget` lived here: it put one removed card back, for the
  // snackbar's Undo action. The undo stack restores the whole draft instead, so
  // a removal is no longer a special case with its own inverse — which is the
  // point of having a stack at all.

  /// Puts a card the library produced on the page.
  ///
  /// Shares everything below the palette with [_addWidget] — the size hint, the
  /// engine placement, the pending-placement bookkeeping — because a card is a
  /// card however it was chosen.
  void _placeCard(DashboardWidgetModel created, int columns,
      {int? atX, int? atY}) {
    final engine = _engine(columns);
    final hint =
        WidgetRegistry.lookup(created.type)?.sizeHint ?? const WidgetSizeHint();
    final x = atX == null
        ? 0
        : atX.clamp(0, (columns - hint.recommendedW).clamp(0, columns));
    final item = GridItem(
      id: created.id,
      x: x,
      y: atY ?? 0,
      w: hint.recommendedW,
      h: hint.recommendedH,
      minW: hint.minW,
      minH: hint.minH,
    );
    setState(() {
      _draftWidgets = {...?_draftWidgets, created.id: created};
      _pendingPlacement.add(created.id);
      _commit(atX == null
          ? engine.add(_draftItems!, item)
          : engine.addAt(_draftItems!, item, atX, atY ?? 0));
      // Select what was just placed: the next thing anyone does to a new card
      // is look at it, and the inspector is where that happens.
      _selection
        ..clear()
        ..add(created.id);
    });
  }

  /// Draws the element the held tool makes, at the rectangle just dragged.
  ///
  /// **The size is the drag, not the size hint.** That is the whole point of
  /// the gesture: with a catalogue you choose a thing and then correct where it
  /// went and how big it is, and with a tool the element arrives finished. A
  /// drawn element that then snapped to its recommended size would be a
  /// catalogue wearing a tool's clothes.
  ///
  /// Returns to Select afterwards, the way a drawing application does: one
  /// shape per press of the tool. Drawing five rectangles in a row is rarer
  /// than drawing one and immediately wanting to move it, and the tool that
  /// stays down is the one that has you making shapes by accident.
  Future<void> _drawWith(
    DesignTool tool,
    Offset from,
    Offset to,
    CanvasGeometry geometry,
    double lineHeight,
  ) async {
    final drawing = toolDrawing(tool, from, to, lineHeight: lineHeight);

    // The catalogue tools have to ask before they can make anything — what a
    // device grid *shows* is the choice, and no drag can express it. The
    // rectangle is not wasted: it becomes the card's placement, so choosing
    // from a list still lands where you drew.
    if (tool.picks) {
      final created = await showWidgetPalette(context);
      if (created == null || !mounted) return;
      _placeDrawn(created, drawing.rect, geometry);
      setState(() => _tool = DesignTool.select);
      return;
    }
    final type = tool.type;
    if (type == null) return;
    final descriptor = WidgetRegistry.lookup(type);
    if (descriptor == null) return;

    _placeDrawn(
      DashboardWidgetModel(
        // The same id shape the library and the palette make. There is no
        // registry of ids to collide with — the document is the only place one
        // lives — and two elements cannot be created in the same microsecond by
        // one pair of hands.
        id: 'widget_${DateTime.now().microsecondsSinceEpoch}',
        type: type,
        title: descriptor.title,
        refreshPolicy: DashboardRefreshPolicy.live,
        config: {...drawing.config},
      ),
      drawing.rect,
      geometry,
    );
    setState(() => _tool = DesignTool.select);
  }

  /// A click with a tool in hand.
  ///
  /// A click is a drag of no length, and a tool that made nothing from one
  /// would read as broken — so the drawing tools make their element at the
  /// floor size the tool itself declares, and the catalogue opens as it always
  /// has.
  void _clickWith(
    DesignTool tool,
    Offset at,
    int columns,
    CanvasGeometry geometry,
    double lineHeight,
  ) {
    if (!tool.draws || tool.picks) {
      final x = (at.dx / geometry.stepX).floor().clamp(0, columns - 1);
      final y = (at.dy / geometry.stepY).floor();
      _addWidget(columns, atX: x, atY: y < 0 ? 0 : y);
      return;
    }
    _drawWith(tool, at, at, geometry, lineHeight);
  }

  /// Puts [created] on the page at exactly [rect], in canvas pixels.
  ///
  /// **Composed and floating, both deliberately.** Composed, because the
  /// rectangle is the truth and the cells beside it are only the approximation
  /// core validates — that is what lets a rule be three pixels tall instead of
  /// a whole row. Floating, because gravity in a packed layout would pull the
  /// element straight up to the top of the page the moment it landed, and an
  /// element that jumps out of your hand as you let go of it is not something
  /// anybody can design with.
  void _placeDrawn(
    DashboardWidgetModel created,
    DashboardRect rect,
    CanvasGeometry geometry,
  ) {
    final descriptor = WidgetRegistry.lookup(created.type);
    final title = (descriptor?.title ?? 'element').toLowerCase();
    // The cells, kept in step with the rectangle by the one function that does
    // that — and guaranteed legal for core, which validates the cells and knows
    // nothing about rectangles.
    final snapped =
        geometry.snapToCells(created.id, rect, floating: true, z: 1);
    final item = GridItem(
      id: created.id,
      x: snapped.x,
      y: snapped.y,
      w: snapped.w,
      h: snapped.h,
      minW: descriptor?.sizeHint.minW ?? 1,
      minH: descriptor?.sizeHint.minH ?? 1,
      floating: true,
      z: 1,
      rect: rect,
    );
    _pushUndo('Draw $title');
    setState(() {
      // The lift is on the element, not on the placement — see
      // `free_layer.dart`. Writing it here keeps a drawn element floating at
      // every breakpoint, which is what "I put this here" means.
      _draftWidgets = {
        ...?_draftWidgets,
        created.id: created.copyWith(config: lift(created.config)),
      };
      _pendingPlacement.add(created.id);
      _commit([...?_draftItems, item]);
      // Select what was just drawn: the next thing anyone does to a new
      // element is give it words or a colour, and that is the inspector.
      _selection
        ..clear()
        ..add(created.id);
    });
  }

  /// Applies a config edit to the draft as it is made.
  ///
  /// No commit step: the page's own Cancel and Done already govern the draft,
  /// and the card is visible while you edit it.
  void _configureLive(String id, Map<String, dynamic> config) {
    final model = _draftWidgets?[id];
    if (model == null) return;
    _pushUndo('Change ${_cardLabel(model)}', coalesce: 'config:$id');
    setState(() {
      _draftWidgets = {...?_draftWidgets, id: model.copyWith(config: config)};
      _contentDirty = true;
    });
  }

  /// Point one unwired reference at a device.
  ///
  /// Its own entry in the undo stack, and NOT coalesced with the others:
  /// wiring twelve slots is twelve decisions, and one undo that unwired all of
  /// them would be the worst possible answer to a mis-click on the twelfth.
  void _wire(String widgetId, String field, String deviceId) {
    final model = _draftWidgets?[widgetId];
    if (model == null) return;
    _pushUndo('Wire ${_cardLabel(model)}');
    setState(() {
      _draftWidgets = {
        ...?_draftWidgets,
        widgetId: model.copyWith(config: wire(model.config, field, deviceId)),
      };
      _contentDirty = true;
    });
  }

  /// Start this page from one somebody already composed.
  ///
  /// The template's own widgets and layouts land here rather than becoming a
  /// separate dashboard, because this IS the new page — you asked for one and
  /// then said what shape it should be. Its references are slots, so the
  /// wiring panel opens with a list of what to point them at.
  Future<void> _startFromTemplate(String templateId) async {
    final template =
        await ref.read(dashboardsProvider.notifier).fetchTemplate(templateId);
    if (template == null || !mounted) return;
    _pushUndo('Start from ${template.name}');
    setState(() {
      _draftWidgets = {for (final w in template.widgets) w.id: w};
      // A template composes for the breakpoints it was drawn at, and this page
      // may show one it never heard of. Keep what it drew and derive the rest
      // from its widest, which is what a page does for its own breakpoints
      // anyway — a wall that inherited nothing would be blank.
      final drawn = {for (final l in template.layouts) l.breakpoint};
      final widest = template.layouts.isEmpty
          ? null
          : template.layouts.reduce((a, b) => a.columns >= b.columns ? a : b);
      _draftLayouts = [
        ...template.layouts,
        if (widest != null)
          for (final breakpoint in DashboardBreakpoint.values)
            if (!drawn.contains(breakpoint))
              widest.copyWith(
                breakpoint: breakpoint,
                derivedFrom: widest.breakpoint,
              ),
      ];
      _contentDirty = true;
    });
  }

  Future<void> _configureWidget(String id) async {
    final model = _draftWidgets?[id];
    if (model == null) return;
    final descriptor = WidgetRegistry.lookup(model.type);
    if (descriptor == null || descriptor.configFields.isEmpty) return;
    final edited = await showWidgetConfig(
      context,
      descriptor: descriptor,
      initial: model.config,
    );
    if (edited == null || !mounted) return;
    setState(() {
      _draftWidgets = {...?_draftWidgets, id: model.copyWith(config: edited)};
    });
  }

  /// One line saying what saving will do besides write the layout on screen.
  ///
  /// Read off the *draft*, not the saved document, so it keeps up with a
  /// session that has already taken a layout over or handed one back.
  String? _editConsequence(DashboardBreakpoint edited) {
    final layouts = _draftLayouts ?? const [];
    final followers = layouts
        .where((l) => l.derivedFrom == edited && l.breakpoint != edited)
        .map((l) => breakpointLabel(l.breakpoint).toLowerCase())
        .toList();
    final derivedFrom =
        layouts.where((l) => l.breakpoint == edited).firstOrNull?.derivedFrom;

    if (derivedFrom != null) {
      return _touched.contains(edited)
          ? 'No longer follows ${breakpointLabel(derivedFrom).toLowerCase()}'
          : 'Follows ${breakpointLabel(derivedFrom).toLowerCase()} — '
              'editing stops that';
    }
    if (followers.isEmpty) return null;
    return '${followers.join(', ')} follow${followers.length == 1 ? 's' : ''} it';
  }

  /// Drops the whole draft in one place. Leaving `_editingBreakpoint` set after
  /// a save would aim the *next* edit at the breakpoint the last one used.
  void _exitEditing() {
    setState(() {
      _draftLayouts = null;
      _draftItems = null;
      _draftWidgets = null;
      _selection.clear();
      _editingBreakpoint = null;
      _touched.clear();
      _contentDirty = false;
      _pendingPlacement.clear();
      _settled.clear();
    });
  }

  static String _cardLabel(DashboardWidgetModel w) => w.title.isNotEmpty
      ? w.title
      : (WidgetRegistry.lookup(w.type)?.title ?? w.type);

  Future<void> _save(DashboardDefinition d) async {
    // Keep only widgets placed on at least one layout. Core rejects a
    // placement naming a widget that does not exist; it does NOT require every
    // widget to appear on every layout — an earlier comment here claimed both
    // and only the first half is true, which is what made leaving a card off
    // one breakpoint look impossible. Gathered across the draft layouts rather
    // than the on-screen arrangement: after switching breakpoints the screen
    // shows one layout and the document carries four.
    final placed = {
      for (final l in _draftLayouts!)
        for (final p in l.placements) p.widgetId,
    };
    final widgets = [
      for (final entry in _draftWidgets!.entries)
        if (placed.contains(entry.key)) entry.value,
    ];
    // Every card's own validator, the same check core runs.
    //
    // The config sheet used to run this on its Done, which is what kept a bad
    // card from ever reaching the save. Moving options into the inspector took
    // that Done away and, with it, the guard — so a card left half-configured
    // (mode Area with no area picked) would have gone to core, which rejects
    // the WHOLE dashboard on the first invalid widget and loses every other
    // edit in the draft. Named per card, because "invalid" without a card name
    // is unactionable on a page of eight.
    for (final w in widgets) {
      final message = WidgetRegistry.lookup(w.type)?.validate?.call(w.config);
      if (message != null) {
        _select(w.id);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${_cardLabel(w)}: $message')));
        return;
      }
    }

    setState(() => _saving = true);
    try {
      // No rebuild here: every gesture already reprojected the draft through
      // writeArrangement, so this is a push of what the bar has been showing.
      // Containers whose group no longer exists, dropped on the way out.
      //
      // Core accepts them — it has to, because it cannot tell an emptied group
      // from a mistyped one, and rejecting the first would make deleting the
      // last card in a group fail to save. So the collecting is the client's
      // job, and here is the moment it can be done without guessing: the
      // widgets being written are exactly the membership.
      final live = livePaths(widgets.map((w) => groupOf(w.config)));
      final layouts = [
        for (final l in _draftLayouts!)
          l.groups.isEmpty ? l : l.copyWith(groups: prunedBoxes(l.groups, live))
      ];
      final next = d.copyWith(
        widgets: widgets,
        layouts: layouts,
        background: _draftBackground,
        updatedAt: DateTime.now(),
      );
      await ref.read(dashboardsProvider.notifier).updateDashboard(next);
      if (mounted) _exitEditing();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The room the page is about, put where everything under it can read it.
    // Overridden here rather than passed down: the config that mentions `@room`
    // is resolved at the placement seam, several widgets deep, and a parameter
    // threaded through all of them is a parameter somebody eventually forgets.
    final body = _build(context);
    return widget.room == null || widget.room!.isEmpty
        ? body
        : ProviderScope(
            overrides: [pageRoomProvider.overrideWithValue(widget.room)],
            child: body,
          );
  }

  Widget _build(BuildContext context) {
    final t = HcTokens.of(context);
    final async = ref.watch(dashboardsProvider);
    // A page that cannot load must SAY so. `async.value == null` used to cover
    // both "still arriving" and "the request failed", and the second one drew
    // the first one's spinner — forever, with no message and nothing to press.
    // A page that never resolves and never explains itself is indistinguishable
    // from a hung app, which is exactly how the cold-load router deadlock read
    // for three days.
    if (async.hasError && async.value == null) {
      return Scaffold(
        backgroundColor: t.surface.base,
        body: _PageLoadFailed(
          error: async.error!,
          onRetry: () => ref.invalidate(dashboardsProvider),
        ),
      );
    }
    // Still arriving is not the same as not there. "Page not found." while the
    // list loads is a claim about the house that is false — the same failure as
    // a card announcing "No devices match" before any device has arrived — and
    // on a slow link it is the first thing the designer says to you.
    if (async.value == null) {
      return Scaffold(
        backgroundColor: t.surface.base,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final dashboards = async.value!;
    final dashboard = dashboards
        .where((d) => d.id == widget.dashboardId)
        .cast<DashboardDefinition?>()
        .firstOrNull;

    if (dashboard == null) {
      return Scaffold(
        body: Center(
          child: Text('Page not found.',
              style: TextStyle(color: t.surface.onBaseMuted)),
        ),
      );
    }

    // The shell, not the viewport, decides which layout this is — brief
    // principle 4. `/wall/...` gets the wall layout at any width.
    final shell = shellFor(GoRouterState.of(context).matchedLocation);

    return LayoutBuilder(
      builder: (context, constraints) {
        // While editing, the breakpoint is pinned to the one editing started
        // on: a window resize mid-drag must not retarget the save at a
        // different layout.
        final breakpoint = _editingBreakpoint ??
            resolveDashboardBreakpoint(
              shell: shell,
              width: constraints.maxWidth,
            );

        // While editing, geometry comes from the draft: the bar can move to a
        // breakpoint with a different column count, and reading the saved
        // document would draw the new arrangement on the old grid.
        // The designer has no view mode to enter from: arriving IS starting.
        if (widget.designer && !_editing) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_editing) _startEditing(dashboard, breakpoint);
          });
        }

        final layout = _draftLayouts
                ?.where((l) => l.breakpoint == breakpoint)
                .firstOrNull ??
            _layoutFor(dashboard, breakpoint);
        final columns = layout.columns <= 0 ? _defaultColumns : layout.columns;

        // Room for the canvas AND a 320px panel beside it. Below this the
        // sheet is still the only thing that fits, and the phone keeps the
        // editing it already had — the brief is explicit that the seated
        // session must not cost the other two.
        final hasInspector = constraints.maxWidth >= 1100;
        final rowHeight =
            layout.rowHeight <= 0 ? _defaultRowHeight : layout.rowHeight;
        final gap = layout.gap;

        final items = _draftItems ?? _itemsFrom(dashboard, layout);
        final widgetsById =
            _draftWidgets ?? {for (final w in dashboard.widgets) w.id: w};

        // Desktop is the layout the others may follow. If the page has none,
        // nothing can follow anything and the bar offers no revert.
        final source = _draftLayouts
                ?.where((l) => l.breakpoint == DashboardBreakpoint.desktop)
                .firstOrNull
                ?.breakpoint ??
            DashboardBreakpoint.desktop;
        final canRevert = _editing &&
            breakpoint != source &&
            (_draftLayouts ?? const []).any((l) => l.breakpoint == source) &&
            layout.derivedFrom == null;

        // What an empty page offers instead of a board. Hidden the moment the
        // page has something on it *or* a canvas under it — a wall start puts
        // nothing on the page, so counting cards alone would leave the offer
        // covering the canvas it had just made.
        Widget? emptyStart() => items.isEmpty &&
                widget.designer &&
                layout.frame == null &&
                !_dismissedStart
            ? EmptyPageStarts(
                editing: true,
                rooms: roomsBySize(
                  ref
                          .watch(devicesProvider)
                          .asData
                          ?.value
                          // The same filter the card itself applies, so the
                          // count promises what the card delivers — see
                          // `selectDevicesForConfig`.
                          .where((d) => !d.isSystem && d.deviceType != 'scene')
                          .map((d) => d.effectiveArea) ??
                      const [],
                  name: humanize,
                ),
                onStart: (kind, {String? room, String? label}) =>
                    _startPage(kind, breakpoint, columns, room, label),
                onTemplate: _startFromTemplate,
              )
            : null;

        // The units a drawn element lands in. The same geometry the composed
        // drags use, so a rectangle drawn and a rectangle dragged mean the same
        // thing.
        final geometry = _geometry(columns);
        // One line of the type a new text element starts at, so a text box is
        // as tall as its words rather than as tall as a grid row. Read from the
        // skin here because the skin is what scales the ramp — a number in
        // `design_tools.dart` would be a second type system.
        final lineHeight = t.text.titleStyle.fontSize! * t.text.title.height;

        // The canvas, shared by both presentations. In the designer it is the
        // middle pane; in the page it is the whole body.
        Widget canvas() => items.isEmpty && !_editing
            ? const EmptyPageStarts(editing: false)
            // An empty page in the designer offers somewhere to start rather
            // than a grid of nothing — see `page_starts.dart`. Only while
            // genuinely empty: once there is one card on it, the page is the
            // page and the starting points would be in the way.
            : _PreviewFrame(
                width: _editing ? previewWidthFor(breakpoint) : null,
                // What a composed page is *drawn at* when somebody is only
                // looking at it. See [_PreviewFrame].
                canvasWidth: _editing ? null : layout.frame?.width,
                child: PageGrid(
                  // A card with a style variant asks about a device by id, so
                  // this is a map rather than a scan: a page of forty cards
                  // each asking about one device would otherwise walk the whole
                  // house forty times on every rebuild.
                  deviceLookup: () {
                    final byId = {
                      for (final d in ref.watch(devicesProvider).value ??
                          const <DeviceState>[])
                        d.id: d,
                    };
                    return (id) => byId[id];
                  }(),
                  items: items,
                  widgetsById: widgetsById,
                  columns: columns,
                  rowHeight: rowHeight,
                  gap: gap,
                  editing: _editing,
                  ghostItems: _editing && _draftLayouts != null
                      ? _ghostFor(breakpoint, source, _draftLayouts!)
                      : const [],
                  onMove: (id, x, y) => _apply(
                      (e, its) => e.move(its, id, x, y), columns,
                      byHand: true),
                  onResize: (id, w, h) => _apply(
                      (e, its) => e.resize(its, id, w, h), columns,
                      byHand: true),
                  onRemove: (id) => _removeWidget(id, columns),
                  onConfigure: (id) => hasInspector || widget.designer
                      ? _select(id)
                      : _configureWidget(id),
                  // A card that edits itself in place — the floor plan placing
                  // a marker. Straight into the same writer the inspector
                  // uses, so it lands in the draft and coalesces into one undo
                  // entry per gesture rather than one per pixel.
                  onWidgetConfig: _configureLive,
                  // A click, with whatever is in hand. A drawing tool makes its
                  // element at its own recommended size — a click is a drag of
                  // no length, and refusing to make anything would read as the
                  // tool being broken. The catalogue tools still ask.
                  onAddAt: (at) =>
                      _clickWith(_tool, at, columns, geometry, lineHeight),
                  // The band draws when a tool is held and selects when it is
                  // not — one gesture, and what it means is what you picked.
                  onDraw: !_tool.draws
                      ? null
                      : (from, to) =>
                          _drawWith(_tool, from, to, geometry, lineHeight),
                  onMarquee: (x1, y1, x2, y2, additive) => setState(() {
                    final caught = _engine(columns)
                        .itemsIn(_draftItems ?? const [], x1, y1, x2, y2);
                    // Shift keeps what you had; a plain band starts again, the
                    // same rule a click follows.
                    if (!additive) _selection.clear();
                    // Clipping one member of a group catches the group, the
                    // same rule a click follows — a band that took three of a
                    // cluster's four cards would then move three of them.
                    final paths = _paths;
                    for (final id in caught) {
                      _selection.addAll(_clickHolds(id, paths));
                    }
                  }),
                  onMenu: (id, at) => _cardMenu(id, at, columns),
                  onSelect: hasInspector || widget.designer
                      ? (id, additive) => _select(id, additive: additive)
                      : null,
                  onEnterGroup: widget.designer ? _enterGroup : null,
                  groupOutline: widget.designer ? _groupOutline : null,
                  // Not gated on `designer`, unlike the outline above: a
                  // container is part of the page. The dashed frame says "this
                  // is what you have hold of" and belongs to the tool; a
                  // background belongs to the document and has to be there when
                  // somebody is only looking at it.
                  groupStyles: layout.groups,
                  groupPaths: _pathsIn(widgetsById),
                  frame: layout.frame,
                  onCompose: (id, rect) => _composeCard(id, rect, columns),
                  onFrameMove: widget.designer ? _setFrameRect : null,
                  snapToGrid: _snapToGrid,
                  // Which magnet the drags use, and whether the fine grid is
                  // drawn. A packed card can only sit on a cell edge; a
                  // composed one can sit anywhere, so the cell is the wrong
                  // thing to pull it to.
                  composing: _draftLayouts
                          ?.where((l) => l.breakpoint == breakpoint)
                          .firstOrNull
                          ?.isComposed ??
                      false,
                  selectedIds: _selection,
                  onDropCard: (payload, x, y) {
                    if (payload is DashboardWidgetModel) {
                      _placeCard(payload, columns, atX: x, atY: y);
                    }
                  },
                ),
              );

        if (widget.designer) {
          return DesignerShell(
            // The draft's background, so the canvas shows what you are typing
            // rather than what was last saved.
            dashboard: _draftBackground == null
                ? dashboard
                : dashboard.copyWith(background: _draftBackground),
            breakpoint: breakpoint,
            layouts: _draftLayouts,
            source: source,
            columns: columns,
            saving: _saving,
            dirty: _touched.isNotEmpty || _contentDirty,
            selectedCount: _selection.length,
            selectedIds: _selection,
            selected: _draftWidgets?[_selectedCard],
            selectedItem: items
                .where((i) => i.id == _selectedCard)
                .cast<GridItem?>()
                .firstOrNull,
            consequence: _editConsequence(breakpoint),
            tool: _tool,
            onTool: (t) => setState(() => _tool = t),
            onSelectBreakpoint: _selectBreakpoint,
            onRevert: canRevert ? () => _revertSelected(source) : null,
            onPick: (created) => _placeCard(created, columns),
            onChanged: (config) => _configureLive(_selectedCard!, config),
            onRemoveSelected: () {
              // Everything in hand, not just the one the inspector was showing.
              for (final id in _selection.toList()) {
                _removeWidget(id, columns);
              }
              _select(null);
            },
            // Escape steps out of a group before it lets go of anything: the
            // way out of something you went into is the first thing it should
            // mean, and letting go as well would cost you the selection you
            // stepped out to work on.
            onDeselect: () {
              if (_leaveGroup()) return;
              _select(null);
            },
            // The tree selects a whole group in one click, which no per-card
            // callback can express.
            onSelectMany: (ids) => setState(() {
              _selection
                ..clear()
                ..addAll(ids);
            }),
            onEnterGroupId: _enterGroup,
            groupInHand: _groupInHand,
            inside: _inside,
            onGroup: _selection.isEmpty ? null : _groupSelection,
            onUngroup: _groupInHand == null ? null : _ungroupSelection,
            onRenameGroup: _groupInHand == null ? null : _renameGroup,
            onEnterGroup: _groupInHand == null
                ? null
                : () => _enterGroup(_selection.first),
            groupBox: _groupInHand == null
                ? null
                : layout.groupBox(_groupInHand!)?.isPlain ?? true
                    ? null
                    : layout.groupBox(_groupInHand!),
            insideFrame: _frameAround(_selectedCard),
            onGroupBox: _groupInHand == null ? null : _setGroupBox,
            // Only on a composed layout. A packed one positions by cells,
            // and a cell is not measured from anything — offering to frame a
            // group there would be a switch that could not do what it says.
            onGroupFrame: _groupInHand == null || !_composedHere
                ? null
                : (on) => _setGroupFrame(_groupInHand!, on),
            onSave: () => _save(dashboard),
            canvas: canvas(),
            emptyStart: emptyStart(),
            // The frame *is* the canvas when there is one: composing at the
            // size you designed for keeps a rectangle's units and the board's
            // pixels the same thing, so nothing has to be converted on the way
            // to the screen.
            canvasWidth: layout.frame?.width ?? previewWidthFor(breakpoint),
            cardCount: items.length,
            items: items,
            widgetsById: widgetsById,
            // Directly: the strip is where you address one element, whatever
            // group it is in. On the canvas a click holds the cluster.
            onSelectCard: (id) => _select(id, direct: true),
            onRename: (name) => setState(() {
              final id = _selectedCard;
              final current = _draftWidgets?[id];
              if (id == null || current == null) return;
              _pushUndo('Rename ${_cardLabel(current)}', coalesce: 'name:$id');
              _draftWidgets = {
                ..._draftWidgets!,
                id: current.copyWith(title: name),
              };
              _contentDirty = true;
            }),
            // Align moves the selection through the same engine call a drag
            // does, so it pushes neighbours out of the way and settles exactly
            // as dragging there would — an alignment that used a private path
            // could land a card somewhere a drag could never put it.
            onAlign: (align) {
              if (_selection.isEmpty) return;
              // Every selected card, through the same engine call a drag makes
              // — so aligning three cards settles exactly as dragging each of
              // them there would.
              _apply(
                  (e, its) => _selection.fold(
                        its,
                        (acc, id) {
                          final item = acc.where((i) => i.id == id).firstOrNull;
                          return item == null
                              ? acc
                              : e.move(
                                  acc, id, align.xFor(item.w, columns), item.y);
                        },
                      ),
                  columns,
                  byHand: true,
                  label: align.label);
            },
            onNudge: (dx, dy) => _apply(
                (e, its) => e.nudge(its, _selection, dx, dy), columns,
                byHand: true, label: 'Nudge'),
            onDuplicate: _selection.isEmpty
                ? null
                : () {
                    // Every selected card, each landing under its own original
                    // — the same rule one card follows, applied to a crowd.
                    for (final id in _selection.toList()) {
                      final model = _draftWidgets?[id];
                      final item =
                          _draftItems?.where((i) => i.id == id).firstOrNull;
                      if (model != null && item != null) {
                        _duplicateCard(model, item, columns);
                      }
                    }
                  },
            onCopy: _selection.isEmpty ? null : _copySelection,
            onPaste: () => _paste(columns, layout.isComposed),
            onSelectAll: () => setState(() {
              _selection
                ..clear()
                ..addAll(items.map((i) => i.id));
            }),
            onDistribute: (horizontal) => _apply(
                (e, its) =>
                    e.distribute(its, _selection, horizontal: horizontal),
                columns,
                byHand: true,
                label: horizontal ? 'Spread across' : 'Spread down'),
            onStack: _selectedCard == null
                ? null
                : (move) => _stack(_selectedCard!, move, columns),
            onWire: _wire,
            onRect: _selectedCard == null
                ? null
                : (rect) => _reposition(_selectedCard!, rect),
            onRotate: _selectedCard == null
                ? null
                : (degrees) => _rotate(_selectedCard!, degrees),
            onFade: _selectedCard == null
                ? null
                : (opacity) => _fade(_selectedCard!, opacity),
            onBackgroundChanged: (next) {
              _pushUndo('Change the background', coalesce: 'background');
              setState(() {
                _draftBackground = next;
                _contentDirty = true;
              });
            },
            canRedo: _redo.isNotEmpty,
            redoLabel: _redo.isEmpty ? null : _redo.last.label,
            onRedo: _redoNext,
            history: _historyEntries,
            historyAt: _historyAt,
            onJumpHistory: _jumpHistory,
            canUndo: _undo.isNotEmpty,
            undoLabel: _undo.isEmpty ? null : _undo.last.label,
            onUndo: _undoLast,
            onFlowChanged: (next) => setState(() {
              _pushUndo(next == GridFlow.free ? 'Keep gaps' : 'Close gaps');
              _draftLayouts = [
                for (final l in _draftLayouts!)
                  if (l.breakpoint == breakpoint) l.copyWith(flow: next) else l,
              ];
              _touched.add(breakpoint);
            }),
            onComposeChanged: (on) => _setComposed(on, breakpoint, columns),
            onFrameChanged: (frame) => _setFrame(frame, breakpoint),
            snapToGrid: _snapToGrid,
            onSnapChanged: (on) => setState(() => _snapToGrid = on),
          );
        }

        return Scaffold(
          bottomNavigationBar: _editing
              ? _EditBar(
                  saving: _saving,
                  onAdd: () => _addWidget(columns),
                  onCancel: _exitEditing,
                  onSave: () => _save(dashboard),
                )
              : null,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(
                  dashboard: dashboard,
                  editing: _editing,
                  onEdit: () => _startEditing(dashboard, breakpoint),
                  // A second door, not a replacement. The pencil still edits in
                  // place — that is what a phone and a wall panel get, and it
                  // is the only thing that fits there. Changing what the pencil
                  // means on wide viewports would take the in-place editor away
                  // from the desktop without asking.
                  onDesign: hasInspector
                      ? () => context.go('/pages/${dashboard.id}/design')
                      : null,
                ),
                if (_editing && _draftLayouts != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        t.space.lg, 0, t.space.lg, t.space.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BreakpointBar(
                          layouts: _draftLayouts!,
                          selected: breakpoint,
                          source: source,
                          onSelect: _selectBreakpoint,
                          onRevert:
                              canRevert ? () => _revertSelected(source) : null,
                        ),
                        // Under the bar, at full width, because it is a
                        // sentence about the thing directly above it — and
                        // because a save whose side effects are not named is
                        // what this whole area is recovering from.
                        if (_editConsequence(breakpoint) case final line?) ...[
                          SizedBox(height: t.space.xs),
                          Text(
                            line,
                            style: t.text.captionStyle
                                .copyWith(color: t.surface.onBaseMuted),
                          ),
                        ],
                        if (_unplacedHere(breakpoint) case final missing
                            when missing.isNotEmpty) ...[
                          SizedBox(height: t.space.sm),
                          for (final w in missing)
                            _UnplacedNotice(
                              widget_: w,
                              breakpointLabel:
                                  breakpointLabel(breakpoint).toLowerCase(),
                              onPlace: () =>
                                  _placeHere(w.id, breakpoint, columns),
                              onKeepOff: () => _keepOffHere(w.id, breakpoint),
                            ),
                        ],
                      ],
                    ),
                  ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                              t.space.lg, 0, t.space.lg, t.space.xl),
                          // The same canvas the designer uses. Two copies of
                          // this had already drifted — the in-place one had
                          // lost selection, drop-at-cell and the card menu —
                          // which is what a shared builder is for.
                          child: canvas(),
                        ),
                      ),
                      // One rail, and what is in it follows what you are
                      // doing: the card you selected, or everything you could
                      // add if you have not selected one.
                      if (hasInspector && _editing)
                        Padding(
                          padding: EdgeInsets.only(
                              right: t.space.lg, bottom: t.space.xl),
                          child: switch (_draftWidgets?[_selectedCard]) {
                            final sel? => CardInspector(
                                model: sel,
                                onChanged: (config) =>
                                    _configureLive(sel.id, config),
                                onRemove: () {
                                  _removeWidget(sel.id, columns);
                                  _select(null);
                                },
                                onClose: () => _select(null),
                              ),
                            null => CardLibrary(
                                onPick: (created) =>
                                    _placeCard(created, columns),
                              ),
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.dashboard,
    required this.editing,
    required this.onEdit,
    required this.onDesign,
  });

  final DashboardDefinition dashboard;
  final bool editing;
  final VoidCallback onEdit;

  /// Null on anything too narrow for three panes.
  final VoidCallback? onDesign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    return Padding(
      padding:
          EdgeInsets.fromLTRB(t.space.lg, t.space.lg, t.space.lg, t.space.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              // The room, when the page is about one. One room page serving
              // fifteen rooms is called "Room", and a title bar saying that
              // over a page full of the Office's things tells you nothing you
              // could not already see and loses the one fact you wanted.
              switch (ref.watch(pageRoomProvider)) {
                final room? when room.isNotEmpty => prettyGroup(room),
                _ => dashboard.name,
              },
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.text.displayStyle.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: t.surface.onBase),
            ),
          ),
          if (editing)
            // Just the mode. Which layout is being arranged, and what follows
            // it, is the breakpoint bar's job — saying it twice in two places
            // is how the two drift apart.
            Text(
              'Editing',
              style: t.text.bodyStyle.copyWith(color: t.accent.active),
            )
          else ...[
            if (onDesign != null) ...[
              TextButton(onPressed: onDesign, child: const Text('Design')),
              SizedBox(width: t.space.xs),
            ],
            HcIconButton(
              icon: HcIcons.pencil,
              tooltip: 'Edit this page',
              onPressed: onEdit,
            ),
            SizedBox(width: t.space.xs),
            _PageMenu(dashboard: dashboard),
          ],
        ],
      ),
    );
  }
}

/// The per-page actions that are not "edit the layout": rename, duplicate,
/// make-home, delete.
class _PageMenu extends ConsumerWidget {
  const _PageMenu({required this.dashboard});

  final DashboardDefinition dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, color: t.surface.onBaseMuted),
      tooltip: 'Page options',
      onSelected: (v) => onPageAction(context, ref, dashboard, v),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'new', child: Text('New page')),
        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        // Beside Duplicate, which is the thing it is nearly: both copy this
        // page, and the difference is where the copy goes and whether it keeps
        // this house's devices.
        PopupMenuItem(
            value: 'template', child: Text('Save as a starting point')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(value: 'home', child: Text('Set as Home page')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}

class _EditBar extends StatelessWidget {
  const _EditBar({
    required this.saving,
    required this.onAdd,
    required this.onCancel,
    required this.onSave,
  });

  final bool saving;
  final VoidCallback onAdd;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding:
          EdgeInsets.fromLTRB(t.space.lg, t.space.sm, t.space.lg, t.space.sm),
      decoration: BoxDecoration(
        color: t.surface.raised,
        border: Border(top: BorderSide(color: t.stroke.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Flexible, not fixed: at phone width the three actions plus the
            // rail padding overflow the bar, and the label is the only part
            // that can give. Found by the first widget test to pump this screen
            // narrow — the bar has always been able to overflow, but /pages
            // never resolved to mobile before, so nothing ever rendered it there.
            Flexible(
              child: OutlinedButton.icon(
                onPressed: saving ? null : onAdd,
                icon: const Icon(HcIcons.plus, size: 15),
                label: const Text(
                  'Add widget',
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ),
            const Spacer(),
            TextButton(
                onPressed: saving ? null : onCancel,
                child: const Text('Cancel')),
            SizedBox(width: t.space.xs),
            FilledButton(
              onPressed: saving ? null : onSave,
              child: saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "This card is not on this layout" — with both ways out.
///
/// A card added while arranging one breakpoint does not force itself into a
/// layout someone arranged by hand; that would reflow their work to make room
/// for something they have not seen. So it is said out loud here instead, once
/// per card, and answering makes it stop.
class _UnplacedNotice extends StatelessWidget {
  const _UnplacedNotice({
    required this.widget_,
    required this.breakpointLabel,
    required this.onPlace,
    required this.onKeepOff,
  });

  final DashboardWidgetModel widget_;
  final String breakpointLabel;
  final VoidCallback onPlace;
  final VoidCallback onKeepOff;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: t.space.xs),
      padding:
          EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.xs),
      decoration: BoxDecoration(
        color: t.surface.raised,
        borderRadius: BorderRadius.circular(t.radius.sm),
        border: Border.all(color: t.stroke.hairline, width: t.stroke.width),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: t.space.sm,
        runSpacing: t.space.xs,
        children: [
          Text(
            '${widget_.title} is not on the $breakpointLabel layout',
            style: t.text.bodySmallStyle.copyWith(color: t.surface.onBase),
          ),
          TextButton(
            onPressed: onPlace,
            child: Text('Place it',
                style: t.text.captionStyle.copyWith(color: t.accent.active)),
          ),
          TextButton(
            onPressed: onKeepOff,
            child: Text('Leave it off',
                style:
                    t.text.captionStyle.copyWith(color: t.surface.onBaseMuted)),
          ),
        ],
      ),
    );
  }
}

/// Holds the canvas to a device-plausible width while editing a layout narrower
/// than the screen, and gets out of the way entirely otherwise.
/// How wide the board is laid out, and whether what is drawn is scaled.
///
/// Two jobs that look like one. **Editing** constrains the board to the
/// breakpoint's own width, so a phone layout is composed at phone width. Only
/// the designer does that, and it is a constraint rather than a scale — the
/// shell has its own zoom on top.
///
/// **Viewing a composed page scales it**, and until now did not, which is the
/// bug that made every composed page look broken on any screen that was not
/// exactly the width it was drawn at. A composed layout states its rectangles
/// in the frame's units — 1600 across, say — and `page_grid` lays the board out
/// at whatever width it is given and then draws those rectangles one-for-one.
/// Give it 1375 and the right two hundred pixels of the design are simply off
/// the edge: no error, no scrollbar that helps, just a page with its right-hand
/// side missing.
///
/// [ScaledCanvas] is the answer and already existed — the designer has used it
/// for zoom since composition shipped. The board is laid out at the frame's
/// width and *drawn* smaller, so a rectangle needs no conversion and a page
/// looks the same on every screen.
///
/// **Never scaled up.** A 1200-wide design on a 2560 monitor at 2.1× is a page
/// of enormous controls rather than a page that fits, so past 1:1 it is centred
/// at its own size — which is what a fixed-width design means.
class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({
    required this.width,
    required this.child,
    this.canvasWidth,
  });

  final double? width;
  final double? canvasWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (width != null) {
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width!),
          child: child,
        ),
      );
    }
    final canvas = canvasWidth;
    if (canvas == null || canvas <= 0) return child;
    return LayoutBuilder(
      builder: (context, c) {
        if (!c.hasBoundedWidth || c.maxWidth <= 0) return child;
        final scale = c.maxWidth / canvas;
        if (scale >= 1) {
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: canvas, child: child),
          );
        }
        return ScaledCanvas(scale: scale, child: child);
      },
    );
  }
}

/// The page list did not arrive, so this page cannot be drawn.
///
/// Says which page, says why, and offers the one useful action. The failure it
/// reports is almost never about this page in particular — the list is the
/// whole house's — so it names the page rather than blaming it.
/// A menu row that names its keyboard shortcut.
///
/// The point is teaching, not decoration. A tool whose copy and paste are
/// keyboard-only has them for the people who already guessed; putting the
/// shortcut beside the label is how everyone else finds out it is there — and
/// stops needing the menu.
class _MenuRow extends StatelessWidget {
  const _MenuRow(this.label, this.keys);

  final String label;
  final String keys;

  /// The whole row as a menu entry, since every caller wants exactly this.
  static PopupMenuItem<String> item(String value, String label, String keys) =>
      PopupMenuItem(value: value, child: _MenuRow(label, keys));

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Row(
      children: [
        Expanded(child: Text(label)),
        SizedBox(width: t.space.md),
        Text(
          keys,
          style: t.text.captionStyle.copyWith(color: t.surface.onBaseMuted),
        ),
      ],
    );
  }
}

class _PageLoadFailed extends StatelessWidget {
  const _PageLoadFailed({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HcIcons.warning, color: t.accent.danger, size: 32),
            SizedBox(height: t.space.md),
            Text('This page could not be loaded.',
                style: t.text.titleStyle.copyWith(color: t.surface.onBase)),
            SizedBox(height: t.space.sm),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: t.text.bodyStyle.copyWith(color: t.surface.onBaseMuted),
            ),
            SizedBox(height: t.space.lg),
            HcButton(label: 'Try again', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

/// The pages somebody already composed: the ones core ships, and the ones
/// imported from another house.
///
/// A template arrives with slots rather than devices — that is what makes it a
/// template rather than a copy of somebody's house — so picking one lands a
/// page with gaps in it, and the wiring panel above the canvas is where you
/// fill them. Said here, because a page of inert controls is a surprise
/// otherwise.
class _Templates extends ConsumerWidget {
  const _Templates({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final templates = ref.watch(dashboardTemplatesProvider);

    return templates.maybeWhen(
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: t.space.lg),
            Row(children: [
              Expanded(
                  child: Divider(
                      height: t.stroke.width, color: t.stroke.hairline)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: t.space.sm),
                child: Text('Or start from a page',
                    style: t.text.captionStyle
                        .copyWith(color: t.surface.onBaseMuted)),
              ),
              Expanded(
                  child: Divider(
                      height: t.stroke.width, color: t.stroke.hairline)),
            ]),
            SizedBox(height: t.space.sm),
            for (final template in list) ...[
              _StartTile(
                icon: Icons.auto_awesome_mosaic_outlined,
                title: template.name,
                blurb: template.description ??
                    'A page somebody composed, ready to wire.',
                trailing: GestureDetector(
                  onTap: () => onPick(template.id),
                  child: const _StartAction(label: 'Use it'),
                ),
              ),
              SizedBox(height: t.space.sm),
            ],
          ],
        );
      },
      // Silent while asking, and silent on an older core that has no
      // templates to give: an error here would be a banner about a feature
      // nobody asked for yet.
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// A page with nothing on it — and, in the designer, somewhere to start.
///
/// "Add a widget to get started" was the whole truth while a page could only
/// ever be a mosaic of cells: there was one shape a template could have, so
/// offering it would have been offering nothing. With a canvas underneath, the
/// choice is real — see `page_starts.dart`.
class EmptyPageStarts extends ConsumerWidget {
  const EmptyPageStarts({
    super.key,
    required this.editing,
    this.rooms = const [],
    this.onStart,
    this.onTemplate,
  });

  final bool editing;

  /// The rooms this house has, busiest first.
  final List<StartRoom> rooms;

  /// Null outside the designer, where there is nowhere to put the result.
  final void Function(PageStartKind kind, {String? room, String? label})?
      onStart;

  /// Start from a page somebody already composed — one core ships, or one
  /// imported from another house.
  final ValueChanged<String>? onTemplate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final onStart = this.onStart;

    if (onStart == null) {
      return Padding(
        padding: EdgeInsets.only(top: t.space.xl * 2),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(HcIcons.dashboards, size: 30, color: t.surface.onBaseMuted),
              SizedBox(height: t.space.md),
              Text(
                editing
                    ? 'Add a widget to get started.'
                    : 'This page is empty. Tap the pencil to add widgets.',
                style: TextStyle(color: t.surface.onBaseMuted),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: t.space.lg, vertical: t.space.xl * 2),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Start this page',
                  textAlign: TextAlign.center,
                  style: t.text.titleStyle.copyWith(color: t.surface.onBase)),
              SizedBox(height: t.space.xs),
              Text(
                'Or add cards from the left and arrange them yourself.',
                textAlign: TextAlign.center,
                style: t.text.captionStyle
                    .copyWith(color: t.surface.onBaseMuted, height: 1.4),
              ),
              SizedBox(height: t.space.lg),
              _StartTile(
                icon: HcIcons.dashboards,
                title: 'A room',
                blurb: rooms.isEmpty
                    ? 'No room on this house has any devices in it yet.'
                    : 'Everything in one room, on one card. It keeps meaning '
                        'the room as the room changes.',
                // A menu rather than a second screen: the choice is one word
                // long and there is nothing else to decide.
                trailing: rooms.isEmpty
                    ? null
                    : PopupMenuButton<String>(
                        tooltip: 'Choose a room',
                        onSelected: (area) => onStart(
                          PageStartKind.room,
                          room: area,
                          label: rooms.firstWhere((r) => r.area == area).label,
                        ),
                        itemBuilder: (context) => [
                          for (final room in rooms)
                            PopupMenuItem(
                              // The area as stored is what selects the
                              // devices; the label is only what you read.
                              value: room.area,
                              height: 34,
                              child: Row(
                                children: [
                                  Expanded(child: Text(room.label)),
                                  SizedBox(width: t.space.sm),
                                  Text('${room.count}',
                                      style: t.text.captionStyle.copyWith(
                                          color: t.surface.onBaseMuted,
                                          fontFeatures: t.numericFontFeatures)),
                                ],
                              ),
                            ),
                        ],
                        child: const _StartAction(label: 'Choose a room'),
                      ),
              ),
              SizedBox(height: t.space.sm),
              _StartTile(
                icon: Icons.tv_outlined,
                title: 'A wall display',
                blurb: 'A 1920×1080 canvas that never scrolls, to compose on. '
                    'Change the size in the panel on the right — nothing moves '
                    'when you do.',
                trailing: GestureDetector(
                  onTap: () => onStart(PageStartKind.wall),
                  child: const _StartAction(label: 'Make one'),
                ),
              ),
              SizedBox(height: t.space.sm),
              _StartTile(
                icon: Icons.grid_on_outlined,
                title: 'Blank',
                blurb: 'The grid, empty. Cards are whole cells and float up to '
                    'close gaps.',
                trailing: GestureDetector(
                  onTap: () => onStart(PageStartKind.blank),
                  child: const _StartAction(label: 'Just the grid'),
                ),
              ),
              // **The pages somebody already composed, in the same list.**
              //
              // They were behind a different button on the dashboards screen,
              // which meant the natural path — New page — could not reach
              // them: John, looking for the room template he had just been
              // told about, found the three starts instead. Two lists of "how
              // do I begin a page" is one too many, and the one you find is
              // the one that gets used.
              //
              // Below the built-in starts rather than above: a start makes
              // something you finish, and a template makes something you
              // WIRE. That is more work, not less, and it should be the
              // deliberate choice of the two.
              if (onTemplate case final onTemplate?)
                _Templates(onPick: onTemplate),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartTile extends StatelessWidget {
  const _StartTile({
    required this.icon,
    required this.title,
    required this.blurb,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String blurb;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        color: t.surface.raised,
        borderRadius: t.radius.mdR,
        border: Border.all(color: t.stroke.hairline, width: t.stroke.width),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: t.surface.onBaseMuted),
          SizedBox(width: t.space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: t.text.bodyStyle.copyWith(
                        color: t.surface.onBase, fontWeight: FontWeight.w600)),
                SizedBox(height: t.space.xs / 2),
                Text(blurb,
                    style: t.text.captionStyle
                        .copyWith(color: t.surface.onBaseMuted, height: 1.4)),
              ],
            ),
          ),
          if (trailing case final action?) ...[
            SizedBox(width: t.space.md),
            action,
          ],
        ],
      ),
    );
  }
}

class _StartAction extends StatelessWidget {
  const _StartAction({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.xs),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.radius.pill),
        border: Border.all(color: t.accent.active, width: t.stroke.width),
      ),
      child: Text(label,
          style: t.text.captionStyle.copyWith(color: t.surface.onBase)),
    );
  }
}
