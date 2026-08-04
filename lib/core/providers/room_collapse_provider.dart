import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kCollapsedKey = 'home_rooms_collapsed';

/// Which rooms the user has folded shut on Home — remembered across reloads.
///
/// Collapsing a room to see past it is a glance-time act, not part of the
/// shared house layout (order/hidden/columns live on the dashboard). So it is
/// kept here as a local UI preference — a fast, per-view choice that survives a
/// reload without a dashboard write on every tap. A room absent from this set is
/// open, so a newly installed room is always visible, never folded by default.
class RoomCollapseNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (ref.mounted) state = (p.getStringList(_kCollapsedKey) ?? const []).toSet();
  }

  Future<void> toggle(String key) async {
    state =
        state.contains(key) ? (state.toSet()..remove(key)) : {...state, key};
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kCollapsedKey, state.toList());
  }
}

final roomCollapseProvider =
    NotifierProvider<RoomCollapseNotifier, Set<String>>(
  RoomCollapseNotifier.new,
);
