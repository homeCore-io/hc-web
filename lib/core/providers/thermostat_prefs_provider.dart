import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLargeKey = 'thermostat_large';

/// Which thermostats the user has chosen to show as the full dial rather than
/// the compact gauge — remembered per device, across sessions.
///
/// Every thermostat starts compact; tapping it expands to the dial and pins the
/// choice, collapsing it puts it back. Persisted, because a thermostat you like
/// big is a lasting preference, not a per-visit one.
class ThermostatLargeNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (ref.mounted) state = (p.getStringList(_kLargeKey) ?? const []).toSet();
  }

  Future<void> setLarge(String id, bool large) async {
    state = large ? {...state, id} : (state.toSet()..remove(id));
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kLargeKey, state.toList());
  }
}

final thermostatLargeProvider =
    NotifierProvider<ThermostatLargeNotifier, Set<String>>(
  ThermostatLargeNotifier.new,
);
