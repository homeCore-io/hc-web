import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/dashboard/grid_engine.dart';
import '../../core/dashboard/groups.dart';
import '../../core/dashboard/layer_tree.dart';
import '../../core/dashboard/widget_registry.dart';
import '../../core/models/dashboard.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';

/// The page as a list you can aim at.
///
/// **This is the answer to "grouping and selection is too many steps."** The
/// steps were never the grouping — they were the hunting. Selecting four things
/// on a busy canvas is a click and three shift-clicks, each of which has to land
/// on the right few pixels, and any miss hits the background and starts the
/// whole thing over. Here every element is a full-width row that does not move,
/// a group is one row that holds all of it, and a range is a click and a
/// shift-click.
///
/// It reads the same order the page draws in — what floats first, topmost
/// first, then the grid in reading order — because a map that disagrees with
/// the territory is worse than no map. The shape of the tree is
/// `core/dashboard/layer_tree.dart`; this only draws it.
class LayerTreePanel extends StatefulWidget {
  const LayerTreePanel({
    super.key,
    required this.items,
    required this.widgetsById,
    required this.selectedIds,
    required this.onSelect,
    this.onEnterGroup,
  });

  final List<GridItem> items;
  final Map<String, DashboardWidgetModel> widgetsById;
  final Set<String> selectedIds;

  /// Replace the selection with these. One callback for one row and for a
  /// whole group, because from here they are the same gesture.
  final ValueChanged<Set<String>> onSelect;

  /// Step inside a group, so the next canvas click picks one member out.
  final ValueChanged<String>? onEnterGroup;

  @override
  State<LayerTreePanel> createState() => _LayerTreePanelState();
}

class _LayerTreePanelState extends State<LayerTreePanel> {
  final _collapsed = <String>{};

  /// Where a shift-click measures from. Null until something has been clicked,
  /// so the first shift-click behaves like a plain one rather than selecting
  /// from the top of a list nobody pointed at.
  int? _anchor;

  /// The page's own order: what floats, topmost first, then the grid in
  /// reading order. Lifted from the old bottom strip, which had it right.
  List<GridItem> get _ordered {
    final floating = [
      for (final i in widget.items)
        if (i.floating) i
    ]..sort((a, b) => b.z.compareTo(a.z));
    final grounded = [
      for (final i in widget.items)
        if (!i.floating) i
    ]..sort((a, b) => a.y == b.y ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
    return [...floating, ...grounded];
  }

  Map<String, String?> get _paths => {
        for (final i in widget.items)
          i.id: groupOf(widget.widgetsById[i.id]?.config ?? const {}),
      };

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final rows = layerRows(
      order: _ordered,
      widgets: widget.widgetsById,
      collapsed: _collapsed,
      typeName: (type) => WidgetRegistry.lookup(type)?.title ?? type,
    );
    final paths = _paths;

    if (rows.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(t.space.md),
        child: Text(
          'Nothing on this page yet. Add something from the Add tab.',
          style: t.text.captionStyle
              .copyWith(color: t.surface.onBaseMuted, height: 1.4),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: t.space.xs),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        final ids = idsFor(row, paths);
        // A group reads as selected when everything under it is. Anything less
        // is a partial selection, and colouring that the same way would say the
        // group is in hand when a click would change what you have.
        final selected =
            ids.isNotEmpty && ids.every(widget.selectedIds.contains);
        return _Row(
          row: row,
          selected: selected,
          icon: _iconFor(row),
          onTap: () {
            final shift = HardwareKeyboard.instance.isShiftPressed;
            final from = _anchor;
            // A shift-click extends from where the last plain click landed and
            // **leaves the anchor where it is**, so dragging the far end of a
            // range back and forth keeps measuring from the same place. Moving
            // it first — which is what this did at first — collapses every
            // range to the single row just clicked.
            if (shift && from != null) {
              widget.onSelect(rangeBetween(rows, from, i, paths));
              return;
            }
            setState(() => _anchor = i);
            widget.onSelect(ids);
          },
          onToggle: row.isGroup
              ? () => setState(() => _collapsed.contains(row.path!)
                  ? _collapsed.remove(row.path!)
                  : _collapsed.add(row.path!))
              : null,
          collapsed: row.isGroup && _collapsed.contains(row.path),
          onEnter: row.isGroup && widget.onEnterGroup != null
              ? () => widget.onEnterGroup!(ids.first)
              : null,
        );
      },
    );
  }

  /// The element's own kind, so a page of eleven things is scannable without
  /// reading eleven names. Groups get the one glyph the rest of the app uses
  /// for them.
  IconData _iconFor(LayerRow row) {
    if (row.isGroup) return HcIcons.dashboards;
    final type = widget.widgetsById[row.id]?.type;
    return (type == null ? null : WidgetRegistry.lookup(type)?.icon) ??
        HcIcons.dashboards;
  }
}

/// Two clicks close enough together to be one gesture.
const _doubleTapWindow = Duration(milliseconds: 400);

class _Row extends StatefulWidget {
  const _Row({
    required this.row,
    required this.selected,
    required this.icon,
    required this.onTap,
    required this.collapsed,
    this.onToggle,
    this.onEnter,
  });

  final LayerRow row;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onToggle;
  final VoidCallback? onEnter;
  final bool collapsed;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  DateTime? _lastTap;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final row = widget.row;
    final selected = widget.selected;
    final onTap = widget.onTap;
    final onEnter = widget.onEnter;
    final onToggle = widget.onToggle;
    final collapsed = widget.collapsed;
    final icon = widget.icon;
    return InkWell(
      // **Not `onDoubleTap`.** Declaring one makes Flutter hold every single
      // tap for the double-tap timeout before delivering it, so a click on a
      // group row would sit there doing nothing for 300ms while a click on an
      // element row — which has no double-tap — fired at once. Two kinds of row
      // that respond at different speeds is worse than no double-click at all.
      // The canvas already learned this; `page_grid.dart` times it by hand for
      // the same reason.
      onTap: () {
        final now = DateTime.now();
        final again = _lastTap != null &&
            now.difference(_lastTap!) < _doubleTapWindow &&
            onEnter != null;
        _lastTap = now;
        if (again) {
          onEnter();
        } else {
          onTap();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: selected ? t.accent.active.withValues(alpha: 0.13) : null,
          border: Border(
            left: BorderSide(
              color: selected ? t.accent.active : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        padding: EdgeInsets.only(
          left: t.space.xs + row.depth * t.space.md,
          right: t.space.sm,
          top: t.space.xs / 2,
          bottom: t.space.xs / 2,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: onToggle == null
                  ? null
                  : InkWell(
                      onTap: onToggle,
                      child: Icon(
                        collapsed ? HcIcons.caretRight : HcIcons.caretDown,
                        size: 11,
                        color: t.surface.onBaseMuted,
                      ),
                    ),
            ),
            Icon(icon, size: 13, color: t.surface.onBaseMuted),
            SizedBox(width: t.space.xs),
            Expanded(
              child: Text(
                row.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.bodySmallStyle.copyWith(
                  color: selected ? t.surface.onBase : t.surface.onBaseMuted,
                  fontWeight: row.isGroup ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (row.isGroup) ...[
              SizedBox(width: t.space.xs),
              Text(
                '${row.count}',
                style: t.text.captionStyle.copyWith(
                  color: t.surface.onBaseMuted,
                  fontFeatures: t.numericFontFeatures,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
