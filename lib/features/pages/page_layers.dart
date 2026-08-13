import 'package:flutter/material.dart';

import '../../core/dashboard/grid_engine.dart';
import '../../core/dashboard/widget_registry.dart';
import '../../core/models/dashboard.dart';
import '../../design/hc_icons.dart';
import '../../design/tokens.dart';

/// Everything on the page, named, in one strip.
///
/// Phase 5 of `designer-plan.md`. The plan asked for "a list of what is on the
/// page, in z-order, with names — select from it, reorder, rename, hide", and
/// two of those four turn out not to exist in this document:
///
/// **There was no z-order.** The grid resolved overlap out of existence, so no
/// two cards were ever on top of each other and there was nothing to order —
/// reading order, top-left to bottom-right, was the only honest answer.
///
/// The free layer changed that premise (`free_layer.dart`), so this strip now
/// says both things at once: the grid in reading order, then **what floats
/// above it, highest first**, which is the order you see them stacked and the
/// order the stacking controls move them through. Grounded cards keep reading
/// order, because among things that cannot overlap there is still no stack.
///
/// **There is no hidden.** `DashboardWidgetModel` has no such field, and
/// inventing one client-side would make a card that vanishes here and is still
/// on the wall display. Removing a card is already undoable, which is most of
/// what hiding is for.
///
/// **Reordering is nothing.** Widget order is read nowhere: layouts reconcile
/// by id and placement is x/y. A drag handle here would rearrange a list and
/// change no pixel on the page, which is worse than not having one.
///
/// So what is left is what this does: **say what is there, and let you get to
/// it**. That is not a consolation prize. A spacer draws nothing at all, and a
/// divider is a hairline — before this, an element you could not see was an
/// element you could only select by remembering where you put it.
class PageLayers extends StatelessWidget {
  const PageLayers({
    super.key,
    required this.items,
    required this.widgetsById,
    required this.selectedId,
    required this.onSelect,
    required this.open,
    required this.onToggle,
  });

  final List<GridItem> items;
  final Map<String, DashboardWidgetModel> widgetsById;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final bool open;
  final VoidCallback onToggle;

  /// Reading order for the grid: down the page, then across. Not the order the
  /// widgets happen to sit in the document, which is an artefact of the order
  /// they were added and matches nothing you can see.
  List<GridItem> get _grounded {
    final sorted = [
      for (final i in items)
        if (!i.floating) i
    ];
    sorted.sort((a, b) => a.y == b.y ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
    return sorted;
  }

  /// What floats, **topmost first** — the way a layers panel has read since
  /// Photoshop, and the opposite of paint order on purpose: the thing in front
  /// is the thing you are most likely to be reaching for.
  List<GridItem> get _floating {
    final sorted = [
      for (final i in items)
        if (i.floating) i
    ];
    sorted.sort((a, b) => b.z.compareTo(a.z));
    return sorted;
  }

  static String nameOf(DashboardWidgetModel? model) {
    if (model == null) return 'Card';
    if (model.title.trim().isNotEmpty) return model.title;
    return WidgetRegistry.lookup(model.type)?.title ?? model.type;
  }

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final grounded = _grounded;
    final floating = _floating;
    // Floating first, so the strip reads top-of-stack to bottom-of-page in one
    // direction.
    final ordered = [...floating, ...grounded];

    return Container(
      decoration: BoxDecoration(
        color: t.surface.raised,
        border: Border(
            top: BorderSide(color: t.stroke.hairline, width: t.stroke.width)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: t.space.md, vertical: t.space.xs),
              child: Row(
                children: [
                  Icon(open ? HcIcons.caretDown : HcIcons.caretRight,
                      size: 12, color: t.surface.onBaseMuted),
                  SizedBox(width: t.space.xs),
                  Text('On this page',
                      style: t.text.overlineStyle
                          .copyWith(color: t.surface.onBaseMuted)),
                  SizedBox(width: t.space.sm),
                  Text('${ordered.length}',
                      style: t.text.captionStyle.copyWith(
                          color: t.surface.onBaseMuted,
                          fontFeatures: t.numericFontFeatures)),
                ],
              ),
            ),
          ),
          if (open)
            SizedBox(
              // One row of chips, scrolled sideways. A tall list here would
              // take the height off the canvas, which is the thing you are
              // actually working in.
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: t.space.md)
                    .copyWith(bottom: t.space.sm),
                itemCount: ordered.length,
                separatorBuilder: (_, __) => SizedBox(width: t.space.xs),
                itemBuilder: (context, i) {
                  final item = ordered[i];
                  final model = widgetsById[item.id];
                  return _LayerChip(
                    floating: item.floating,
                    label: nameOf(model),
                    icon: WidgetRegistry.lookup(model?.type ?? '')?.icon ??
                        Icons.widgets_outlined,
                    selected: item.id == selectedId,
                    onTap: () => onSelect(item.id),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _LayerChip extends StatelessWidget {
  const _LayerChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.floating = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  /// Above the grid, and therefore able to sit on top of something. Marked
  /// rather than merely ordered: a strip of identical chips in a new order is
  /// a change nobody notices.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.radius.pill),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: t.space.sm, vertical: t.space.xs),
          decoration: BoxDecoration(
            color: selected ? t.accent.active.withValues(alpha: 0.14) : null,
            borderRadius: BorderRadius.circular(t.radius.pill),
            border: Border.all(
              color: selected ? t.accent.active : t.stroke.hairline,
              width: t.stroke.width,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (floating) ...[
                Icon(Icons.layers_outlined,
                    size: 12,
                    color: selected ? t.accent.active : t.accent.primary),
                SizedBox(width: t.space.xs / 2),
              ],
              Icon(icon,
                  size: 13,
                  color: selected ? t.accent.active : t.surface.onBaseMuted),
              SizedBox(width: t.space.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.captionStyle.copyWith(
                      color:
                          selected ? t.surface.onBase : t.surface.onBaseMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
