import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kCollapsedKey = 'home_rooms_collapsed';

/// Which rooms the user has folded shut on Home — remembered across reloads.
///
/// Collapsing a room to see past it is a glance-time act, not part of the
/// shared house layout (order/hidden/columns live on the dashboard). So it is
/// kept here as a local UI preference — a fast, per-view choice that survives a
/// reload without a dashboard write on every tap. A room absent from this set is
/// open, so a newly installed room is always visible, never folded by default.
class RoomCollapseNotifier extends StateNotifier<Set<String>> {
  RoomCollapseNotifier() : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) state = (p.getStringList(_kCollapsedKey) ?? const []).toSet();
  }

  Future<void> toggle(String key) async {
    state =
        state.contains(key) ? (state.toSet()..remove(key)) : {...state, key};
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kCollapsedKey, state.toList());
  }
}

final roomCollapseProvider =
    StateNotifierProvider<RoomCollapseNotifier, Set<String>>(
  (ref) => RoomCollapseNotifier(),
);
