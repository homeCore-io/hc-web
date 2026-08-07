import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/collapsed_groups_provider.dart';
import '../../design/tokens.dart';

/// The one group header every list section uses — light, not a card.
///
/// A room name (amber when something in it is active), a muted count, an
/// optional Room/Zone/Source tag, and an optional right-hand control (a room
/// on/off toggle). A chevron collapses the group; the collapsed state is
/// remembered per [id] across sessions. Modelled on the Devices group header,
/// which is the section grammar everything else now speaks.
class SectionGroupHeader extends ConsumerWidget {
  const SectionGroupHeader({
    super.key,
    required this.id,
    required this.title,
    this.count,
    this.tag,
    this.tagAccent = false,
    this.trailing,
    this.collapsible = true,
  });

  /// Namespaced collapse key, e.g. `scenes:kitchen`.
  final String id;
  final String title;
  final String? count;
  final String? tag;
  final bool tagAccent;
  final Widget? trailing;
  final bool collapsible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final collapsed =
        collapsible && ref.watch(collapsedGroupsProvider).contains(id);

    return InkWell(
      onTap: collapsible
          ? () => ref.read(collapsedGroupsProvider.notifier).toggle(id)
          : null,
      child: Container(
        padding:
            EdgeInsets.fromLTRB(t.space.xs, t.space.md, t.space.xs, t.space.sm),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.stroke.hairline)),
        ),
        child: Row(
          children: [
            if (collapsible)
              AnimatedRotation(
                turns: collapsed ? -0.25 : 0,
                duration: t.motion.fast,
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    size: 18, color: t.surface.onBaseMuted),
              ),
            SizedBox(width: t.space.xs),
            // One expanding left cluster (name · tag · count) so the trailing
            // control always pins to the right edge, aligned across every group.
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.text.bodyStyle.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                          // Room/group titles are always the active amber — a
                          // deliberate, state-independent accent.
                          color: t.accent.active),
                    ),
                  ),
                  if (tag != null) ...[
                    SizedBox(width: t.space.sm),
                    _Tag(tag!, accent: tagAccent),
                  ],
                  if (count != null) ...[
                    SizedBox(width: t.space.sm),
                    Text(count!,
                        style: t.text.captionStyle.copyWith(
                            color: t.surface.onBaseMuted,
                            fontFeatures: t.numericFontFeatures)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              SizedBox(width: t.space.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {required this.accent});
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final c = accent ? t.accent.primary : t.surface.onBaseMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(
            color: accent ? c.withValues(alpha: 0.4) : t.stroke.hairline),
        borderRadius: t.radius.xsR,
      ),
      child: Text(label.toUpperCase(),
          style: t.text.overlineStyle.copyWith(
              fontWeight: FontWeight.w700, letterSpacing: 0.6, color: c)),
    );
  }
}

/// A collapsible group as one box: the [SectionGroupHeader] plus [child],
/// hidden when collapsed. For non-sliver pages (Scenes, grouped lists). In a
/// sliver context (Devices), use [SectionGroupHeader] directly and gate the
/// content sliver on [collapsedGroupsProvider].
class SectionGroup extends ConsumerWidget {
  const SectionGroup({
    super.key,
    required this.id,
    required this.title,
    required this.child,
    this.count,
    this.tag,
    this.tagAccent = false,
    this.trailing,
  });

  final String id;
  final String title;
  final String? count;
  final String? tag;
  final bool tagAccent;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final collapsed = ref.watch(collapsedGroupsProvider).contains(id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionGroupHeader(
          id: id,
          title: title,
          count: count,
          tag: tag,
          tagAccent: tagAccent,
          trailing: trailing,
        ),
        if (!collapsed)
          Padding(
            padding: EdgeInsets.only(top: t.space.md, bottom: t.space.lg),
            child: child,
          ),
      ],
    );
  }
}
