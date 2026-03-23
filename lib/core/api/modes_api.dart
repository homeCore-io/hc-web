import 'homecore_client.dart';

class ModesApi {
  final HomecoreClient client;
  ModesApi(this.client);

  Future<List<Map<String, dynamic>>> listModes() async {
    final response = await client.dio.get('/modes');
    return List<Map<String, dynamic>>.from(response.data as List);
  }

  Future<void> setModeOn(String modeId, bool on) async {
    await client.dio.patch('/devices/$modeId/state', data: {'on': on});
  }
}
