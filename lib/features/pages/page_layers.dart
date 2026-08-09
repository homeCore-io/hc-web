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
/// **There is no z-order.** The grid resolves overlap out of existence, so no
/// two cards are ever on top of each other and there is nothing to order. What
/// there is instead is *reading order* — top-left to bottom-right — which is
/// the order you would point at them in, and the one this uses.
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

  /// Reading order: down the page, then across. Not the order the widgets
  /// happen to sit in the document, which is an artefact of the order they were
  /// added and matches nothing you can see.
  List<GridItem> get _ordered {
    final sorted = [...items];
    sorted.sort((a, b) => a.y == b.y ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
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
    final ordered = _ordered;

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
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

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
