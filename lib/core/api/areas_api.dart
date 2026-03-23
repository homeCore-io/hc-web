import 'homecore_client.dart';

class AreasApi {
  final HomecoreClient client;
  AreasApi(this.client);

  Future<List<Map<String, dynamic>>> listAreas() async {
    final response = await client.dio.get('/areas');
    return List<Map<String, dynamic>>.from(response.data as List);
  }
}
