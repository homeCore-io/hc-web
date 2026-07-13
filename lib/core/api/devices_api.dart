import 'homecore_client.dart';

class DevicesApi {
  final HomecoreClient client;
  DevicesApi(this.client);

  /// Inlining the schemas costs one request instead of N, and the payload only
  /// grows for the devices that actually have one — 9 of 168 on a real install.
  Future<List<Map<String, dynamic>>> listDevices({
    bool includeSchema = true,
  }) async {
    final response = await client.dio.get(
      '/devices',
      queryParameters: includeSchema ? {'include_schema': true} : null,
    );
    return List<Map<String, dynamic>>.from(response.data as List);
  }

  Future<Map<String, dynamic>> getDevice(String id) async {
    final response = await client.dio.get('/devices/$id');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> setDeviceState(String id, Map<String, dynamic> state) async {
    await client.dio.patch('/devices/$id/state', data: state);
  }

  Future<Map<String, dynamic>> updateDevice(
      String id, Map<String, dynamic> body) async {
    final response = await client.dio.patch('/devices/$id', data: body);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteDevice(String id) async {
    await client.dio.delete('/devices/$id');
  }
}
