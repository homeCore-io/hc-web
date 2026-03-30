import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/dashboard.dart';
import 'auth_provider.dart';

const _dashboardsStorageKey = 'hc_web_dashboards_v1';

class DashboardsNotifier extends AsyncNotifier<List<DashboardDefinition>> {
  @override
  Future<List<DashboardDefinition>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUser = await ref.watch(currentUserProvider.future);
    final owner = currentUser?['username'] as String? ?? 'local_user';
    final raw = prefs.getString(_dashboardsStorageKey);
    if (raw == null || raw.isEmpty) {
      final templates = DashboardTemplateFactory.templates(ownerUserId: owner);
      await prefs.setString(
        _dashboardsStorageKey,
        DashboardTemplateFactory.encodeList(templates),
      );
      return templates;
    }
    return DashboardTemplateFactory.decodeList(raw);
  }

  Future<void> _persist(List<DashboardDefinition> dashboards) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _dashboardsStorageKey,
      DashboardTemplateFactory.encodeList(dashboards),
    );
    state = AsyncData(dashboards);
  }

  Future<void> createDashboard(DashboardDefinition dashboard) async {
    final dashboards = [...(state.valueOrNull ?? []), dashboard];
    await _persist(dashboards);
  }

  Future<void> updateDashboard(DashboardDefinition dashboard) async {
    final dashboards = (state.valueOrNull ?? [])
        .map((item) => item.id == dashboard.id ? dashboard : item)
        .toList();
    await _persist(dashboards);
  }

  Future<void> deleteDashboard(String id) async {
    final dashboards =
        (state.valueOrNull ?? []).where((item) => item.id != id).toList();
    await _persist(_normalizeDefault(dashboards));
  }

  Future<void> duplicateDashboard(String id) async {
    final existing =
        (state.valueOrNull ?? []).firstWhere((item) => item.id == id);
    final now = DateTime.now();
    final copy = existing.copyWith(
      id: 'dashboard_${now.microsecondsSinceEpoch}',
      name: '${existing.name} Copy',
      isDefault: false,
      createdAt: now,
      updatedAt: now,
    );
    await createDashboard(copy);
  }

  Future<void> setDefault(String id) async {
    final dashboards = (state.valueOrNull ?? [])
        .map((item) => item.copyWith(
              isDefault: item.id == id,
              updatedAt: DateTime.now(),
            ))
        .toList();
    await _persist(dashboards);
  }

  Future<void> resetTemplates() async {
    final currentUser = await ref.read(currentUserProvider.future);
    final owner = currentUser?['username'] as String? ?? 'local_user';
    await _persist(DashboardTemplateFactory.templates(ownerUserId: owner));
  }

  List<DashboardDefinition> _normalizeDefault(
      List<DashboardDefinition> dashboards) {
    if (dashboards.isEmpty) return dashboards;
    if (dashboards.any((item) => item.isDefault)) return dashboards;
    final first = dashboards.first;
    return [
      first.copyWith(isDefault: true, updatedAt: DateTime.now()),
      ...dashboards.skip(1),
    ];
  }
}

final dashboardsProvider =
    AsyncNotifierProvider<DashboardsNotifier, List<DashboardDefinition>>(
  DashboardsNotifier.new,
);

final defaultDashboardProvider = Provider<DashboardDefinition?>((ref) {
  final dashboards = ref.watch(dashboardsProvider).valueOrNull ?? const [];
  if (dashboards.isEmpty) return null;
  for (final dashboard in dashboards) {
    if (dashboard.isDefault) return dashboard;
  }
  return dashboards.first;
});
