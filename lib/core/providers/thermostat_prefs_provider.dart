import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLargeKey = 'thermostat_large';

/// Which thermostats the user has chosen to show as the full dial rather than
/// the compact gauge — remembered per device, across sessions.
///
/// Every thermostat starts compact; tapping it expands to the dial and pins the
/// choice, collapsing it puts it back. Persisted, because a thermostat you like
/// big is a lasting preference, not a per-visit one.
class ThermostatLargeNotifier extends StateNotifier<Set<String>> {
  ThermostatLargeNotifier() : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) state = (p.getStringList(_kLargeKey) ?? const []).toSet();
  }

  Future<void> setLarge(String id, bool large) async {
    state = large ? {...state, id} : (state.toSet()..remove(id));
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kLargeKey, state.toList());
  }
}

final thermostatLargeProvider =
    StateNotifierProvider<ThermostatLargeNotifier, Set<String>>(
  (ref) => ThermostatLargeNotifier(),
);
