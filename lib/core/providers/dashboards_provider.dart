import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/dashboards_api.dart';
import '../models/dashboard.dart';
import 'auth_provider.dart';

final dashboardsApiProvider = Provider<DashboardsApi>((ref) {
  return DashboardsApi(ref.watch(homecoreClientProvider));
});

class DashboardsNotifier extends AsyncNotifier<List<DashboardDefinition>> {
  bool _dashboardApiAvailable = true;

  @override
  Future<List<DashboardDefinition>> build() async {
    final currentUser = await ref.watch(currentUserProvider.future);
    final owner = currentUser?['id'] as String? ??
        currentUser?['username'] as String? ??
        'local_user';
    final api = ref.read(dashboardsApiProvider);
    var dashboards = await _listDashboardsOrFallback(api, owner);
    dashboards = await _ensureGettingStartedDashboard(api, owner, dashboards);
    return dashboards;
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    final currentUser = await ref.read(currentUserProvider.future);
    final owner = currentUser?['id'] as String? ??
        currentUser?['username'] as String? ??
        'local_user';
    state = AsyncData(
      await _listDashboardsOrFallback(ref.read(dashboardsApiProvider), owner),
    );
  }

  Future<void> createDashboard(DashboardDefinition dashboard) async {
    if (!_dashboardApiAvailable) {
      state = AsyncData([...(state.value ?? const []), dashboard]);
      return;
    }
    await ref.read(dashboardsApiProvider).createDashboard(dashboard);
    await reload();
  }

  Future<void> updateDashboard(DashboardDefinition dashboard) async {
    if (!_dashboardApiAvailable) {
      state = AsyncData(
        (state.value ?? const [])
            .map((item) => item.id == dashboard.id ? dashboard : item)
            .toList(),
      );
      return;
    }
    await ref.read(dashboardsApiProvider).updateDashboard(dashboard);
    await reload();
  }

  Future<void> deleteDashboard(String id) async {
    if (!_dashboardApiAvailable) {
      final dashboards =
          (state.value ?? const []).where((item) => item.id != id).toList();
      state = AsyncData(_normalizeDefault(dashboards));
      return;
    }
    await ref.read(dashboardsApiProvider).deleteDashboard(id);
    await reload();
  }

  Future<void> duplicateDashboard(String id) async {
    if (!_dashboardApiAvailable) {
      final existing = (state.value ?? []).firstWhere((item) => item.id == id);
      final now = DateTime.now();
      final copy = existing.copyWith(
        id: 'dashboard_${now.microsecondsSinceEpoch}',
        name: '${existing.name} Copy',
        isDefault: false,
        createdAt: now,
        updatedAt: now,
      );
      await createDashboard(copy);
      return;
    }
    await ref.read(dashboardsApiProvider).duplicateDashboard(id);
    await reload();
  }

