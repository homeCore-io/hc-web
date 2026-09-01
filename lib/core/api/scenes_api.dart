import 'homecore_client.dart';

class ScenesApi {
  late final HomecoreClient client;
  ScenesApi(this.client);

  /// For fakes that override the methods they need and never reach the wire —
  /// the same arrangement, and the same reasoning, as [DevicesApi.fake].
  ScenesApi.fake();

  Future<List<Map<String, dynamic>>> listScenes() async {
    final response = await client.dio.get('/scenes');
    return List<Map<String, dynamic>>.from(response.data as List);
  }

  Future<void> activateScene(String id) async {
    await client.dio.post('/scenes/$id/activate');
  }

  Future<Map<String, dynamic>> createScene(Map<String, dynamic> json) async {
    final response = await client.dio.post('/scenes', data: json);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> updateScene(String id, Map<String, dynamic> json) async {
    await client.dio.put('/scenes/$id', data: json);
  }

  Future<void> deleteScene(String id) async {
    await client.dio.delete('/scenes/$id');
  }
}
