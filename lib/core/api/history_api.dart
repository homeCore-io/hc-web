import 'homecore_client.dart';
import '../models/history_entry.dart';

class HistoryApi {
  final HomecoreClient client;
  HistoryApi(this.client);

  Future<List<HistoryEntry>> getHistory(String deviceId) async {
    final response = await client.dio.get('/devices/$deviceId/history');
    return (response.data as List)
        .map((e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
