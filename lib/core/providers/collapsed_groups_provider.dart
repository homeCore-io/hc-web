import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which section groups the user has collapsed, remembered across sessions.
///
/// Keys are namespaced by section so "Kitchen" in Devices and "Kitchen" in
/// Scenes collapse independently — e.g. `devices:kitchen`, `scenes:kitchen`.
/// Everything starts expanded; only the ids the user has actively collapsed
/// live in the set, so a brand-new group is open by default.
class CollapsedGroupsNotifier extends Notifier<Set<String>> {
  static const _key = 'collapsed_groups';

  @override
  Set<String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (ref.mounted) state = (p.getStringList(_key) ?? const []).toSet();
  }

  Future<void> toggle(String id) async {
    final next = Set<String>.from(state);
    if (!next.remove(id)) next.add(id);
    state = next;
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, next.toList());
  }
}

final collapsedGroupsProvider =
    NotifierProvider<CollapsedGroupsNotifier, Set<String>>(
        CollapsedGroupsNotifier.new);
