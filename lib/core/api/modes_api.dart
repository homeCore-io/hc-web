import 'homecore_client.dart';

class ModesApi {
  late final HomecoreClient client;
  ModesApi(this.client);

  /// For fakes that override the methods they need and never reach the wire —
  /// the same arrangement, and the same reasoning, as [DevicesApi.fake].
  ModesApi.fake();

  Future<List<Map<String, dynamic>>> listModes() async {
    final response = await client.dio.get('/modes');
    return List<Map<String, dynamic>>.from(response.data as List);
  }

  Future<void> setModeOn(String modeId, bool on) async {
    await client.dio.patch('/devices/$modeId/state', data: {'on': on});
  }

  Future<void> createMode(String id, String name, String kind) async {
    await client.dio
        .post('/modes', data: {'id': id, 'name': name, 'kind': kind});
  }

  Future<void> deleteMode(String id) async {
    await client.dio.delete('/modes/$id');
  }

  Future<void> setOffset(String modeId, String field, int minutes) async {
    await client.dio.patch('/devices/$modeId/state', data: {field: minutes});
  }
}
