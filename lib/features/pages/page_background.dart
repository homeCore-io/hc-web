import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/models/dashboard.dart';
import '../../design/tokens.dart';

/// The layer a page sits on.
///
/// John: *"background image for the page that everything sits on top of with
/// configurable blur."*
///
/// Three layers, in this order, and the order is the design:
///
/// 1. the image, sized to cover;
/// 2. the **blur**, over the image only — the cards on top stay sharp, which is
///    what separates this from a blurred window;
/// 3. the **dim**, a scrim in the page's own base colour.
///
/// Blur and dim are not extras. A photograph behind live content destroys the
/// legibility of everything on it: white text on a bright sky is unreadable and
/// the card borders disappear into the detail. Together they turn a picture
/// into a *surface*, which is the only way a background and a dashboard can
/// share a screen.
///
/// A broken URL leaves the page exactly as it would have been, because a
/// background that fails should cost you a picture and not a dashboard.
class PageBackground extends StatelessWidget {
  const PageBackground({
    super.key,
    required this.background,
    required this.child,
  });

  final DashboardBackground? background;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);
    final bg = background;
    if (bg == null || bg.isEmpty) return child;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Image.network(
            bg.image!,
            fit: BoxFit.cover,
            // Silent: the page is the subject, and an error panel behind every
            // card would be worse than no picture at all. The address is
            // checked where it is typed, not here.
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        if (bg.blur > 0)
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: bg.blur, sigmaY: bg.blur),
              child: const SizedBox.shrink(),
            ),
          ),
        if (bg.dim > 0)
          Positioned.fill(
            // The page's own base colour, not black — dimming towards the skin
            // keeps a light skin light, where black would make every skin the
            // same skin at 60%.
            child: ColoredBox(
              color: t.surface.base.withValues(alpha: bg.dim),
            ),
          ),
        Positioned.fill(child: child),
      ],
    );
  }
}
