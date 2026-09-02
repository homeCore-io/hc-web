import '../models/dashboard.dart';
import 'homecore_client.dart';

class DashboardsApi {
  final HomecoreClient client;
  DashboardsApi(this.client);

  DashboardDefinition _parseDashboard(Map data) {
    final map = Map<String, dynamic>.from(data);
    if (map.containsKey('dashboard') && map['dashboard'] is Map) {
      final nested = Map<String, dynamic>.from(map['dashboard'] as Map);
      nested['is_default'] = map['is_default'] as bool? ?? false;
      return DashboardDefinition.fromJson(nested);
    }
    return DashboardDefinition.fromJson(map);
  }

  Future<List<DashboardDefinition>> listDashboards() async {
    final response = await client.dio.get('/dashboards');
    final items = (response.data as List? ?? const []);
    return items.whereType<Map>().map(_parseDashboard).toList();
  }

  Future<List<DashboardDefinition>> listTemplates() async {
    final response = await client.dio.get('/dashboards/templates');
    final items = (response.data as List? ?? const []);
    return items.whereType<Map>().map(_parseDashboard).toList();
  }

  Future<DashboardDefinition> createDashboard(
    DashboardDefinition dashboard,
  ) async {
    final response =
        await client.dio.post('/dashboards', data: dashboard.toJson());
    return _parseDashboard(Map<String, dynamic>.from(response.data as Map));
  }

  Future<DashboardDefinition> updateDashboard(
    DashboardDefinition dashboard,
  ) async {
    final response = await client.dio.put(
      '/dashboards/${dashboard.id}',
      data: dashboard.toJson(),
    );
    return _parseDashboard(Map<String, dynamic>.from(response.data as Map));
  }

  /// Re-read the dashboard files from disk.
  ///
  /// Dashboards are documents on disk as well as records in core, so editing
  /// one by hand — or restoring a directory of them — leaves core serving what
  /// it loaded at startup until it is told to look again. Admin only.
  Future<void> reload() async {
    await client.dio.post('/dashboards/reload');
  }

  Future<void> deleteDashboard(String id) async {
    await client.dio.delete('/dashboards/$id');
  }

  Future<DashboardDefinition> createFromTemplate(String templateId) async {
    final response = await client.dio.post('/dashboards/templates/$templateId');
    return _parseDashboard(Map<String, dynamic>.from(response.data as Map));
  }

  Future<DashboardDefinition> duplicateDashboard(String id) async {
    final response = await client.dio.post('/dashboards/$id/duplicate');
    return _parseDashboard(Map<String, dynamic>.from(response.data as Map));
  }

  /// A page, on its way out.
  ///
  /// [wired] true keeps the device ids, which is what a BACKUP wants: it is
  /// going home to the house it came from and must restore exactly. False
  /// strips every reference to a labelled slot, which is what SHARING wants:
  /// the ids mean nothing in anybody else's house, and a file full of another
  /// person's bridge serials is not a gift.
  Future<DashboardDefinition> exportDashboard(
    String id, {
    bool wired = true,
  }) async {
    final response = await client.dio.get(
      '/dashboards/$id/export',
      queryParameters: {'wired': wired},
    );
    return _parseDashboard(Map<String, dynamic>.from(response.data as Map));
  }

  Future<DashboardDefinition> importDashboard(
    DashboardDefinition dashboard,
  ) async {
    final response =
        await client.dio.post('/dashboards/import', data: dashboard.toJson());
    return _parseDashboard(Map<String, dynamic>.from(response.data as Map));
  }

  Future<DashboardDefinition> setDefault(String id) async {
    final response = await client.dio.post('/dashboards/$id/default');
    return _parseDashboard(Map<String, dynamic>.from(response.data as Map));
  }

  // ── Per-user access (ACL) ──
  //
  // Kept off the shared DashboardDefinition model on purpose: access is managed
  // from one place (admin → user), and threading a grant list through the whole
  // dashboard model + its copyWith/toJson would ripple far beyond this feature.

  /// Every dashboard as an access view: who owns it and who is granted what.
  /// Reads the same `/dashboards` list the app already serves, plus the `access`
  /// field the server now includes.
  Future<List<DashboardAccessInfo>> listAccess() async {
    final response = await client.dio.get('/dashboards');
    final items = (response.data as List? ?? const []);
    return items.whereType<Map>().map((raw) {
      final m = Map<String, dynamic>.from(raw);
      final d = m['dashboard'] is Map
          ? Map<String, dynamic>.from(m['dashboard'] as Map)
          : m;
      return DashboardAccessInfo.fromJson(d);
    }).toList();
  }

  /// Replace a dashboard's grant list. Owner/admin only (enforced server-side).
  Future<void> setAccess(String id, List<DashboardGrant> grants) async {
    await client.dio.put('/dashboards/$id/access',
        data: {'access': grants.map((g) => g.toJson()).toList()});
  }
}

/// How far a grant reaches. Mirrors the backend `GrantLevel`.
enum DashboardGrantLevel { view, edit }

DashboardGrantLevel? _grantLevelFromWire(String? s) => switch (s) {
      'view' => DashboardGrantLevel.view,
      'edit' => DashboardGrantLevel.edit,
      _ => null,
    };

class DashboardGrant {
  DashboardGrant({required this.userId, required this.level});
  final String userId;
  final DashboardGrantLevel level;

  Map<String, dynamic> toJson() => {'user_id': userId, 'level': level.name};

  factory DashboardGrant.fromJson(Map<String, dynamic> j) => DashboardGrant(
        userId: '${j['user_id']}',
        level: _grantLevelFromWire(j['level'] as String?) ??
            DashboardGrantLevel.view,
      );
}

/// A dashboard reduced to what the access UI needs.
class DashboardAccessInfo {
  DashboardAccessInfo({
    required this.id,
    required this.name,
    required this.ownerUserId,
    required this.grants,
  });
  final String id;
  final String name;
  final String ownerUserId;
  final List<DashboardGrant> grants;

  /// This user's level on this dashboard, or null for none. The owner is
  /// implicit (always full) and never appears in [grants].
  DashboardGrantLevel? levelFor(String userId) {
    if (userId == ownerUserId) return DashboardGrantLevel.edit;
    for (final g in grants) {
      if (g.userId == userId) return g.level;
    }
    return null;
  }

  factory DashboardAccessInfo.fromJson(Map<String, dynamic> j) =>
      DashboardAccessInfo(
        id: '${j['id']}',
        name: j['name'] as String? ?? 'Dashboard',
        ownerUserId: '${j['owner_user_id'] ?? ''}',
        grants: ((j['access'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => DashboardGrant.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
      );
}