  Future<void> importDashboard(DashboardDefinition dashboard) async {
    if (!_dashboardApiAvailable) {
      await createDashboard(dashboard.copyWith(
        id: 'dashboard_${DateTime.now().microsecondsSinceEpoch}',
        isDefault: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      return;
    }
    await ref.read(dashboardsApiProvider).importDashboard(dashboard);
    await reload();
  }

  Future<DashboardDefinition> exportDashboard(String id,
      {bool wired = true}) async {
    if (!_dashboardApiAvailable) {
      return (state.value ?? const []).firstWhere((item) => item.id == id);
    }
    return ref.read(dashboardsApiProvider).exportDashboard(id, wired: wired);
  }

  /// One template, by id.
  ///
  /// From the list core already serves rather than a second endpoint: the list
  /// is small, it is already cached for the picker, and a template that exists
  /// in one place and not the other would be a page you could see and not use.
  Future<DashboardDefinition?> fetchTemplate(String templateId) async {
    final templates = await ref.read(dashboardTemplatesProvider.future);
    return templates.where((t) => t.id == templateId).firstOrNull;
  }

  Future<void> createFromTemplate(String templateId) async {
    final currentUser = await ref.read(currentUserProvider.future);
    final owner = currentUser?['id'] as String? ??
        currentUser?['username'] as String? ??
        'local_user';
    if (!_dashboardApiAvailable) {
      final template = DashboardTemplateFactory.templates(ownerUserId: owner)
          .firstWhere((item) => item.id == templateId);
      await createDashboard(template.copyWith(
        id: 'dashboard_${DateTime.now().microsecondsSinceEpoch}',
        isDefault: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      return;
    }
    await ref.read(dashboardsApiProvider).createFromTemplate(templateId);
    await reload();
  }

  Future<void> setDefault(String id) async {
    if (!_dashboardApiAvailable) {
      state = AsyncData(
        (state.value ?? const [])
            .map((item) => item.copyWith(
                  isDefault: item.id == id,
                  updatedAt: DateTime.now(),
                ))
            .toList(),
      );
      return;
    }
    await ref.read(dashboardsApiProvider).setDefault(id);
    await reload();
  }

  Future<void> resetTemplates() async {
    final currentUser = await ref.read(currentUserProvider.future);
    final owner = currentUser?['id'] as String? ??
        currentUser?['username'] as String? ??
        'local_user';
    if (!_dashboardApiAvailable) {
      state = AsyncData(
        DashboardTemplateFactory.starterDashboards(ownerUserId: owner),
      );
      return;
    }
    final existing = state.value ?? const <DashboardDefinition>[];
    for (final dashboard in existing) {
      if (dashboard.ownerUserId == owner) {
        await ref.read(dashboardsApiProvider).deleteDashboard(dashboard.id);
      }
    }
    await ref
        .read(dashboardsApiProvider)
        .createFromTemplate('starter_getting_started');
    await reload();
  }

  Future<List<DashboardDefinition>> _ensureGettingStartedDashboard(
    DashboardsApi api,
    String owner,
    List<DashboardDefinition> dashboards,
  ) async {
    final starter =
        DashboardTemplateFactory.starterDashboards(ownerUserId: owner).single;

    if (!_dashboardApiAvailable) {
      if (dashboards.isEmpty) return [starter];
      return _normalizeDefault(dashboards);
    }

    if (dashboards.isEmpty) {
      final created = await api.createFromTemplate('starter_getting_started');
      await api.setDefault(created.id);
      return await api.listDashboards();
    }

    final existingStarter = dashboards
        .where((dashboard) =>
            dashboard.id == starter.id || dashboard.name == starter.name)
        .firstOrNull;
    if (existingStarter != null) {
      // One-time icon migration: the starter originally shipped with icon
      // 'home', which renders the identical house glyph to the Home nav item.
      // Re-point stale copies at the template's current icon ('rocket') so the
      // rail reads clearly. Idempotent — only fires while the stored icon is
      // still the legacy 'home'.
      final needsIconFix =
          existingStarter.icon == 'home' && starter.icon != 'home';
      if (needsIconFix) {
        await api.updateDashboard(existingStarter.copyWith(
          icon: starter.icon,
          updatedAt: DateTime.now(),
        ));
      }
      if (!dashboards.any((dashboard) => dashboard.isDefault)) {
        await api.setDefault(existingStarter.id);
        return await api.listDashboards();
      }
      if (needsIconFix) return await api.listDashboards();
      return dashboards;
    }

    final oldHome = dashboards
        .where((dashboard) => dashboard.id == 'template_home_overview')
        .firstOrNull;
    if (oldHome != null) {
      await api.updateDashboard(oldHome.copyWith(
        name: starter.name,
        description: starter.description,
        visibility: starter.visibility,
        tags: starter.tags,
        icon: starter.icon,
        widgets: starter.widgets,
        layouts: starter.layouts,
        updatedAt: DateTime.now(),
      ));
      await api.setDefault(oldHome.id);
      return await api.listDashboards();
    }

    final created = await api.createFromTemplate('starter_getting_started');
    await api.setDefault(created.id);
    return await api.listDashboards();
  }

  Future<List<DashboardDefinition>> _listDashboardsOrFallback(
    DashboardsApi api,
    String owner,
  ) async {
    try {
      _dashboardApiAvailable = true;
      return await api.listDashboards();
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        _dashboardApiAvailable = false;
        return DashboardTemplateFactory.starterDashboards(ownerUserId: owner);
      }
      rethrow;
    }
  }

  List<DashboardDefinition> _normalizeDefault(
    List<DashboardDefinition> dashboards,
  ) {
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
  final dashboards = ref.watch(dashboardsProvider).value ?? const [];
  if (dashboards.isEmpty) return null;
  for (final dashboard in dashboards) {
    if (dashboard.isDefault) return dashboard;
  }
  return dashboards.first;
});

final dashboardTemplatesProvider =
    FutureProvider<List<DashboardDefinition>>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);
  final owner = currentUser?['id'] as String? ??
      currentUser?['username'] as String? ??
      'local_user';
  try {
    return ref.read(dashboardsApiProvider).listTemplates();
  } on DioException catch (error) {
    if (error.response?.statusCode == 404) {
      return DashboardTemplateFactory.templates(ownerUserId: owner);
    }
    rethrow;
  }
});

/// Every dashboard as an access view (owner + grants), for the per-user ACL
/// admin. autoDispose so it reflects edits on reopen.
final dashboardAccessProvider =
    FutureProvider.autoDispose<List<DashboardAccessInfo>>((ref) {
  return ref.watch(dashboardsApiProvider).listAccess();
});
