import 'homecore_client.dart';

class DevicesApi {
  final HomecoreClient client;
  DevicesApi(this.client);

  Future<List<Map<String, dynamic>>> listDevices() async {
    final response = await client.dio.get('/devices');
    return List<Map<String, dynamic>>.from(response.data as List);
  }

  Future<Map<String, dynamic>> getDevice(String id) async {
    final response = await client.dio.get('/devices/$id');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> setDeviceState(String id, Map<String, dynamic> state) async {
    await client.dio.patch('/devices/$id/state', data: state);
  }
}
