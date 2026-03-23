import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/scenes_api.dart';
import '../models/scene.dart';
import 'auth_provider.dart';

final scenesApiProvider = Provider<ScenesApi>((ref) {
  return ScenesApi(ref.watch(homecoreClientProvider));
});

final scenesProvider = FutureProvider<List<SceneModel>>((ref) async {
  final api = ref.watch(scenesApiProvider);
  final raw = await api.listScenes();
  return raw.map(SceneModel.fromJson).toList();
});
