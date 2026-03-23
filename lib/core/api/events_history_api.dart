import 'homecore_client.dart';
import '../models/event_entry.dart';

class EventsHistoryApi {
  final HomecoreClient client;
  EventsHistoryApi(this.client);

  Future<List<EventEntry>> listEvents({int limit = 50, String? type, String? deviceId}) async {
    final params = <String, dynamic>{'limit': limit};
    if (type != null) params['type'] = type;
    if (deviceId != null) params['device_id'] = deviceId;
    final response = await client.dio.get('/events', queryParameters: params);
    return (response.data as List)
        .map((e) => EventEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
