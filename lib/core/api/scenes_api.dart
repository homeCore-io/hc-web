import 'homecore_client.dart';

class ScenesApi {
  final HomecoreClient client;
  ScenesApi(this.client);

  Future<List<Map<String, dynamic>>> listScenes() async {
    final response = await client.dio.get('/scenes');
    return List<Map<String, dynamic>>.from(response.data as List);
  }

  Future<void> activateScene(String id) async {
    await client.dio.post('/scenes/$id/activate');
  }
}
