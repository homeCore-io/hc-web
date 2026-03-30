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

  Future<DashboardDefinition> exportDashboard(String id) async {
    final response = await client.dio.get('/dashboards/$id/export');
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
}
