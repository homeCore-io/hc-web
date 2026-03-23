import 'homecore_client.dart';

class PluginsApi {
  final HomecoreClient client;
  PluginsApi(this.client);

  Future<List<Map<String, dynamic>>> listPlugins() async {
    final response = await client.dio.get('/plugins');
    return List<Map<String, dynamic>>.from(response.data as List);
  }

  Future<void> deregister(String id) async {
    await client.dio.delete('/plugins/$id');
  }
}
