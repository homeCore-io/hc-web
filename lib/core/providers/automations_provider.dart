import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/automations_api.dart';
import '../models/rule.dart';
import 'auth_provider.dart';

final automationsApiProvider = Provider<AutomationsApi>((ref) {
  return AutomationsApi(ref.watch(homecoreClientProvider));
});

class AutomationsNotifier extends AsyncNotifier<List<HcRule>> {
  @override
  Future<List<HcRule>> build() async {
    return ref.read(automationsApiProvider).listRules();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(automationsApiProvider).listRules());
  }

  Future<void> toggle(String id, bool enabled) async {
    await ref.read(automationsApiProvider).patchRule(id, {'enabled': enabled});
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.map((r) => r.id == id
        ? HcRule(
            id: r.id,
            name: r.name,
            enabled: enabled,
            priority: r.priority,
            cooldownSecs: r.cooldownSecs,
            runMode: r.runMode,
            maxQueue: r.maxQueue,
            trigger: r.trigger,
            conditions: r.conditions,
            actions: r.actions,
            tags: r.tags,
            error: r.error)
        : r).toList());
  }

  Future<void> delete(String id) async {
    await ref.read(automationsApiProvider).deleteRule(id);
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.where((r) => r.id != id).toList());
  }

  Future<String> clone(String id) async {
    final cloned = await ref.read(automationsApiProvider).cloneRule(id);
    final current = state.valueOrNull ?? [];
    state = AsyncData([...current, cloned]);
    return cloned.id;
  }

  Future<void> bulkSetEnabled(List<String> ids, bool enabled) async {
    await ref.read(automationsApiProvider).bulkPatch({'ids': ids, 'enabled': enabled});
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.map((r) =>
      ids.contains(r.id) ? HcRule(
        id: r.id, name: r.name, enabled: enabled,
        priority: r.priority, cooldownSecs: r.cooldownSecs,
        runMode: r.runMode, maxQueue: r.maxQueue,
        trigger: r.trigger, conditions: r.conditions,
        actions: r.actions, tags: r.tags, error: r.error,
      ) : r).toList());
  }
}

final automationsProvider =
    AsyncNotifierProvider<AutomationsNotifier, List<HcRule>>(
  AutomationsNotifier.new,
);
