import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/automations_api.dart';
import '../rules/rule.dart';
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

  /// Applies [change] to the rule with [id] in place, leaving the rest alone.
  void _patchLocal(
      bool Function(HcRule) matches, void Function(HcRule) change) {
    final current = state.valueOrNull ?? [];
    state = AsyncData([
      for (final r in current)
        if (matches(r)) (r.copy()..let(change)) else r,
    ]);
  }

  Future<void> toggle(String id, bool enabled) async {
    await ref.read(automationsApiProvider).patchRule(id, {'enabled': enabled});
    _patchLocal((r) => r.id == id, (r) => r.enabled = enabled);
  }

  Future<void> delete(String id) async {
    await ref.read(automationsApiProvider).deleteRule(id);
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.where((r) => r.id != id).toList());
  }

  Future<HcRule> save(HcRule rule) async {
    final api = ref.read(automationsApiProvider);
    final saved = rule.id.isEmpty
        ? await api.createRule(rule)
        : await api.updateRule(rule);

    final current = state.valueOrNull ?? [];
    final next = [...current];
    final existing = next.indexWhere((r) => r.id == saved.id);
    if (existing >= 0) {
      next[existing] = saved;
    } else {
      next.add(saved);
    }
    state = AsyncData(next);
    return saved;
  }

  Future<String> clone(String id) async {
    final cloned = await ref.read(automationsApiProvider).cloneRule(id);
    final current = state.valueOrNull ?? [];
    state = AsyncData([...current, cloned]);
    return cloned.id;
  }

  Future<void> bulkSetEnabled(List<String> ids, bool enabled) async {
    // A bulk PATCH with no selector is a 400 by design — it once disabled every
    // rule in the house — so never call this with an empty id list.
    if (ids.isEmpty) return;
    await ref
        .read(automationsApiProvider)
        .bulkPatch({'ids': ids, 'enabled': enabled});
    _patchLocal((r) => ids.contains(r.id), (r) => r.enabled = enabled);
  }
}

extension<T> on T {
  void let(void Function(T) f) => f(this);
}

final automationsProvider =
    AsyncNotifierProvider<AutomationsNotifier, List<HcRule>>(
  AutomationsNotifier.new,
);
