import '../models/dashboard.dart';
import 'homecore_client.dart';

class DashboardsApi {
  final HomecoreClient client;
  DashboardsApi(this.client);

  Future<List<DashboardDefinition>> listDashboards() async {
    final response = await client.dio.get('/dashboards');
    final items = (response.data as List? ?? const []);
    return items
        .whereType<Map>()
        .map((item) =>
            DashboardDefinition.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<DashboardDefinition> createDashboard(
    DashboardDefinition dashboard,
  ) async {
    final response =
        await client.dio.post('/dashboards', data: dashboard.toJson());
    return DashboardDefinition.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<DashboardDefinition> updateDashboard(
    DashboardDefinition dashboard,
  ) async {
    final response = await client.dio.put(
      '/dashboards/${dashboard.id}',
      data: dashboard.toJson(),
    );
    return DashboardDefinition.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<void> deleteDashboard(String id) async {
    await client.dio.delete('/dashboards/$id');
  }

  Future<DashboardDefinition> setDefault(String id) async {
    final response = await client.dio.post('/dashboards/$id/default');
    return DashboardDefinition.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }
}
