import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kActiveSortKey = 'home_sort_active_first';

/// Whether Home puts the devices that are ON at the top of their room.
///
/// Active-first is the right default: with a hundred-odd devices the handful
/// doing something is the story, and burying a lit lamp between two idle plugs
/// because of its initial makes the page a lookup table.
///
/// But it is a *moving* order — a light switching off re-sorts the room under
/// your cursor, which is maddening when you are working down a list or reaching
/// for the same row twice. So it is a preference, remembered locally like the
/// collapsed-rooms set: a glance-time choice about this view, not part of the
/// shared house layout.
///
/// Off falls back to A–Z, which is stable by construction.
class ActiveSortNotifier extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return true;
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    // Absent means never chosen, and the default is on.
    if (ref.mounted) state = p.getBool(_kActiveSortKey) ?? true;
  }

  Future<void> toggle() async {
    state = !state;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kActiveSortKey, state);
  }
}

final activeSortProvider = NotifierProvider<ActiveSortNotifier, bool>(
  ActiveSortNotifier.new,
);
