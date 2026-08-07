/// Which authored layout a surface should render.
///
/// Brief principle 4: *the room decides the size, not the viewport.* A panel
/// bolted to a wall is read from across a dim room, and the width it reports has
/// nothing to do with that — a 1280px wall panel and a 1280px laptop window want
/// different layouts. [HcShell] is route-derived (`shellFor` in
/// `shell/shell_scope.dart`), so it knows which one it is looking at; raw pixels
/// do not.
///
/// Everything here is pure, so the whole resolution matrix is testable without
/// pumping a widget.
library;

import '../../design/skins.dart';
import '../models/dashboard.dart';

/// The breakpoint a surface *wants*, before checking what the dashboard has.
DashboardBreakpoint resolveDashboardBreakpoint({
  required HcShell shell,
  required double width,
}) =>
    switch (shell) {
      // The wall gets the wall layout at any width. This is the whole point of
      // branching on shell: the same 1280px that means "small laptop" in the
      // hand means "panel across a room" on the wall.
      HcShell.wall => DashboardBreakpoint.tv,
      HcShell.touch => dashboardBreakpointForWidth(width),
    };

/// How wide to draw [b] when previewing it on a screen that is not that size.
///
/// Editing the phone layout on a laptop otherwise arranges it across 1600px —
/// a four-column grid stretched to a shape it will never have, where every card
/// looks like a banner and no judgement you make about it transfers. The
/// numbers sit just inside the thresholds [dashboardBreakpointForWidth] uses,
/// so the preview is a width that really would resolve to that breakpoint.
///
/// Null means "as wide as it gets": desktop and wall are already the big end.
double? previewWidthFor(DashboardBreakpoint b) => switch (b) {
      DashboardBreakpoint.mobile => 430,
      DashboardBreakpoint.tablet => 900,
      DashboardBreakpoint.desktop => 1600,
      DashboardBreakpoint.tv => null,
    };

/// What to fall back to when a dashboard has no layout for [wanted], in order of
/// preference.
///
/// Ordered by how little the substitution hurts: a tv layout stands in for
/// desktop far better than a mobile one does. Without this, [layoutFor] falls
/// back to `layouts.first`, which is whatever order the JSON happened to be in.
const Map<DashboardBreakpoint, List<DashboardBreakpoint>> _fallbackOrder = {
  DashboardBreakpoint.mobile: [
    DashboardBreakpoint.mobile,
    DashboardBreakpoint.tablet,
    DashboardBreakpoint.desktop,
    DashboardBreakpoint.tv,
  ],
  DashboardBreakpoint.tablet: [
    DashboardBreakpoint.tablet,
    DashboardBreakpoint.desktop,
    DashboardBreakpoint.mobile,
    DashboardBreakpoint.tv,
  ],
  DashboardBreakpoint.desktop: [
    DashboardBreakpoint.desktop,
    DashboardBreakpoint.tv,
    DashboardBreakpoint.tablet,
    DashboardBreakpoint.mobile,
  ],
  DashboardBreakpoint.tv: [
    DashboardBreakpoint.tv,
    DashboardBreakpoint.desktop,
    DashboardBreakpoint.tablet,
    DashboardBreakpoint.mobile,
  ],
};

/// The breakpoint [d] can actually serve for [wanted], or null when it has no
/// layouts at all.
DashboardBreakpoint? availableBreakpoint(
  DashboardDefinition d,
  DashboardBreakpoint wanted,
) {
  if (d.layouts.isEmpty) return null;
  final present = {for (final l in d.layouts) l.breakpoint};
  for (final candidate in _fallbackOrder[wanted]!) {
    if (present.contains(candidate)) return candidate;
  }
  return d.layouts.first.breakpoint;
}
