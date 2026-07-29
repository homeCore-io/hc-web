import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kRailVisibleKey = 'nav_rail_visible';

/// Whether the persistent nav rail is shown.
///
/// The user asked for both a rail and a hub-launcher, selectable. This is the
/// switch: `true` keeps the collapsible rail on the left (which itself can open
/// the launcher); `false` is "launcher-only" — no persistent chrome at all, just
/// a single hub button that opens the full-screen page grid. Persisted, because
/// which one you prefer is a lasting choice, not a per-session mood.
class NavRailVisibleNotifier extends StateNotifier<bool> {
  NavRailVisibleNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) state = p.getBool(_kRailVisibleKey) ?? true;
  }

  Future<void> set(bool visible) async {
    state = visible;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kRailVisibleKey, visible);
  }

  Future<void> toggle() => set(!state);
}

final navRailVisibleProvider =
    StateNotifierProvider<NavRailVisibleNotifier, bool>(
  (ref) => NavRailVisibleNotifier(),
);

const _kRailExpandedKey = 'nav_rail_expanded';

/// Whether the nav rail is pinned open (labels) or collapsed to icons.
///
/// Manual and persisted: the rail changes width only when the user toggles it —
/// never on hover — so the page content never reflows out from under the
/// pointer. Defaults to collapsed (icons), the quieter resting state.
class NavRailExpandedNotifier extends StateNotifier<bool> {
  NavRailExpandedNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) state = p.getBool(_kRailExpandedKey) ?? false;
  }

  Future<void> set(bool expanded) async {
    state = expanded;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kRailExpandedKey, expanded);
  }

  Future<void> toggle() => set(!state);
}

final navRailExpandedProvider =
    StateNotifierProvider<NavRailExpandedNotifier, bool>(
  (ref) => NavRailExpandedNotifier(),
);

const _kLandingRouteKey = 'landing_route';

/// The route the app opens to on a fresh load — the house by default, or a page
/// the user promoted with "Set as Home page".
///
/// Deliberately a preference, NOT the dashboard `is_default` flag: the house
/// still stores its room arrangement in the default dashboard, so hijacking
/// `is_default` for "which page is home" would move that storage out from under
/// it. Landing is a navigation choice; it lives with navigation.
class LandingRouteNotifier extends StateNotifier<String> {
  LandingRouteNotifier() : super('/') {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) state = p.getString(_kLandingRouteKey) ?? '/';
  }

  Future<void> set(String route) async {
    state = route;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLandingRouteKey, route);
  }
}

final landingRouteProvider =
    StateNotifierProvider<LandingRouteNotifier, String>(
  (ref) => LandingRouteNotifier(),
);
