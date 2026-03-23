import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// SkeletonLoader — provides a shared shimmer animation to all SkeletonBlock
// children in the subtree. Wrap a loading placeholder with this.
// ---------------------------------------------------------------------------

class SkeletonLoader extends StatefulWidget {
  final Widget child;
  const SkeletonLoader({required this.child, super.key});

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => _SkeletonScope(
          value: _controller.value,
          child: widget.child,
        ),
      );
}

class _SkeletonScope extends InheritedWidget {
  final double value;
  const _SkeletonScope({required this.value, required super.child});

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonScope>()?.value ?? 0;

  @override
  bool updateShouldNotify(_SkeletonScope old) => old.value != value;
}

// ---------------------------------------------------------------------------
// SkeletonBlock — single shimmer rectangle.
// ---------------------------------------------------------------------------

class SkeletonBlock extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBlock({
    this.width,
    this.height = 14,
    this.radius = 6,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final t = _SkeletonScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final base = cs.surfaceContainerHighest;
    final highlight = cs.surfaceContainerLow;

    // Shimmer sweep: gradient moves left → right over the duration.
    final sweep = t * 3 - 1; // ranges -1 → 2
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment(sweep - 1, 0),
          end: Alignment(sweep + 1, 0),
          colors: [base, highlight, base],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SkeletonListTile — placeholder for a single ListTile row.
// ---------------------------------------------------------------------------

class SkeletonListTile extends StatelessWidget {
  final bool withAvatar;
  const SkeletonListTile({this.withAvatar = true, super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (withAvatar) ...[
              const SkeletonBlock(width: 40, height: 40, radius: 20),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBlock(
                      width: MediaQuery.of(context).size.width * 0.45,
                      height: 14),
                  const SizedBox(height: 6),
                  SkeletonBlock(
                      width: MediaQuery.of(context).size.width * 0.3,
                      height: 11),
                ],
              ),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// SkeletonList — N list tile skeletons, wrapped in SkeletonLoader.
// ---------------------------------------------------------------------------

class SkeletonList extends StatelessWidget {
  final int count;
  final bool withAvatar;

  const SkeletonList({this.count = 8, this.withAvatar = true, super.key});

  @override
  Widget build(BuildContext context) => SkeletonLoader(
        child: ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, __) => SkeletonListTile(withAvatar: withAvatar),
        ),
      );
}

// ---------------------------------------------------------------------------
// SkeletonCard — placeholder for a card with two lines of text.
// ---------------------------------------------------------------------------

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBlock(
                  width: MediaQuery.of(context).size.width * 0.5, height: 16),
              const SizedBox(height: 10),
              SkeletonBlock(
                  width: MediaQuery.of(context).size.width * 0.7, height: 12),
              const SizedBox(height: 6),
              const SkeletonBlock(height: 12),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// SkeletonCardList — N cards, wrapped in SkeletonLoader.
// ---------------------------------------------------------------------------

class SkeletonCardList extends StatelessWidget {
  final int count;
  const SkeletonCardList({this.count = 6, super.key});

  @override
  Widget build(BuildContext context) => SkeletonLoader(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          itemBuilder: (_, __) => const SkeletonCard(),
        ),
      );
}
