import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/modes_api.dart';
import '../models/mode_state.dart';
import 'auth_provider.dart';

final modesApiProvider = Provider<ModesApi>((ref) {
  return ModesApi(ref.watch(homecoreClientProvider));
});

final modesProvider = FutureProvider<List<ModeState>>((ref) async {
  final api = ref.watch(modesApiProvider);
  final raw = await api.listModes();
  return raw.map(ModeState.fromJson).toList();
});
