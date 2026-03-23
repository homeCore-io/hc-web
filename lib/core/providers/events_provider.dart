import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/events_api.dart';
import '../models/hc_event.dart';

final eventsApiProvider = Provider<EventsApi>((ref) {
  final api = EventsApi();
  ref.onDispose(api.dispose);
  return api;
});

final eventsStreamProvider = StreamProvider<HcEvent>((ref) {
  final api = ref.watch(eventsApiProvider);
  return api.connect();
});
