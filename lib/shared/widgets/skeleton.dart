import 'package:flutter/material.dart';

import '../../design/components/hc_surface.dart';
import '../../design/tokens.dart';

// ---------------------------------------------------------------------------
// Loading placeholders.
//
// The shimmer itself is HcShimmer, in design/components. This file used to
// carry its own — a second AnimationController, its own gradient, its own
// colours off `Theme.of(context).colorScheme` rather than the tokens. Two
// consequences, both of which showed:
//
//   * its highlight read `surfaceContainerLow`, which `hcTheme` never sets, so
//     the brightest part of every loading state was a Material-derived colour
//     no skin had chosen; and
//   * it called `repeat()` unconditionally in `initState`, so the sheen went on
//     travelling under reduced motion — on every page, before its data arrived,
//     which is the one moment every page has in common.
//
// What was worth keeping was never the mechanism, it was these shapes. So the
// shapes stayed and the mechanism went: HcShimmer already resolves its colours
// from the tokens and already stops itself when the skin says not to move.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// SkeletonListTile — placeholder for a single ListTile row.
// ---------------------------------------------------------------------------

class SkeletonListTile extends StatelessWidget {
  final bool withAvatar;
  const SkeletonListTile({this.withAvatar = true, super.key});

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    // The row a real one will be, so the list does not jump when data lands.
    final avatar = t.density.rowHeight * 0.75;
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: t.space.md, vertical: t.space.sm + 2),
      child: Row(
        children: [
          if (withAvatar) ...[
            HcShimmer(
                width: avatar,
                height: avatar,
                radius: BorderRadius.circular(avatar / 2)),
            SizedBox(width: t.space.md),
          ],
          // Fractions of the row rather than of the window: these sit inside
          // lists and sheets that are routinely narrower than the screen, and
          // MediaQuery does not know that.
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HcShimmer(width: c.maxWidth * 0.45, height: 14),
                  SizedBox(height: t.space.xs + 2),
                  HcShimmer(width: c.maxWidth * 0.3, height: 11),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SkeletonList — N list tile skeletons.
// ---------------------------------------------------------------------------

class SkeletonList extends StatelessWidget {
  final int count;
  final bool withAvatar;

  const SkeletonList({this.count = 8, this.withAvatar = true, super.key});

  @override
  Widget build(BuildContext context) => ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, __) => SkeletonListTile(withAvatar: withAvatar),
      );
}

// ---------------------------------------------------------------------------
// SkeletonCard — placeholder for a card with two lines of text.
// ---------------------------------------------------------------------------

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return Card(
      margin: EdgeInsets.only(bottom: t.space.sm + 4),
      child: Padding(
        padding: EdgeInsets.all(t.density.cardPadding),
        child: LayoutBuilder(
          builder: (context, c) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HcShimmer(width: c.maxWidth * 0.5, height: 16),
              SizedBox(height: t.space.sm + 2),
              HcShimmer(width: c.maxWidth * 0.7, height: 12),
              SizedBox(height: t.space.xs + 2),
              const HcShimmer(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SkeletonCardList — N cards.
// ---------------------------------------------------------------------------

class SkeletonCardList extends StatelessWidget {
  final int count;
  const SkeletonCardList({this.count = 6, super.key});

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    return ListView.builder(
      padding: EdgeInsets.all(t.space.md),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (_, __) => const SkeletonCard(),
    );
  }
}
