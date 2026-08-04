import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../api/scenes_api.dart';
import '../models/scene.dart';
import 'auth_provider.dart';
import 'events_provider.dart';

final scenesApiProvider = Provider<ScenesApi>((ref) {
  return ScenesApi(ref.watch(homecoreClientProvider));
});

final scenesProvider = FutureProvider<List<SceneModel>>((ref) async {
  final api = ref.watch(scenesApiProvider);
  final raw = await api.listScenes();
  return raw.map(SceneModel.fromJson).toList();
});

// Tracks when each scene was last activated (scene_id → DateTime).
// Updated in real-time from the WebSocket event stream.
class SceneActivatedTimesNotifier extends StateNotifier<Map<String, DateTime>> {
  SceneActivatedTimesNotifier(Ref ref) : super(const {}) {
    ref.listen(eventsStreamProvider, (_, next) {
      next.whenData((event) {
        if (event.type == 'scene_activated') {
          final sceneId = event.data['scene_id'] as String?;
          if (sceneId != null) {
            state = Map.unmodifiable({...state, sceneId: event.timestamp});
          }
        }
      });
    });
  }
}

final sceneActivatedTimesProvider =
    StateNotifierProvider<SceneActivatedTimesNotifier, Map<String, DateTime>>(
  (ref) => SceneActivatedTimesNotifier(ref),
);
