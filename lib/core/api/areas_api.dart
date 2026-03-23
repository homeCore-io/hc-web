import 'homecore_client.dart';

class AreasApi {
  final HomecoreClient client;
  AreasApi(this.client);

  Future<List<Map<String, dynamic>>> listAreas() async {
    final response = await client.dio.get('/areas');
    return List<Map<String, dynamic>>.from(response.data as List);
  }

  Future<Map<String, dynamic>> createArea(String name) async {
    final response = await client.dio.post('/areas', data: {'name': name});
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> renameArea(String id, String name) async {
    final response =
        await client.dio.patch('/areas/$id', data: {'name': name});
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteArea(String id) async {
    await client.dio.delete('/areas/$id');
  }

  Future<Map<String, dynamic>> setDevices(
      String id, List<String> deviceIds) async {
    final response =
        await client.dio.put('/areas/$id/devices', data: deviceIds);
    return Map<String, dynamic>.from(response.data as Map);
  }
}
